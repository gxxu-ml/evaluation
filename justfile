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

start_local model_name model_path="":
    #!/usr/bin/env bash
    REPO_ROOT=$(pwd)

    if [ "{{model_path}}" = "" ]; then
        model_path="ibm/{{model_name}}"
    else
        model_path={{model_path}}
    fi

    if [ ! -d "venv" ]; then
        echo "Creating a virtual environment..."
        python -m venv venv
    fi
    source venv/bin/activate
    pip install -U setuptools

    if [ ! -d "FastChat" ]; then
        git clone --quiet https://github.com/shivchander/FastChat.git
    fi
    cd $REPO_ROOT/FastChat
    if [[ "$model_path" == ibm/* ]] || [[ "$model_path" =~ (merlinite|granite) ]]; then
        git switch server
        pip install git+https://${GH_IBM_TOKEN}@github.ibm.com/ai-models-architectures/IBM-models.git@0.1.1
    else
        git switch main
    fi
    pip install --quiet -e ".[model_worker]"
    # for analysis.py
    pip install wandb matplotlib pandas pygithub ibmcloudant tenacity
    cd $REPO_ROOT

    screen -dmS controller -- python -m fastchat.serve.controller
    sleep 20

    for i in {0..4}
    do
        CUDA_VISIBLE_DEVICES=$i screen -dmS worker-$i -- python -m fastchat.serve.model_worker \
            --model-path {{model_path}} \
            --model-name {{model_name}}-$i \
            --port 3100$i \
            --worker http://localhost:3100$i
    done
    sleep 40

    screen -dmS server -- python -m fastchat.serve.openai_api_server \
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
        --parallel 10 \
        --yes

    python show_result.py --bench-name {{bench_name}}

run_bench_judge workspace model bench_name:
    echo "Running MT-Bench (generation)..."
    just run_bench {{workspace}} {{model}} {{bench_name}}
    just wait_for_run_bench
    echo "...Done running MT-Bench (generation)!"

    echo "Running MT-Bench (judgement)..."
    just run_judge {{workspace}} {{model}} {{bench_name}}
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

run_mt model_name model_path:
    echo "Preparing workspace for MT-Bench"
    test -d {{projdir}}/ws-mt || just prepare_bench ws-mt
    echo "...Done reparing workspaces!"

    echo "Starting server for {{model_name}} using {{model_path}}..."
    just start_local {{model_name}} {{model_path}}
    echo "...Done starting server!"

    just run_bench_judge ws-mt {{model_name}} mt_bench

    echo "Killing current model..."
    pkill screen
    echo "...Done killing current model!"

    cp -r {{projdir}}/ws-mt/FastChat/fastchat/llm_judge/data/mt_bench {{model_path}}

run_mt_dir model_name model_dir:
    #!/bin/env bash

    fns=(`ls {{model_dir}}`)

    for fn in "${fns[@]}"; do
        just run_mt {{model_name}}-${fn##*_} {{model_dir}}/$fn
    done