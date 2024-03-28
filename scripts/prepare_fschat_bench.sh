#!/usr/bin/env bash

# Check if at least one argument is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <workspace_root> [--force]"
    echo "  workspace_root: The root directory for the workspace."
    echo "  --force: Optional. If set, deletes and recreates the workspace if it already exists."
    exit 1
fi

REPO_ROOT=$(pwd)
WORKSPACE=$(realpath "$1")
FORCE=$2

# Check if the directory exists, if not create it
if [ ! -d "$WORKSPACE" ]; then
    echo "Directory $WORKSPACE does not exist. Creating it..."
    mkdir -p "$WORKSPACE"
else
    if [ "$FORCE" == "--force" ]; then
        echo "Force flag detected. Deleting and recreating $WORKSPACE..."
        rm -rf "$WORKSPACE"
        mkdir -p "$WORKSPACE"
    else
        echo "Directory $WORKSPACE already exists. Exiting..."
        exit 1
    fi
fi

echo "Changing directory to $WORKSPACE..."
cd $WORKSPACE

echo "Creating a virtual environment..."
python3.9 -m venv venv
source venv/bin/activate
pip install -U setuptools

echo "Cloning taxonomy repo..."
# git clone --quiet https://llm-alignment/labrador-datagen.git
# cd $WORKSPACE/labrador-datagen
# git switch --detach a8dd8c952c17f449303638b83bee2c31c98c50fc
git clone --quiet https://${GH_TOKEN}@github.com/instruct-lab/taxonomy.git
cd $WORKSPACE/taxonomy
git switch test-release-031624
cd $WORKSPACE

echo "Cloning FastChat repo..."
# git clone --quiet https://{}github.com/lm-sys/FastChat.git
git clone --quiet https://github.com/shivchander/FastChat.git 
cd $WORKSPACE/FastChat
# git switch --detach d04ce6453ae016d9e03626b679c07aa1388dcbee # should be updated as we go
git switch ibm-pr # TODO
pip install --quiet --use-pep517 .
pip install --quiet pandas torch transformers accelerate openai==0.28.0 anthropic

echo "Injecting codes to FastChat..."
ln -s $REPO_ROOT/scripts/make_pr_bench.py $WORKSPACE/FastChat/fastchat/llm_judge/make_pr_bench.py 
sed -i 's/NEED_REF_CATS = \[/NEED_REF_CATS = \["taxonomy", /g' $WORKSPACE/FastChat/fastchat/llm_judge/common.py
sed -i 's/args = parser.parse_args()/parser.add_argument("--yes", action="store_true")\n    args = parser.parse_args()/g' $WORKSPACE/FastChat/fastchat/llm_judge/gen_judgment.py
sed -i 's/input("Press Enter to confirm...")/if not args.yes:\n        input("Press Enter to confirm...")/g' $WORKSPACE/FastChat/fastchat/llm_judge/gen_judgment.py
sed -i "s/You will be given a reference answer and the assistant's answer. Begin your evaluation by comparing the assistant's answer with the reference answer. Identify and correct any mistakes./You will be given a reference answer and the assistant's answer. Begin your evaluation by comparing the assistant's answer with the reference answer. Identify and correct any mistakes. If correct, an assistant's answer that follows a similar style of the reference answer is preferable. Do not bias to any particular style that does not appear in the reference answer./g" $WORKSPACE/FastChat/fastchat/llm_judge/data/judge_prompts.jsonl

echo "Making data..."
cd $WORKSPACE/FastChat/fastchat/llm_judge
# python make_pr_bench.py --taxonomy-dir $WORKSPACE/labrador-datagen/taxonomies --output-dir data
python make_pr_bench.py --taxonomy-dir $WORKSPACE/taxonomy --output-dir data

echo "FastChat preparation completed successfully."