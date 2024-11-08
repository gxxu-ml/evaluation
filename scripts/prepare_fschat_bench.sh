#!/usr/bin/env bash

# Check if at least one argument is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <workspace_root> [rc_branch_name]"
    echo "  workspace_root: The root directory for the workspace."
    echo "  rc_branch_name: Optional. If set, use this branch for the PR-Bench creation and modification. If not provided, skip PR-Bench creation and modification."
    exit 1
fi

REPO_ROOT=$(pwd)
WORKSPACE=$(realpath "$1")
RC_BRANCH=$2

# Check if the directory exists, if not create it
if [ ! -d "$WORKSPACE" ]; then
    echo "Directory $WORKSPACE does not exist. Creating it..."
    mkdir -p "$WORKSPACE"
else
    echo "Directory $WORKSPACE already exists. Exiting..."
    exit 1
fi

echo "Changing directory to $WORKSPACE..."
cd $WORKSPACE

echo "Creating a virtual environment..."
python -m venv venv
source venv/bin/activate
pip install -U setuptools

if [ -z "$RC_BRANCH" ]; then
    echo "Skipping cloning taxonomy repo..."
else
    echo "Cloning taxonomy repo..."
    git clone --quiet https://${GH_TOKEN}@github.com/instruct-lab/taxonomy.git
    cd $WORKSPACE/taxonomy
    git switch $RC_BRANCH
    cd $WORKSPACE
fi

echo "Cloning FastChat repo..."
git clone --quiet https://github.com/xukai92/FastChat.git 
cd $WORKSPACE/FastChat
git switch ilab # TODO
pip install --quiet -e ".[model_worker,llm_judge]"
pip install --quiet pandas

echo "Injecting codes to FastChat..."
ln -s $REPO_ROOT/scripts/make_pr_bench.py $WORKSPACE/FastChat/fastchat/llm_judge/make_pr_bench.py 
sed -i 's/NEED_REF_CATS = \[/NEED_REF_CATS = \["taxonomy", /g' $WORKSPACE/FastChat/fastchat/llm_judge/common.py

if [ -z "$RC_BRANCH" ]; then
    echo "Skipping PR-Bench prompt modification and data creation..."
else
    echo "Modifying judge prompt for PR-Bench..."

    sed -i "s/You will be given a reference answer and the assistant's answer. Begin your evaluation by comparing the assistant's answer with the reference answer. Identify and correct any mistakes./You will be given a reference answer and the assistant's answer. Begin your evaluation by comparing the assistant's answer with the reference answer. Identify and correct any mistakes. If correct, an assistant's answer that follows a similar style of the reference answer is preferable. Do not bias to any particular style that does not appear in the reference answer./g" $WORKSPACE/FastChat/fastchat/llm_judge/data/judge_prompts.jsonl

    echo "Making PR-Bench data..."
    cd $WORKSPACE/FastChat/fastchat/llm_judge
    python make_pr_bench.py --taxonomy-dir $WORKSPACE/taxonomy --output-dir data
fi

echo "FastChat preparation completed successfully."