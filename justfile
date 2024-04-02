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
        git clone --quiet https://github.com/shivchander/FastChat.git
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
        CUDA_VISIBLE_DEVICES=$i screen -dmS worker-$i -- python3 -m fastchat.serve.model_worker \
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

    OPENAI_API_KEY=${OPEN_API_KEY} python gen_judgment.py \
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

run_all rc_model_path workspace model bench_name:
    #!/usr/bin/env bash
    echo "Running evaluation {{bench_name}} with model {{model}} in workspace {{workspace}}"
    ./just prepare_bench {{workspace}}
    ./just link_rc {{rc_model_path}}
    echo "Done preparing workspace..Starting server..."
    ./just start_local {{model}}
    echo "Done starting up server...Running run_bench..."
    ./just run_bench {{workspace}} {{model}} {{bench_name}}
    ./just wait_for_run_bench
    echo "Done with run_bench...running evaluation..."
    ./just run_judge {{workspace}} {{model}} {{bench_name}}
    echo "Done with evaluation!"

wait_for_run_bench:
    #!/usr/bin/env bash
    while [ $(screen -ls | grep run-bench | wc -l) -ne 0 ]
    do
        echo "Still running run_bench.."
        sleep 30
    done
