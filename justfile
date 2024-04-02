projdir := justfile_directory()

[private]
default:
    ./just --list

link_rc model_path:
    #!/usr/bin/env bash
    if [ ! -d {{projdir / "ibm"}} ]; then
        mkdir {{projdir / "ibm"}}
    fi
    ln -s {{model_path}} {{projdir / "ibm" / "merlinite-7b-rc"}}

prepare_bench *args:
    ./scripts/prepare_fschat_bench.sh {{args}}

start_local model_name org="ibm":
    #!/usr/bin/env bash
    REPO_ROOT=$(pwd)

    if [ ! -d "venv" ]; then
        echo "Creating a virtual environment..."
        python3.9 -m venv venv
    fi
    source venv/bin/activate
    pip install -U setuptools

    if [ ! -d "FastChat" ]; then
        git clone --quiet https://github.com/shivchander/FastChat.git
    fi
    cd $REPO_ROOT/FastChat
    if [[ "{{org}}" == "ibm" ]]; then
        git switch kx/openai-api-hack
        git checkout fdc7e4ec9a9ea7a9ccef1056e5b217828c9b401c
    else
        git switch main
    fi
    pip install --quiet --use-pep517 ".[model_worker]"
    # for analysis.py
    pip install wandb matplotlib pandas pygithub
    cd $REPO_ROOT

    screen -dmS controller -- python3 -m fastchat.serve.controller
    sleep 20

    for i in {0..4}
    do
        CUDA_VISIBLE_DEVICES=$i screen -dmS worker-$i -- python3 -m fastchat.serve.model_worker \
            --model-path {{org}}/{{model_name}} \
            --model-name {{model_name}}-$i \
            --port 3100$i \
            --worker http://localhost:3100$i
    done
    sleep 40

    screen -dmS server -- python3 -m fastchat.serve.openai_api_server \
        --host localhost \
        --port 8000

run_bench workspace model bench_name endpoint="http://localhost:8000/v1":
    #!/usr/bin/env bash

    REPO_ROOT=$(pwd)
    WORKSPACE=$(realpath {{workspace}})

    cd $WORKSPACE
    source venv/bin/activate

    cd $WORKSPACE/FastChat/fastchat/llm_judge

    for i in {0..4}
    do
        OPENAI_API_KEY="NO_API_KEY" screen -dmS run-bench-$i -- python gen_api_answer.py \
            --bench-name {{bench_name}} \
            --openai-api-base {{endpoint}} \
            --model "{{model}}-$i" \
            --num-choices 1
    done
    cd $REPO_ROOT

run_judge workspace model bench_name:
    #!/usr/bin/env bash

    REPO_ROOT=$(pwd)
    WORKSPACE=$(realpath {{workspace}})

    cd $WORKSPACE
    source venv/bin/activate

    cd $WORKSPACE/FastChat/fastchat/llm_judge

    OPENAI_API_KEY=${OPENAI_API_KEY} python gen_judgment.py \
        --bench-name {{bench_name}} \
        --model-list "{{model}}-0" "{{model}}-1" "{{model}}-2" "{{model}}-3" "{{model}}-4" \
        --parallel 40 \
        --yes

    python show_result.py --bench-name {{bench_name}}

quick-sync:
    #!/usr/bin/env bash
    git add --update
    git commit -m "quick sync"
    git push

run_eval model:
    echo "Starting server for {{model}}..."
    ./just start_local {{model}}
    echo "...Done starting server!"

    echo "Running MT-Bench (generation)..."
    ./just run_bench ws-mt {{model}} mt_bench
    ./just wait_for_run_bench
    echo "...Done running MT-Bench (generation)!"

    echo "Running MT-Bench (judgement)..."
    ./just run_judge ws-mt {{model}} mt_bench
    echo "...Done running MT-Bench (judgement)!"

    echo "Running PR-Bench (generation)..."
    ./just run_bench ws-pr {{model}} pr_bench
    ./just wait_for_run_bench
    echo "...Done running PR-Bench (generation)!"

    echo "Running PR-Bench (judgement)..."
    ./just run_judge ws-pr {{model}} pr_bench
    echo "...Done running PR-Bench (judgement)!"

run_all rc_branch_name rc_model_path:
    #!/usr/bin/env bash
    echo "Evaluating current model and RC model from {{rc_model_path}}..."

    echo "Preparing workspaces for MT-Bench and PR-Bench..."
    ./just prepare_bench ws-mt
    ./just prepare_bench ws-pr {{rc_branch_name}}
    echo "...Done reparing workspaces!"

    ./just link_rc {{rc_model_path}}

    echo "Evaluating current model..."
    ./just run_eval merlinite-7b
    echo "...Done evaluating current model!"

    echo "Killing current model..."
    pkill screen
    echo "...Done killing current model!"

    echo "Evaluating RC model..."
    ./just run_eval merlinite-7b-rc
    echo "...Done evaluating RC model!"
    
    echo "...Done evaluating current model and RC model!"

wait_for_run_bench:
    #!/usr/bin/env bash
    while [ $(screen -ls | grep run-bench | wc -l) -ne 0 ]
    do
        echo "Still running run_bench.."
        sleep 30
    done
