#!/usr/bin/env bash

OPENAI_API_KEY=""

REPO_ROOT=$(pwd)
WORKSPACE=$(realpath "$1")

cd $WORKSPACE
source venv/bin/activate

cd $WORKSPACE/FastChat/fastchat/llm_judge

OPENAI_API_KEY=$OPENAI_API_KEY python gen_api_answer.py \
    --bench-name pr_bench \
    --model "gpt-3.5-turbo" \
    --parallel 16 \
    --num-choices 1
OPENAI_API_KEY=$OPENAI_API_KEY python gen_judgment.py \
    --bench-name pr_bench \
    --model-list "gpt-3.5-turbo" \
    --parallel 16 \
    --yes

python show_result.py --bench-name pr_bench
