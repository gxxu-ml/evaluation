TOKEN := ""
OPENAI_API_KEY := ""

projdir := justfile_directory()

alias qc := quick-sync

[private]
default:
    just --list

link_rc model_path="/new_data/experiments/ap-m-10-pr0316-v4/sft_model/epoch_4_step_390720":
    #!/usr/bin/env bash
    if [ ! -d {{projdir / "ibm"}} ]; then
        mkdir {{projdir / "ibm"}}
    fi
    ln -s {{model_path}} {{projdir / "ibm" / "merlinite-7b-rc"}}

prepare_bench workspace:
    ./scripts/prepare_fschat_bench.sh {{workspace}}

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
        git clone --quiet https://{{TOKEN}}@github.com/shivchander/FastChat.git
    fi
    cd $REPO_ROOT/FastChat
    if [[ "{{org}}" == "ibm" ]]; then
        git switch kx/openai-api-hack
    else
        git switch main
    fi
    pip install --quiet --use-pep517 ".[model_worker]"
    cd $REPO_ROOT

    screen -dmS controller -- python3 -m fastchat.serve.controller
    sleep 10

    for i in {0..4}
    do
        CUDA_VISIBLE_DEVICES=$i screen -dmS w-$i -- python3 -m fastchat.serve.model_worker \
            --model-path {{org}}/{{model_name}} \
            --model-name {{model_name}}-$i \
            --port 3100$i \
            --worker http://localhost:3100$i
    done
    sleep 20

    screen -dmS server -- python3 -m fastchat.serve.openai_api_server \
        --host localhost \
        --port 8000

run_bench workspace model bench_name endpoint="http://localhost:8000/v1":
    #!/usr/bin/env bash

    REPO_ROOT=$(pwd)
    WORKSPACE=$(realpath {{workspace}})
    NAME="pr_bench"

    cd $WORKSPACE
    source venv/bin/activate

    cd $WORKSPACE/FastChat/fastchat/llm_judge

    for i in {0..4}
    do
        OPENAI_API_KEY="NO_API_KEY" screen -dmS e-$i -- python gen_api_answer.py \
            --bench-name {{bench_name}} \
            --openai-api-base {{endpoint}} \
            --model "{{model}}-$i" \
            --num-choices 1
    done

run_judge workspace model bench_name:
    #!/usr/bin/env bash

    REPO_ROOT=$(pwd)
    WORKSPACE=$(realpath {{workspace}})

    cd $WORKSPACE
    source venv/bin/activate

    cd $WORKSPACE/FastChat/fastchat/llm_judge

    OPENAI_API_KEY={{OPENAI_API_KEY}} python gen_judgment.py \
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

run_all workspace model bench_name endpoint="http://localhost:8000/v1":
    #!/usr/bin/env bash

    ./just start_local {{model}}
    while (screen -r | wc -l) <= 1
    do
        sleep 10
    done
    echo "Done starting up server..." 
    # run_judge 
    # run_judge
    