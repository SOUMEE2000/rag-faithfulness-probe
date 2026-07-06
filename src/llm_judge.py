"""
Stage C (method 2 of 2) — LLM-judge scoring.
Prompt fixed per PROJECT_PLAN.md Section 4.2. Do not edit inline;
log any change with a timestamp in notes/prompt_changes.md.
Model: llama3.1 via Ollama (same model as decomposition, different prompt —
this is intentional per plan, not an oversight).
"""
import re
import ollama

JUDGE_PROMPT = """You are verifying whether a factual claim is supported by a source document. Read the source and the claim. Respond with exactly one word on the first line — SUPPORTED, UNSUPPORTED, or CONTRADICTED — followed by a one-sentence reason on the second line.

SUPPORTED = the source directly states or clearly implies this claim.
UNSUPPORTED = the source does not contain enough information to confirm this claim (it may be true, but it isn't grounded in this source).
CONTRADICTED = the source states something that conflicts with this claim.

Source: {source_context}
Claim: {claim}

Verdict:"""

VALID_VERDICTS = {"SUPPORTED", "UNSUPPORTED", "CONTRADICTED"}


def score_claim_judge(source_context, claim, model="llama3.1"):
    prompt = JUDGE_PROMPT.format(source_context=source_context, claim=claim)
    response = ollama.chat(model=model, messages=[{"role": "user", "content": prompt}])
    text = response["message"]["content"].strip()

    lines = text.split("\n", 1)
    first_line = lines[0].strip().upper()
    reason = lines[1].strip() if len(lines) > 1 else ""

    verdict = None
    for v in VALID_VERDICTS:
        if v in first_line:
            verdict = v.lower()
            break

    if verdict is None:
        # retry once at temperature 0 if unparseable
        response = ollama.chat(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            options={"temperature": 0},
        )
        text = response["message"]["content"].strip()
        lines = text.split("\n", 1)
        first_line = lines[0].strip().upper()
        reason = lines[1].strip() if len(lines) > 1 else ""
        for v in VALID_VERDICTS:
            if v in first_line:
                verdict = v.lower()
                break

    return {
        "verdict": verdict if verdict else "unparseable",
        "reason": reason,
        "raw_response": text,
    }


if __name__ == "__main__":
    result = score_claim_judge(
        source_context="The Eiffel Tower was completed in 1889 in Paris, France.",
        claim="The Eiffel Tower is located in Paris.",
    )
    print(result)
