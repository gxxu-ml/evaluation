projdir := justfile_directory()

[private]
default:
    just --list

link_rc model_path:
    #!/usr/bin/env bash
    if [ ! -d {{projdir / "ibm"}} ]; then
        mkdir {{projdir / "ibm"}}
    fi
    ln -s {{model_path}} {{projdir / "ibm" / "merlinite-7b-rc"}}

prepare_bench *args:
    ./scripts/prepare_fschat_bench.sh {{args}}

prepare_local model_path:
    #!/usr/bin/env bash
    REPO_ROOT=$(pwd)

    if [ ! -d "venv" ]; then
        echo "Creating a virtual environment..."
        python -m venv venv
        source venv/bin/activate
        pip install -U setuptools
        installed=0
    else
        source venv/bin/activate
        installed=1
    fi

    if [ ! -d "FastChat" ]; then
        git clone --quiet https://github.com/xukai92/FastChat.git
    fi
    cd $REPO_ROOT/FastChat
    if [[ "{{model_path}}" == ibm/* ]] || [[ "{{model_path}}" =~ (merlinite|granite) ]]; then
        git switch ilab
        if [[ "$installed" == "0" ]]; then
            pip install git+https://${GH_IBM_TOKEN}@github.ibm.com/ai-models-architectures/IBM-models.git@0.1.1
        fi
    else
        git switch main
    fi
    if [[ "$installed" == "0" ]]; then
        pip install --quiet -e ".[model_worker]"
        # for analysis.py
        pip install wandb matplotlib pandas pygithub ibmcloudant tenacity
    fi

start_local model_name model_path="" max_worker_id="4":
    #!/usr/bin/env bash
    REPO_ROOT=$(pwd)

    if [ "{{model_path}}" = "" ]; then
        model_path="ibm/{{model_name}}"
    else
        model_path={{model_path}}
    fi

    just prepare_local $model_path
    
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

run_bench workspace model bench_name max_worker_id="4" endpoint="http://localhost:8000/v1":
    #!/usr/bin/env bash

    REPO_ROOT=$(pwd)
    WORKSPACE=$(realpath {{workspace}})

    cd $WORKSPACE
    source venv/bin/activate

    cd $WORKSPACE/FastChat/fastchat/llm_judge

    if [[ {{max_worker_id}} == "0" ]]; then
        OPENAI_API_KEY="NO_API_KEY" screen -dmS run-bench-$CUDA_VISIBLE_DEVICES -- python gen_api_answer.py \
            --bench-name {{bench_name}} \
            --openai-api-base {{endpoint}} \
            --model "{{model}}" \
            --num-choices 1
    else
        for i in {0..{{max_worker_id}}}
        do
            OPENAI_API_KEY="NO_API_KEY" screen -dmS run-bench-$i -- python gen_api_answer.py \
                --bench-name {{bench_name}} \
                --openai-api-base {{endpoint}} \
                --model "{{model}}-$i" \
                --num-choices 1
        done
    fi
    cd $REPO_ROOT

run_judge workspace model bench_name max_worker_id="4" judge_model="gpt-4":
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

    OPENAI_API_KEY=${OPENAI_API_KEY} python gen_judgment.py \
        --bench-name {{bench_name}} \
        --model-list $model_list \
        --judge-model {{judge_model}} \
        --parallel $parallel \
        --yes

    python show_result.py --bench-name {{bench_name}} --judge-model {{judge_model}}

run_bench_judge workspace model bench_name max_worker_id="4" judge_model="gpt-4":
    echo "Running MT-Bench (generation)..."
    just run_bench {{workspace}} {{model}} {{bench_name}} {{max_worker_id}}
    just wait_for_run_bench
    echo "...Done running MT-Bench (generation)!"

    echo "Running MT-Bench (judgement)..."
    just run_judge {{workspace}} {{model}} {{bench_name}} {{max_worker_id}} {{judge_model}}
    echo "...Done running MT-Bench (judgement)!"

quick-sync:
    #!/usr/bin/env bash
    git add --update
    git commit -m "quick sync"
    git push

run_eval model:
    echo "Starting server for {{model}}..."
    just start_local {{model}}
    echo "...Done starting server!"

    just run_bench_judge ws-mt {{model}} mt_bench

    just run_bench_judge ws-pr {{model}} pr_bench

run_all rc_branch_name rc_model_path:
    #!/usr/bin/env bash
    echo "Evaluating current model and RC model from {{rc_model_path}}..."

    echo "Preparing workspaces for MT-Bench and PR-Bench..."
    just prepare_bench ws-mt
    just prepare_bench ws-pr {{rc_branch_name}}
    echo "...Done reparing workspaces!"

    just link_rc {{rc_model_path}}

    echo "Evaluating current model..."
    just run_eval merlinite-7b
    echo "...Done evaluating current model!"

    echo "Killing current model..."
    pkill screen
    echo "...Done killing current model!"

    echo "Evaluating RC model..."
    just run_eval merlinite-7b-rc
    echo "...Done evaluating RC model!"

    echo "Killing current model..."
    pkill screen
    echo "...Done killing current model!"
    
    echo "...Done evaluating current model and RC model!"

wait_for_run_bench:
    #!/usr/bin/env bash
    while [ $(screen -ls | grep run-bench | wc -l) -ne 0 ]
    do
        echo "Still running run_bench.."
        sleep 30
    done

run_mt model_name model_path max_worker_id="4" judge_model="gpt-4" cuda_devices="":
    #!/usr/bin/env bash
    if [[ ! "{{cuda_devices}}" == "" ]]; then
        export CUDA_VISIBLE_DEVICES={{cuda_devices}}
    fi
    echo "Running with CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"

    echo "Preparing workspace for MT-Bench"
    test -d {{projdir}}/ws-mt || just prepare_bench ws-mt
    echo "...Done reparing workspaces!"

    echo "Starting server for {{model_name}} using {{model_path}}..."
    just start_local {{model_name}} {{model_path}} {{max_worker_id}}
    echo "...Done starting server!"

    just run_bench_judge ws-mt {{model_name}} mt_bench {{max_worker_id}} {{judge_model}}

    echo "Killing current model..."
    pkill screen
    echo "...Done killing current model!"

    cp -r {{projdir}}/ws-mt/FastChat/fastchat/llm_judge/data/mt_bench {{model_path}}

run_mt_dir model_name model_dir:
    #!/usr/bin/env bash

    fns=(`ls {{model_dir}}`)

    for fn in "${fns[@]}"; do
        just run_mt {{model_name}}-${fn##*_} {{model_dir}}/$fn
    done

run_mt_dir_parallel model_name model_dir every="1": && (run_mt_dir_parallel_core model_name model_dir every)
    #!/usr/bin/env julia
    fns = readdir("{{model_dir}}")
    fns = collect(fns[1:{{every}}:end])
    println("$(length(fns)) checkpoints to process...")

[confirm]
run_mt_dir_parallel_core model_name model_dir every="1": 
    #!/usr/bin/env -S julia -t 8
    run(`just prepare_bench ws-mt`) # init bench venv for all
    model_name = "{{model_name}}"
    fns = readdir("{{model_dir}}")
    fns = collect(fns[1:{{every}}:end])
    run(`just prepare_local {{model_dir}}/$(fns[1])`) # init worker venv for all
    Threads.@threads for fn in fns
        m = match(r"samples_(\d+)", fn)
        if !isnothing(m)
            num_samples = parse(Int, m[1])
            cuda_dev = Threads.threadid() - 1
            cmd = `just run_mt $model_name-$num_samples {{model_dir}}/$fn 0 gpt-4 $cuda_dev`
            @info "running" cuda_dev cmd
            run(cmd)
        end
    end

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
