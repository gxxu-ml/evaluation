projdir := justfile_directory()

[private]
default:
    just --list

link-rc model_path:
    #!/usr/bin/env bash
    if [ ! -d {{projdir / "ibm"}} ]; then
        mkdir {{projdir / "ibm"}}
    fi
    ln -s {{model_path}} {{projdir / "ibm" / "merlinite-7b-rc"}}

prepare-bench *args:
    ./scripts/prepare_fschat_bench.sh {{args}}

prepare-local model_path:
    #!/usr/bin/env bash
    REPO_ROOT=$(pwd)

    if [ ! -d "venv" ]; then
        echo "Creating a virtual environment..."
        python -m venv venv
        source venv/bin/activate
        pip install -U setuptools
    fi

    if [ ! -d "FastChat" ]; then
        git clone --quiet https://github.com/xukai92/FastChat.git
        cd $REPO_ROOT/FastChat
        if [[ "{{model_path}}" == ibm/* ]] || [[ "{{model_path}}" =~ (merlinite|granite) ]]; then
            git switch ilab
            pip install git+https://${GH_IBM_TOKEN}@github.ibm.com/ai-models-architectures/IBM-models.git@0.1.1
            pip install instructlab-dolomite

        else
            git switch main
        fi
        # switch to main if llama-3 in model_path
        if [[ "{{model_path}}" == *llama-3* ]]; then
            git switch main
        fi
        # switch to main if mistral in model_path
        if [[ "{{model_path}}" == *sw-mistral* ]]; then
            git switch main
        fi
        # switch to main if mistral in model_path
        if [[ "{{model_path}}" == *g8b* ]]; then
            git switch main
            pip install git+https://github.com/huggingface/transformers
        fi
        # switch to main if mistral in model_path
        if [[ "{{model_path}}" == *rh8b* ]]; then
            git switch main
            pip install git+https://github.com/huggingface/transformers
        fi
        pip install --quiet -e ".[model_worker]"
        pip install wandb matplotlib pandas pygithub ibmcloudant tenacity # for analysis.py
    fi

start-local model_name model_path="" max_worker_id="4":
    #!/usr/bin/env bash
    REPO_ROOT=$(pwd)

    if [ "{{model_path}}" = "" ]; then
        model_path="ibm/{{model_name}}"
    else
        model_path={{model_path}}
    fi

    just prepare-local $model_path
    source venv/bin/activate
    
    cd $REPO_ROOT

    if [ $(screen -ls | grep controller | wc -l) -eq 0 ]; then
        screen -dmS controller -- python -m fastchat.serve.controller
    fi

    sleep 20
    if [[ {{max_worker_id}} == "0" ]]; then
        # assuming CUDA_VISIBLE_DEVICES is set to only 1 number
        screen -dmS worker-$CUDA_VISIBLE_DEVICES -- python -m fastchat.serve.model_worker \
                --model-path ${model_path} \
                --model-name {{model_name}} \
                --port 3100$CUDA_VISIBLE_DEVICES \
                --worker http://localhost:3100$CUDA_VISIBLE_DEVICES
    else
        for i in {0..{{max_worker_id}}}
        do
            CUDA_VISIBLE_DEVICES=$i screen -dmS worker-$i -- python -m fastchat.serve.model_worker \
                --model-path ${model_path} \
                --model-name {{model_name}}-$i \
                --port 3100$i \
                --worker http://localhost:3100$i
        done
    fi
    sleep 40

    if [ $(screen -ls | grep server | wc -l) -eq 0 ]; then
        screen -dmS server -- python -m fastchat.serve.openai_api_server \
            --host localhost \
            --port 8000
    fi

run-bench workspace model bench_name max_worker_id="4" endpoint="http://localhost:8000/v1":
    #!/usr/bin/env bash

    REPO_ROOT=$(pwd)
    WORKSPACE=$(realpath {{workspace}})

    cd $WORKSPACE
    source venv/bin/activate

    cd $WORKSPACE/FastChat/fastchat/llm_judge

    if [[ {{max_worker_id}} == "0" ]]; then
        OPENAI_API_KEY="NO_API_KEY" screen -dmS bench-$CUDA_VISIBLE_DEVICES -- python gen_api_answer.py \
            --bench-name {{bench_name}} \
            --openai-api-base {{endpoint}} \
            --model "{{model}}" \
            --num-choices 1
    else
        for i in {0..{{max_worker_id}}}
        do
            OPENAI_API_KEY="NO_API_KEY" screen -dmS bench-$i -- python gen_api_answer.py \
                --bench-name {{bench_name}} \
                --openai-api-base {{endpoint}} \
                --model "{{model}}-$i" \
                --num-choices 1
        done
    fi
    cd $REPO_ROOT

run-judge workspace model bench_name max_worker_id="4" judge_model="gpt-4":
    #!/usr/bin/env bash

    REPO_ROOT=$(pwd)
    WORKSPACE=$(realpath {{workspace}})

    cd $WORKSPACE
    source venv/bin/activate

    cd $WORKSPACE/FastChat/fastchat/llm_judge

    if [ "{{judge_model}}" == "gpt-4-turbo" ]; then
        parallel=40
    else
        parallel=10
    fi
    
    model_list=""
    if [[ {{max_worker_id}} == "0" ]]; then
        model_list+="{{model}}"
    else
        for i in $(seq 0 {{max_worker_id}})
        do
            model_list+="{{model}}-$i "
        done
    fi

    if [ -z "$EVAL_OAI_BATCH" ] || [ "$EVAL_OAI_BATCH" != "0" ]; then
        OPENAI_API_KEY=${OPENAI_API_KEY} python gen_judgment.py \
            --bench-name {{bench_name}} \
            --model-list $model_list \
            --judge-model {{judge_model}} \
            --batch \
            --yes

        /home/lab/.conda/envs/ilab/bin/python submit_and_wait_batch.py data/mt_bench/model_judgment/gpt-4_single-batch.jsonl data/mt_bench/model_judgment/gpt-4_single-batch-output.jsonl

        OPENAI_API_KEY=${OPENAI_API_KEY} python gen_judgment.py \
            --bench-name {{bench_name}} \
            --model-list $model_list \
            --judge-model {{judge_model}} \
            --batch \
            --yes
    else
        if [ -z "$EVAL_USE_P2" ] || [ "$EVAL_USE_P2" != "0" ]; then
            pkill screen

            just vllm-p2 &
            sleep 300

            OPENAI_API_BASE=http://0.0.0.0:8080/v1 OPENAI_API_KEY=NO_API_KEY ILAB_EVAL_MERGE_SYS_USR=1 python gen_judgment.py \
            --bench-name {{bench_name}} \
            --model-list $model_list \
            --judge-model {{judge_model}} \
            --parallel $parallel \
            --yes
        else
            OPENAI_API_KEY=${OPENAI_API_KEY} python gen_judgment.py \
            --bench-name {{bench_name}} \
            --model-list $model_list \
            --judge-model {{judge_model}} \
            --parallel $parallel \
            --yes
        fi
    fi

    python show_result.py --bench-name {{bench_name}} --judge-model {{judge_model}}



run-judge-batch workspace model_name_ls bench_name:
    #!/usr/bin/env bash

    IFS=',' read -r -a model_names <<< {{model_name_ls}}
    REPO_ROOT=$(pwd)
    WORKSPACE=$(realpath {{workspace}})

    cd $WORKSPACE
    source venv/bin/activate

    cd $WORKSPACE/FastChat/fastchat/llm_judge
    
    model_list=""
    for i in "${!model_names[@]}";
    do
        model_list+="${model_names[$i]} "
    done

    if [ -z "$EVAL_USE_P2" ] || [ "$EVAL_USE_P2" != "0" ]; then
        pkill screen

        just vllm-p2 &
        sleep 180

        OPENAI_API_BASE=http://0.0.0.0:8080/v1 OPENAI_API_KEY=NO_API_KEY ILAB_EVAL_MERGE_SYS_USR=1 python gen_judgment.py \
        --bench-name {{bench_name}} \
        --model-list $model_list \
        --judge-model prometheus \
        --parallel 40 \
        --yes

        python show_result.py --bench-name {{bench_name}} --judge-model prometheus
    else
        # default to GPT4 if P2 not used.
        export EVAL_USE_GPT4="1"
    fi
    
    if [ -z "$EVAL_USE_GPT4" ] || [ "$EVAL_USE_GPT4" != "0" ]; then
        OPENAI_API_KEY=${OPENAI_API_KEY} python gen_judgment.py \
        --bench-name {{bench_name}} \
        --model-list $model_list \
        --judge-model gpt-4 \
        --parallel 20 \
        --yes
        python show_result.py --bench-name {{bench_name}} --judge-model gpt-4
    fi


    


run-bench-judge workspace model bench_name max_worker_id="4" judge_model="gpt-4":
    echo "Running MT-Bench (generation)..."
    just run-bench {{workspace}} {{model}} {{bench_name}} {{max_worker_id}}
    just wait-for-run-bench
    echo "...Done running MT-Bench (generation)!"

    echo "Running MT-Bench (judgement)..."
    just run-judge {{workspace}} {{model}} {{bench_name}} {{max_worker_id}} {{judge_model}}
    echo "...Done running MT-Bench (judgement)!"

quick-sync:
    #!/usr/bin/env bash
    git add --update
    git commit -m "quick sync"
    git push

run-eval model:
    echo "Starting server for {{model}}..."
    just start-local {{model}}
    echo "...Done starting server!"

    just run-bench-judge ws-mt {{model}} mt_bench

    just run-bench-judge ws-pr {{model}} pr_bench

run-all rc_branch_name rc_model_path:
    #!/usr/bin/env bash
    echo "Evaluating current model and RC model from {{rc_model_path}}..."

    echo "Preparing workspaces for MT-Bench and PR-Bench..."
    just prepare-bench ws-mt
    just prepare-bench ws-pr {{rc_branch_name}}
    echo "...Done reparing workspaces!"

    just link-rc {{rc_model_path}}

    echo "Evaluating current model..."
    just run-eval merlinite-7b
    echo "...Done evaluating current model!"

    echo "Killing current model..."
    pkill screen
    echo "...Done killing current model!"

    echo "Evaluating RC model..."
    just run-eval merlinite-7b-rc
    echo "...Done evaluating RC model!"

    echo "Killing current model..."
    pkill screen
    echo "...Done killing current model!"
    
    echo "...Done evaluating current model and RC model!"

wait-for-run-bench:
    #!/usr/bin/env bash
    while [ $(screen -ls | grep bench | wc -l) -ne 0 ]
    do
        echo "Still running run-bench.."
        sleep 30
    done

run-mt model_name model_path max_worker_id="4" judge_model="gpt-4" cuda_devices="":
    #!/usr/bin/env bash
    if [[ ! "{{cuda_devices}}" == "" ]]; then
        export CUDA_VISIBLE_DEVICES={{cuda_devices}}
    fi
    echo "Running with CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"

    echo "Preparing workspace for MT-Bench"
    test -d {{projdir}}/ws-mt || just prepare-bench ws-mt
    echo "...Done reparing workspaces!"

    echo "Starting server for {{model_name}} using {{model_path}}..."
    just start-local {{model_name}} {{model_path}} {{max_worker_id}}
    echo "...Done starting server!"

    just run-bench-judge ws-mt {{model_name}} mt_bench {{max_worker_id}} {{judge_model}}

    echo "Killing current model..."
    pkill screen
    echo "...Done killing current model!"

    cp -r {{projdir}}/ws-mt/FastChat/fastchat/llm_judge/data/mt_bench {{model_path}}

run-mt-dir model_name model_dir:
    #!/usr/bin/env bash

    fns=(`ls {{model_dir}}`)

    for fn in "${fns[@]}"; do
        just run-mt {{model_name}}-${fn##*_} {{model_dir}}/$fn
    done


start-local-batch model_name_ls:
    #!/usr/bin/env bash
    REPO_ROOT=$(pwd)

    IFS=',' read -r -a model_names <<< {{model_name_ls}}
    
    just prepare-local "ibm/${model_names[0]}"
    source venv/bin/activate

    cd $REPO_ROOT

    if [ $(screen -ls | grep controller | wc -l) -eq 0 ]; then
        screen -dmS controller -- python -m fastchat.serve.controller
    fi

    sleep 20

    for i in "${!model_names[@]}";
    do
        echo "ibm/${model_names[$i]}"
        CUDA_VISIBLE_DEVICES=$i screen -dmS worker-$i -- python -m fastchat.serve.model_worker \
            --model-path "ibm/${model_names[$i]}" \
            --model-name ${model_names[$i]} \
            --port 3100$i \
            --worker http://localhost:3100$i
    done

    sleep 40

    if [ $(screen -ls | grep server | wc -l) -eq 0 ]; then
        screen -dmS server -- python -m fastchat.serve.openai_api_server \
            --host localhost \
            --port 8000
    fi

run-bench-batch model_name_ls workspace="ws-mt" bench_name="mt_bench" endpoint="http://localhost:8000/v1":
    #!/usr/bin/env bash
    test -d {{projdir}}/{{workspace}} || just prepare-bench {{workspace}}
    IFS=',' read -r -a model_names <<< {{model_name_ls}}

    REPO_ROOT=$(pwd)
    WORKSPACE=$(realpath {{workspace}})

    cd $WORKSPACE
    source venv/bin/activate
    
    cd $WORKSPACE/FastChat/fastchat/llm_judge

    for i in "${!model_names[@]}";
    do
        OPENAI_API_KEY="NO_API_KEY" screen -dmS bench-$i -- python gen_api_answer.py \
            --bench-name {{bench_name}} \
            --openai-api-base {{endpoint}} \
            --model ${model_names[$i]} \
            --num-choices 1 | tee $WORKSPACE/FastChat/fastchat/llm_judge/data/mt_bench/${model_names[$i]}.log
    done
    cd $REPO_ROOT

    just wait-for-run-bench
    echo "...Done running MT-Bench (generation) for current batch!"

    echo "Killing current model..."
    pkill screen
    echo "...Done killing current batch of models!"



run-mt-dir-parallel model_name model_dir every="1" max_checkpoints="16": && (run-mt-dir-parallel-core model_name model_dir every max_checkpoints)
    #!/usr/bin/env julia
    fns = readdir("{{model_dir}}")


run-mt-dir-parallel-core model_name model_dir every="1" max_checkpoints="16": 
    #!/usr/bin/env -S julia -t 8
    
    # run(`just prepare-bench ws-mt`) # init bench venv for all
    fns = readdir("{{model_dir}}")

    # Function to extract numeric suffix safely
    function extract_suffix(folder)
        parts = split(folder, "_")
        parts2 = split(folder, "-")
        # for samples_1234
        if length(parts) == 2 && parts[1] == "samples" && all(isdigit, parts[2])
            return parse(Int, parts[2]), folder
        # for checkpoint-1234
        elseif length(parts2) == 2 && parts2[1] == "checkpoint" && all(isdigit, parts2[2])
            return parse(Int, parts2[2]), folder
        else
            return nothing
        end
    end

    # Extract the numeric suffixes and pair them with the original folder names, skipping invalid ones
    paired = filter(!isnothing, [extract_suffix(folder) for folder in fns])

    # Sort the pairs based on the numeric suffix
    sorted_paired = sort(paired)
    
    # Extract the sorted folder names
    fns = [pair[2] for pair in sorted_paired]

    fns = collect(fns[1:{{every}}:end])
    fns = fns[1:min(length(fns),{{max_checkpoints}})]

    println("$(length(fns)) checkpoints to process...")

    # Create soft-links
    run(`mkdir -p ibm`)
    for (i, fn) in enumerate(fns)
        target = joinpath("{{model_dir}}", fn)
        link = joinpath("ibm", "{{model_name}}-$fn")
        run(`ln -sf $target $link`)
    end

    # # Split checkpoints into batches of up to 8
    batches = [fns[i:min(i+8-1, length(fns))] for i in 1:8:length(fns)]
    
    for batch in batches
        model_name_ls = join("{{model_name}}-" .* batch, ",")
        run(`echo $model_name_ls`)
        run(`just start-local-batch $model_name_ls`)
        run(`just run-bench-batch $model_name_ls`)
    end

    full_model_name_ls = join("{{model_name}}-" .* fns, ",")

    run(`just run-judge-batch ws-mt $full_model_name_ls mt_bench`)
    run(`cp -r ws-mt/FastChat/fastchat/llm_judge/data/mt_bench {{model_dir}}`)



vllm-p2 port="8080":
    #!/usr/bin/env bash

    export PATH="${HOME}/.conda/envs/vllm/bin:${PATH}"

    if ! ray status > /dev/null 2>&1; then
        ray start --head --num-cpus=32 --num-gpus=8 --disable-usage-stats
    else
        echo "Ray server is already running..."
    fi

    check_success() {
        local file=$1
        local message="Started server process"
        if [ ! -f "$file" ]; then
            echo "Log file $file does not exist."
            return 1
        fi
        # Tail the log file and grep for success message, exit when found
        tail -f "$file" | grep -q "$message"
        echo "Server at $file has started successfully."
        return 0
    }
    # if returns 1, then it failed
    if ! check_success vllm_server.log; then
        python -m vllm.entrypoints.openai.api_server \
            --port {{port}} \
            --model prometheus-eval/prometheus-8x7b-v2.0 \
            --dtype float16 \
            --tensor-parallel-size 8 \
            --served-model-name prometheus > vllm_server.log &
    else
        echo "Server already started."
    fi

###

query model content port="8000":
    #!/usr/bin/env bash

    curl http://localhost:{{port}}/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "{{model}}",
            "messages": [{"role": "user", "content": "{{content}}"}],
            "max_tokens": 1024
        }'
