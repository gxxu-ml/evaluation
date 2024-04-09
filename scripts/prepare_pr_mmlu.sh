#!/usr/bin/env bash
# Usage: ./scripts/prepare_pr_mmlu.sh /app/test/ws-mmlu-pr /new_data/e2e_apr8/

WORKSPACE="$1"
mkdir -p $WORKSPACE
SDG_BASE_PATH="$2"
cd $WORKSPACE
echo "Making PR-MMLU at $WORKSPACE..."
git clone --quiet https://github.com/EleutherAI/lm-evaluation-harness.git
cd $WORKSPACE/lm-evaluation-harness
echo "Creating a virtual environment..."
python -m venv venv
source venv/bin/activate
pip install -e .
git clone https://$IBM_GH_TOKEN@github.ibm.com/ai-models-architectures/IBM-models.git
cd IBM-models && git checkout 0.0.8 && pip install -e .
cd $WORKSPACE/lm-evaluation-harness
sed -i '1s/^/import ibm_models\n/' lm_eval/__main__.py
mkdir lm_eval/tasks/mmlu_pr
echo -e 'task: mmlu_pr\ndataset_path: json\ndataset_name: null\ntest_split: test\ndoc_to_text: "{{question.strip()}}\\nA. {{choices[0]}}\\nB. {{choices[1]}}\\nC. {{choices[2]}}\\nD. {{choices[3]}}\\nAnswer:"\ndoc_to_choice: ["A", "B", "C", "D"]\ndoc_to_target: answer\noutput_type: multiple_choice\nmetric_list:\n  - metric: acc\n    aggregation: mean\n    higher_is_better: true' > $WORKSPACE/lm-evaluation-harness/lm_eval/tasks/mmlu_pr/_default_mmlu_pr_template_yaml
echo "PR-MMLU completed successfully."
echo "Copying task yamls from $SDG_BASE_PATH"
find $SDG_BASE_PATH -name "*_task.yaml" -exec cp {} lm_eval/tasks/mmlu_pr \;