# Run mt-bench/pr-bench evaluation

Running the evaluation: 

Once you've logged into the cluster, run the following command using the manifest `manifests/evaluation.yaml`:

```bash
sed -e 's|job-name|<evaluation-job-name>|g' \                
-e 's|gh-token|<GH_TOKEN>|g' \
-e 's|openai-api-key|<OPENAI_API_KEY>|g' \
-e 's|wandb-api-key|<WANDB_API_KEY>|g' \
-e 's|cloudant-url|<CLOUDANT_URL>|g' \
-e 's|cloudant-apikey|<CLOUDANT_APIKEY>|g' \
-e 's|rc-branch-name|<release-candidate-branch-of-the-taxonomy-repo>|g' \
-e 's|rc-model-path|<path-in-volume-mount-where-rc-model-is-mounted>|g' \
manifests/evaluation.yaml \
| oc apply -f -
```

## Example run: 

```bash
$ git clone https://<token>@github.com/instruct-lab/evalution.git

$ cd evaluation

$ sed -e 's|job-name|test-evaluation|g' \                
-e 's|gh-token|$GH_TOKEN|g' \
-e 's|openai-api-key|$OAI_KEY|g' \
-e 's|wandb-api-key|$WANDB_KEY|g' \
-e 's|cloudant-url|$CLOUDANT_URL|g' \
-e 's|cloudant-apikey|$CLOUDANT_APIKEY|g' \
-e 's|rc-branch-name|test-release-031624|g' \
-e 's|rc-model-path|"/new_data/experiments/ap-m-10-pr0316-v4/sft_model/epoch_4_step_390720"|g' \
manifests/evaluation.yaml \
| oc apply -f -

$  oc get pods -w | grep test-evaluation
test-evaluation-master-0        0/1     Pending             0          10s
test-evaluation-master-0        0/1     ContainerCreating   0          85s
test-evaluation-master-0        0/1     Running             0          1m53s

$  oc logs -f test-evaluation-master-0
Cloning into 'evaluation'...
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100 2176k  100 2176k    0     0  40.8M      0 --:--:-- --:--:-- --:--:--  274M
Evaluating current model and RC model from /new_data/experiments/ap-m-10-pr0316-v4/sft_model/epoch_4_step_390720...
Preparing workspaces for MT-Bench and PR-Bench...
./scripts/prepare_fschat_bench.sh ws-mt
Directory /root/evaluation/ws-mt does not exist. Creating it...
Changing directory to /root/evaluation/ws-mt...
...
```

The evaluation & analysis results will be pushed to W&B