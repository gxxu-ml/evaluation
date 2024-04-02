import os, yaml, json, click
from datetime import datetime
from tqdm import tqdm


def get_file_paths(directory):
    file_paths = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.split("/")[-1] == "qna.yaml":
                file_paths.append(os.path.join(root, file))
    return file_paths

def load_judge_prompts(prompt_file: str):
    prompts = {}
    with open(prompt_file) as fin:
        for line in fin:
            line = json.loads(line)
            prompts[line["name"]] = line
    return prompts

def read_qna(fn):
    try:
        with open(fn, "r", encoding="utf-8") as file:
            contents = yaml.safe_load(file)
        return contents["seed_examples"]
    except:
        return None

def make_pr_bench(taxonomy_dir, output_dir, keep_all, add_date, changed_qnas_to_pr=None):
    qna_fn_lst = get_file_paths(taxonomy_dir)

    question_lst = []
    idx_q = 0
    for qna_fn in tqdm(qna_fn_lst):
        examples = read_qna(qna_fn)
        qna_fn = qna_fn[len(taxonomy_dir) + 1:]
        if examples is None:
            print(f"failed to load {qna_fn}. skipping...")
            continue
        if not keep_all and len(examples) < 3:
            print(f"{qna_fn} is skipped as it only has {len(examples)}")
            continue
        for ex in examples:
            c = ex["question"] if "context" in ex else None
            q, a = ex["question"], ex["answer"]
            if q is None or a is None: continue
            if c is None:
                t_1 = q
            else:
                t_1 = "Given the context below:\n" + c + "\n" + "Answer the following question: " + q
            question = {
                "qna_fn": qna_fn,
                "question_id": idx_q, 
                "category": "taxonomy", 
                "turns": [t_1], 
                "reference": [a],
            }
            if changed_qnas_to_pr is not None:
                pr_num = changed_qnas_to_pr.get(qna_fn)
                if pr_num is not None:
                    question["pr_num"] = "#" + pr_num
            question_lst.append(question)

            idx_q += 1

    print(f"generated {len(question_lst)} questions")
    pr_bench_dir = os.path.join(output_dir, "pr_bench")
    if add_date:
        pr_bench_dir = pr_bench_dir + "-" + datetime.now().strftime('%Y-%m%d')
    question_fn = "question.jsonl"

    os.makedirs(pr_bench_dir, exist_ok=True)

    with open(
        os.path.join(pr_bench_dir, question_fn), "w", encoding="utf-8"
    ) as outfile:
        for entry in question_lst:
            json.dump(entry, outfile)
            outfile.write("\n")

@click.command()
@click.option('--taxonomy-dir')
@click.option('--output-dir')
@click.option('--keep-all', is_flag=True)
@click.option('--add-date', is_flag=True)
def main(taxonomy_dir, output_dir, keep_all, add_date):
    make_pr_bench(taxonomy_dir, output_dir, keep_all, add_date)


if __name__ == "__main__":
    main()