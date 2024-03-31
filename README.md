# Run mt-bench/pr-bench evaluation

Running the evalution: 

Once you've logged into the cluster, run the following command using the manifest `manifests/evaluation.yaml`:

```bash
sed -e 's|job-name|<evaluation-job-name>|g' \                
-e 's|gh-token|<GH-TOKEN>|g' \
-e 's|open-api-key|<OPEN-API-KEY>|g' \
-e 's|workspace|<WORKSPACE-NAME>|g' \
-e 's|model-name|<MODEL-NAME>|g' \
-e 's|eval-name|<one of pr_bench/mt_bench>|g' \
manifests/evaluation.yaml \
| oc apply -f -
```

## Example run: 

```bash
$ git clone https://<token>@github.com/instruct-lab/evalution.git

$ cd evaluation

$ sed -e 's|job-name|test-evaluation|g' \                
-e 's|gh-token|REDACTED|g' \
-e 's|open-api-key|REDACTRED|g' \
-e 's|workspace|ws-test|g' \
-e 's|model-name|merlinite-7b-rc|g' \
-e 's|eval-name|pr_bench|g' \
manifests/evaluation.yaml \
| oc apply -f -

$  oc get pods -w | grep test-evaluation
test-evaluation-master-0        0/1     Pending             0          10s
test-evaluation-master-0        0/1     ContainerCreating   0          85s
test-evaluation-master-0        0/1     Running             0          1m53s

$ oc logs test-evalution-master-0 -f 
Cloning into 'evaluation'...
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100 2176k  100 2176k    0     0  20.4M      0 --:--:-- --:--:-- --:--:-- 20.4M
Running evaluation pr_bench with model merlinite-7b-rc in workspace ws-test
./scripts/prepare_fschat_bench.sh ws-test
Directory /root/evaluation/ws-test does not exist. Creating it...
Changing directory to /root/evaluation/ws-test...
Creating a virtual environment...
Collecting setuptools
  Using cached setuptools-69.2.0-py3-none-any.whl (821 kB)
Installing collected packages: setuptools
  Attempting uninstall: setuptools
    Found existing installation: setuptools 44.0.0
    Uninstalling setuptools-44.0.0:
      Successfully uninstalled setuptools-44.0.0
Successfully installed setuptools-69.2.0
Cloning taxonomy repo...
Switched to a new branch 'test-release-031624'
branch 'test-release-031624' set up to track 'origin/test-release-031624'.
Cloning FastChat repo...
branch 'ibm-pr' set up to track 'origin/ibm-pr'.
Switched to a new branch 'ibm-pr'
Injecting codes to FastChat...
Making data...
 50%|█████     | 45/90 [00:00<00:00, 442.64it/s]/root/evaluation/ws-test/taxonomy/compositional_skills/extraction/abstractive/abstract/qna.yaml is skipped as it only has 1
/root/evaluation/ws-test/taxonomy/compositional_skills/extraction/abstractive/key_points/qna.yaml is skipped as it only has 1
/root/evaluation/ws-test/taxonomy/compositional_skills/extraction/abstractive/main_takeaway/qna.yaml is skipped as it only has 1
.
.
.
generated 138 questions
FastChat preparation completed successfully.
Done preparing workspace..Starting server...
Creating a virtual environment...
Collecting setuptools
  Using cached setuptools-69.2.0-py3-none-any.whl (821 kB)
Installing collected packages: setuptools
  Attempting uninstall: setuptools
    Found existing installation: setuptools 44.0.0
    Uninstalling setuptools-44.0.0:
      Successfully uninstalled setuptools-44.0.0
Successfully installed setuptools-69.2.0
Switched to a new branch 'kx/openai-api-hack'
branch 'kx/openai-api-hack' set up to track 'origin/kx/openai-api-hack'.
Done starting up server...Running run_bench...
Still running run_bench..
Still running run_bench..
Still running run_bench..
Still running run_bench..
Still running run_bench..
.
.
.
Done with run_bench...running evaluation...
Stats:
{
    "bench_name": "pr_bench",
    "mode": "single",
    "judge": "gpt-4",
    "baseline": null,
    "model_list": [
        "merlinite-7b-rc-0",
        "merlinite-7b-rc-1",
        "merlinite-7b-rc-2",
        "merlinite-7b-rc-3",
        "merlinite-7b-rc-4"
    ],
    "total_num_questions": 138,
    "total_num_matches": 690,
    "output_path": "data/pr_bench/model_judgment/gpt-4_single.jsonl"
}
 12%|█▏        | 82/690 [00:10<00:44, 13.77it/s]question: 51, turn: 1, model: merlinite-7b-rc-3, score: 2, judge: ('gpt-4', 'single-v1')
question: 45, turn: 1, model: merlinite-7b-rc-4, score: 8, judge: ('gpt-4', 'single-v1')
question: 82, turn: 1, model: merlinite-7b-rc-2, score: 8, judge: ('gpt-4', 'single-v1')
question: 70, turn: 1, model: merlinite-7b-rc-0, score: 6, judge: ('gpt-4', 'single-v1')
question: 59, turn: 1, model: merlinite-7b-rc-4, score: 1, judge: ('gpt-4', 'single-v1')
.
.
.
question: 111, turn: 1, model: merlinite-7b-rc-4, score: 10, judge: ('gpt-4', 'single-v1')
question: 136, turn: 1, model: merlinite-7b-rc-4, score: 1, judge: ('gpt-4', 'single-v1')
question: 125, turn: 1, model: merlinite-7b-rc-4, score: 3, judge: ('gpt-4', 'single-v1')
question: 97, turn: 1, model: merlinite-7b-rc-1, score: 2, judge: ('gpt-4', 'single-v1')
Mode: single
Input file: data/pr_bench/model_judgment/gpt-4_single.jsonl

########## First turn ##########
                           score
model             turn          
merlinite-7b-rc-3 1     6.362319
merlinite-7b-rc-2 1     6.228261
merlinite-7b-rc-1 1     6.028986
merlinite-7b-rc-4 1     6.007246
merlinite-7b-rc-0 1     5.949275
Done with evaluation!

```