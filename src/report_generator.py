"""
Stage E — Write final report files.
Outputs, per PROJECT_PLAN.md Section 3.1 / 5:
    results/faithfulness_report.json   (full per-claim detail, all examples)
    results/aggregate_scores.csv       (id, n_claims, faithfulness_score, agreement_rate)
"""
import json
import csv
import os


def write_reports(all_results, output_dir="results"):
    os.makedirs(output_dir, exist_ok=True)

    with open(os.path.join(output_dir, "faithfulness_report.json"), "w") as f:
        json.dump(all_results, f, indent=2)

    csv_path = os.path.join(output_dir, "aggregate_scores.csv")
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "n_claims", "faithfulness_score", "agreement_rate"])
        for r in all_results:
            writer.writerow([r["id"], r["n_claims"], r["faithfulness_score"], r["agreement_rate"]])

    # summary stats printed to console — paste these into README "Preliminary Results"
    valid = [r for r in all_results if r["n_claims"] > 0]
    n_failed = len(all_results) - len(valid)
    if valid:
        mean_faith = sum(r["faithfulness_score"] for r in valid) / len(valid)
        mean_agree = sum(r["agreement_rate"] for r in valid) / len(valid)
        print(f"n examples: {len(all_results)} | decomposition failures: {n_failed}")
        print(f"mean faithfulness_score: {mean_faith:.3f}")
        print(f"mean agreement_rate: {mean_agree:.3f}")
    else:
        print("No valid examples to summarize.")
