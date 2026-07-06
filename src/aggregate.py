"""
Stage D — Aggregate per-claim scores into per-example and overall metrics.

Per PROJECT_PLAN.md Section 3.1:
    faithfulness_score = (# claims marked SUPPORTED by both methods) / (total claims)
    agreement_rate = (# claims where NLI verdict == judge verdict) / (total claims)

"supported" from NLI means the verdict field is exactly "supported"
(entailment). "SUPPORTED" from judge means the verdict field is exactly
"supported" (already lowercased in llm_judge.py). Both must match "supported"
for a claim to count toward faithfulness_score numerator.
"""
import json
import os


def aggregate_example(example_id, claims, nli_scores, judge_scores):
    """
    claims: list of claim strings
    nli_scores: list of dicts from nli_scorer.score_claim_nli, same order as claims
    judge_scores: list of dicts from llm_judge.score_claim_judge, same order as claims
    """
    n = len(claims)
    if n == 0:
        return {
            "id": example_id,
            "n_claims": 0,
            "faithfulness_score": None,
            "agreement_rate": None,
            "per_claim": [],
        }

    both_supported = 0
    agree = 0
    per_claim = []

    for claim, nli, judge in zip(claims, nli_scores, judge_scores):
        nli_v = nli["verdict"]
        judge_v = judge["verdict"]
        if nli_v == "supported" and judge_v == "supported":
            both_supported += 1
        if nli_v == judge_v:
            agree += 1
        per_claim.append({
            "claim": claim,
            "nli_verdict": nli_v,
            "nli_confidence": nli["confidence"],
            "judge_verdict": judge_v,
            "judge_reason": judge["reason"],
            "agree": nli_v == judge_v,
        })

    return {
        "id": example_id,
        "n_claims": n,
        "faithfulness_score": both_supported / n,
        "agreement_rate": agree / n,
        "per_claim": per_claim,
    }


def find_disagreements(all_results, max_cases=4):
    """
    Returns the first max_cases disagreement instances found in dataset
    order (not sorted by 'interestingness') per PROJECT_PLAN.md Section 3.2 —
    no cherry-picking.
    """
    cases = []
    for result in all_results:
        for claim_record in result.get("per_claim", []):
            if not claim_record["agree"]:
                cases.append({
                    "example_id": result["id"],
                    **claim_record,
                })
                if len(cases) >= max_cases:
                    return cases
    return cases
