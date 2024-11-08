#!/usr/bin/env bash
# Usage: ./scripts/run_pr_mmlu.sh workspace_path output_path model_path 1 2

WORKSPACE="$1"
OUTPUT_FILE="$2"
MODEL_PATH="$3"
cd $WORKSPACE/lm-evaluation-harness
source venv/bin/activate
NUM_FEWSHOTS="$4"
BATCH_SIZE="$5"
lm_eval --model hf --model_args pretrained=$MODEL_PATH,dtype=bfloat16 \
--tasks mmlu_pr \
--num_fewshot $NUM_FEWSHOTS \
--output_path $OUTPUT_FILE \
--batch_size $BATCH_SIZE