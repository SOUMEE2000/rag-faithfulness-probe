"""
Runs Stages A -> E end to end. This is the single entry point:
    python src/pipeline.py

If interrupted, cached files in data/claims/ and data/scores/ mean it will
resume without redoing completed work. Do not delete those directories
mid-run.
"""
import json
import os
from tqdm import tqdm

from data_loader import load_examples
from claim_decompose import decompose_claims
from nli_scorer import score_claim_nli
from llm_judge import score_claim_judge
from aggregate import aggregate_example, find_disagreements
from report_generator import write_reports

SCORES_CACHE_DIR = "data/scores"


def run_example(example):
    example_id = example["id"]
    cache_path = os.path.join(SCORES_CACHE_DIR, f"{example_id}.json")

    if os.path.exists(cache_path):
        with open(cache_path) as f:
            return json.load(f)

    decomp = decompose_claims(example_id, example["question"], example["generated_answer"])
    claims = decomp["claims"]

    if decomp["decomposition_failed"] or not claims:
        result = {"id": example_id, "n_claims": 0, "faithfulness_score": None,
                  "agreement_rate": None, "per_claim": [], "decomposition_failed": True}
    else:
        nli_scores = [score_claim_nli(example["source_context"], c) for c in claims]
        judge_scores = [score_claim_judge(example["source_context"], c) for c in claims]
        result = aggregate_example(example_id, claims, nli_scores, judge_scores)
        result["decomposition_failed"] = False

    os.makedirs(SCORES_CACHE_DIR, exist_ok=True)
    with open(cache_path, "w") as f:
        json.dump(result, f, indent=2)

    return result


def main():
    examples = load_examples()
    print(f"Loaded {len(examples)} examples (source: {examples[0]['source_dataset']})")

    all_results = []
    for ex in tqdm(examples, desc="Scoring examples"):
        all_results.append(run_example(ex))

    write_reports(all_results)

    disagreements = find_disagreements(all_results, max_cases=4)
    print(f"\nFound {len(disagreements)} disagreement cases for write-up.")
    with open("results/disagreement_cases_raw.json", "w") as f:
        json.dump(disagreements, f, indent=2)
    print("Raw disagreement data written to results/disagreement_cases_raw.json")
    print("Now write these up by hand in notes/disagreement_cases.md per the README template.")


if __name__ == "__main__":
    main()
