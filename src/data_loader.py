"""
Stage A — Load data.
Decision (per PROJECT_PLAN.md Section 1): try RAGTruth QA subset first,
timeboxed to 30 minutes of debugging. Fall back to HotpotQA + self-generated
answers if RAGTruth is inaccessible. Whichever path is used, the caller MUST
record which one in data/examples.jsonl's metadata so the README doesn't
have to guess later.

Output contract: a list of dicts, each:
    {
        "id": str,
        "question": str,
        "source_context": str,
        "generated_answer": str,
        "source_dataset": "ragtruth" | "hotpotqa_selfgen"
    }
Cached to data/examples.jsonl (one JSON object per line).
"""
import json
import os

N_EXAMPLES = 200
CACHE_PATH = "data/examples.jsonl"


def load_ragtruth(n=N_EXAMPLES):
    """
    Primary path. Try HuggingFace first, then raw GitHub JSON as a secondary
    attempt within the SAME 30-minute timebox (this is not a separate fallback
    tier — if both fail, move to load_hotpotqa_fallback()).
    """
    from datasets import load_dataset

    # NOTE: confirm this HF path when you have network access — RAGTruth's
    # exact HF dataset id may differ. If load_dataset raises, git clone
    # https://github.com/ParticleMedia/RAGTruth and parse the JSON directly
    # instead of debugging the HF path further.
    ds = load_dataset("wandb/RAGTruth", split="test")

    examples = []
    count = 0
    for row in ds:
        if row.get("task_type") != "QA":  # keep to QA subset only, per plan
            continue
        examples.append({
            "id": f"ragtruth_{row.get('id', count)}",
            "question": row["prompt"] if "prompt" in row else row.get("question", ""),
            "source_context": row["reference"] if "reference" in row else row.get("source_context", ""),
            "generated_answer": row["response"] if "response" in row else row.get("generated_answer", ""),
            "source_dataset": "ragtruth",
        })
        count += 1
        if count >= n:
            break
    return examples


def load_hotpotqa_fallback(n=N_EXAMPLES):
    """
    Fallback path (Section 1). Loads HotpotQA distractor validation split,
    then generates an answer for each (question, context) pair using
    LLaMA-3.1 via Ollama at temperature 0.7 with a plain RAG prompt
    (no faithfulness instruction — we want natural hallucination behavior).
    """
    from datasets import load_dataset
    import ollama

    ds = load_dataset("hotpot_qa", "distractor", split="validation")

    examples = []
    for i, row in enumerate(ds):
        if i >= n:
            break
        context_text = " ".join(
            " ".join(sentences) for sentences in row["context"]["sentences"]
        )
        prompt = (
            f"Answer the question using only the context below.\n\n"
            f"Context: {context_text}\n\nQuestion: {row['question']}\n\nAnswer:"
        )
        response = ollama.chat(
            model="llama3.1",
            messages=[{"role": "user", "content": prompt}],
            options={"temperature": 0.7},
        )
        examples.append({
            "id": f"hotpotqa_{row['id']}",
            "question": row["question"],
            "source_context": context_text,
            "generated_answer": response["message"]["content"],
            "source_dataset": "hotpotqa_selfgen",
        })
    return examples


def load_examples(force_reload=False):
    if os.path.exists(CACHE_PATH) and not force_reload:
        with open(CACHE_PATH) as f:
            return [json.loads(line) for line in f]

    try:
        examples = load_ragtruth()
        if not examples:
            raise ValueError("RAGTruth returned zero QA examples")
    except Exception as e:
        print(f"[data_loader] RAGTruth path failed ({e}); using HotpotQA fallback.")
        examples = load_hotpotqa_fallback()

    os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
    with open(CACHE_PATH, "w") as f:
        for ex in examples:
            f.write(json.dumps(ex) + "\n")

    return examples


if __name__ == "__main__":
    exs = load_examples()
    print(f"Loaded {len(exs)} examples. Source: {exs[0]['source_dataset'] if exs else 'none'}")
