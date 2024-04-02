#!/usr/bin/env python

import os
os.environ["WANDB_BASE_URL"] = "https://wandb-instance.105mljrhdm0c.us-east.codeengine.appdomain.cloud/"
import re
import git
import click
from matplotlib import pyplot as plt
import pandas as pd
from github import Github
import wandb

from make_pr_bench import make_pr_bench

pd.set_option('display.max_columns', None)
pd.set_option('display.max_rows', None)
pd.set_option('display.expand_frame_repr', False)
pd.set_option('max_colwidth', None)

plt.style.use("bmh")

OWNER = "instruct-lab"
REPO_NAME = "taxonomy"
DEFAULT_BRANCH = "main"


def get_changed_qnas_to_pr(repo: object, stage_branch: str) -> list:
    main_branch = repo.get_branch(DEFAULT_BRANCH)
    stage_commit = repo.get_branch(stage_branch).commit
    main_commit = main_branch.commit

    diff = repo.compare(main_commit.sha, stage_commit.sha)

    changed_files = {}
    for commit in diff.commits:
        commit_obj = repo.get_commit(commit.sha)
        commit_message = commit_obj.commit.message
        pr_numbers = re.findall(r"#(\d+)", commit_message)
        for f in commit_obj.files:
            if f.filename.endswith("qna.yaml"):
                changed_files[f.filename] = pr_numbers[0]

    return changed_files


def save_group_by(df_diff, primary_group_by, name, output_dir):
    df_g = df_diff.groupby([primary_group_by, 'model'])[
        "score"].mean().unstack(fill_value=0)

    df_g.head().to_csv(os.path.join(output_dir, name + ".csv"),
                       sep=',', index=True, encoding='utf-8')

    if df_g.get("merlinite-7b") is not None:
        fig = make_fig(df_g)
        fig.savefig(os.path.join(output_dir, name + ".png"))

        fig = make_fig(df_g, 5.5)
        fig.savefig(os.path.join(output_dir, name + "_5.5.png"))


def gather_pr_bench(workspace_dir, data_dir, output_dir):
    model_dir_pr_bench = os.path.join(data_dir, "pr_bench")

    fn_q = os.path.join(model_dir_pr_bench, "question-eval.jsonl")
    df_q = pd.read_json(fn_q, lines=True)
    print(f"{len(df_q)=}")

    fn_q_old = os.path.join(model_dir_pr_bench, "question-main.jsonl")
    df_q_old = pd.read_json(fn_q_old, lines=True)
    print(f"{len(df_q_old)=}")

    fn_j = os.path.join(model_dir_pr_bench, "model_judgment", "gpt-4_single.jsonl")
    df_j = pd.read_json(fn_j, lines=True)
    print(f"{len(df_j)=}")

    df_q_diff = df_q[~df_q['qna_fn'].isin(df_q_old["qna_fn"].to_list())]

    df_q_diff.head().to_csv(os.path.join(output_dir, "question_diff.csv"),
                            sep=',', index=False, encoding='utf-8')

    print(len(df_q_diff["qna_fn"].unique()), len(df_q_diff["qna_fn"]))

    df_q_diff.groupby("qna_fn").size().value_counts(
    ).reset_index().rename({"index": "#examples"}, axis=1)

    df_j_diff = df_j.merge(df_q_diff, on="question_id", how="inner")
    df_j_diff['model'] = df_j_diff['model'].str.replace(
        '-[0-9]$', '', regex=True)
    df_j_diff['qna_fn'] = df_j_diff['qna_fn'].str.replace(
        workspace_dir + '/taxonomy/', '')
    df_j_diff['qna_fn'] = df_j_diff['qna_fn'].str.replace('/qna.yaml', '')

    df_j_diff.groupby("model")["score"].mean().reset_index().to_csv(os.path.join(
        output_dir, "pr_bench_scores.csv"), sep=',', index=False, encoding='utf-8')

    save_group_by(df_j_diff, "qna_fn", "qna_scores", output_dir)
    save_group_by(df_j_diff, "pr_num", "pr_scores", output_dir)


def gather_mt_bench(data_dir, output_dir):
    model_dir_mt_bench = os.path.join(data_dir, "mt_bench")

    fn_q = os.path.join(model_dir_mt_bench, "question.jsonl")
    df_q = pd.read_json(fn_q, lines=True)
    print(f"{len(df_q)=}")

    fn_j = os.path.join(model_dir_mt_bench, "model_judgment", "gpt-4_single.jsonl")
    df_j = pd.read_json(fn_j, lines=True)
    print(f"{len(df_j)=}")

    df_j['model'] = df_j['model'].str.replace('-[0-9]$', '', regex=True)
    df_j.groupby("model")["score"].mean().to_csv(os.path.join(
        output_dir, "mt_bench_scores.csv"), sep=',', index=True, encoding='utf-8')


def make_fig(df_g, ths=10):
    df_gg = df_g[df_g["merlinite-7b"] < ths]
    n = df_gg.shape[0]

    fig, ax = plt.subplots(figsize=(12, 0.4 * n + 1), tight_layout=True)
    plt.close(fig)

    y = list(range(n))
    y0 = [yi + 0.15 for yi in y]
    y1 = [yi - 0.15 for yi in y]
    ax.vlines(ths, y[0] - 0.5, y[-1] + 0.5, color="gray",
              linestyle="dashed", alpha=0.4)
    for yi, m in zip([y0, y1], ["merlinite-7b", "merlinite-7b-rc"]):
        ax.barh(yi, df_gg[m].to_list(), label=m, height=0.25)
    ax.set_xlim(1, 10)
    ax.set_yticks(y, df_gg.index.to_list())
    ax.legend()

    return fig


@click.command()
@click.option(
    "--project-dir",
    type=click.Path(),
    default="/root/evaluation",
    show_default=True,
    help="The project directory"
)
@click.option(
    "--taxonomy-dir",
    required=True,
    help="The location of the taxonomy repo"
)
@click.option(
    "--eval-branch",
    required=True,
    help="The branch of the taxonomy repo to evaluate"
)
@click.option(
    "--output-dir",
    type=click.Path(),
    required=True,
    help="The output directory"
)
def main(project_dir, taxonomy_dir, eval_branch, output_dir):
    workspace_dir_mt = os.path.join(project_dir, "ws-mt")
    workspace_dir_pr = os.path.join(project_dir, "ws-pr")
    data_dir_pr = os.path.join(workspace_dir_pr, "FastChat/fastchat/llm_judge/data")
    data_dir_mt = os.path.join(workspace_dir_mt, "FastChat/fastchat/llm_judge/data")

    gh_token = os.getenv("GH_TOKEN", None)
    g = Github(gh_token)
    repo = g.get_repo(f"{OWNER}/{REPO_NAME}")
    changed_qnas_to_pr = get_changed_qnas_to_pr(repo, eval_branch)

    taxonomy_repo = git.Repo(taxonomy_dir)
    taxonomy_repo.git.checkout(eval_branch)
    make_pr_bench(taxonomy_dir, data_dir_pr, True, False, changed_qnas_to_pr, suffix="eval")
    taxonomy_repo.git.checkout(DEFAULT_BRANCH)
    make_pr_bench(taxonomy_dir, data_dir_pr, True, False, suffix="main")

    gather_pr_bench(workspace_dir_pr, data_dir_pr, output_dir)
    gather_mt_bench(data_dir_mt, output_dir)

    # log results as W&B artifacts
    # TODO update team name once it's changed
    run = wandb.init(entity="instructlab-backend", project="ilab", job_type="evaluation")

    # TODO implement below when the upstream artifact is ready
    #run.use_artifact("bike-dataset:latest")

    artifact = wandb.Artifact(name="eval-mt_bench", type="dataset")
    artifact.add_dir(local_path=os.path.join(data_dir_mt, "mt_bench"))
    run.log_artifact(artifact)

    artifact = wandb.Artifact(name="eval-pr_bench", type="dataset")
    artifact.add_dir(local_path=os.path.join(data_dir_pr, "pr_bench"))
    run.log_artifact(artifact)

    artifact = wandb.Artifact(name="eval-analysis", type="dataset")
    artifact.add_dir(local_path=output_dir)
    run.log_artifact(artifact)

    run.finish()

if __name__ == "__main__":
    main()
