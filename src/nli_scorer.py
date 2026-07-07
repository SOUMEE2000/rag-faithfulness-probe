"""
Stage C (method 1 of 2) — NLI-based entailment scoring.
Model fixed per PROJECT_PLAN.md Section 2:
    MoritzLaurer/DeBERTa-v3-large-mnli-fever-anli-ling-wanli
(preferred — tuned for fact-verification-style entailment).
Fallback model if the above fails to load: microsoft/deberta-v2-xlarge-mnli.
Premise = source_context. Hypothesis = claim.
Label mapping: entailment -> supported, neutral -> unsupported,
contradiction -> contradicted.

NOTE: Forced to CPU (DEVICE = "cpu") so DeBERTa never competes with
Ollama/LLaMA for GPU VRAM. On a 6 GB GPU, both cannot coexist in VRAM.
CPU inference is ~1-3 sec/claim — acceptable for 200 examples.
"""
import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification

DEVICE = "cpu"  # Kept on CPU intentionally — see module docstring above

MODEL_NAME_PRIMARY = "MoritzLaurer/DeBERTa-v3-large-mnli-fever-anli-ling-wanli"
MODEL_NAME_FALLBACK = "microsoft/deberta-v2-xlarge-mnli"

_tokenizer = None
_model = None
_label_map = None


def _load_model():
    global _tokenizer, _model, _label_map
    if _model is not None:
        return
    try:
        _tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME_PRIMARY)
        _model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME_PRIMARY)
        model_name_used = MODEL_NAME_PRIMARY
    except Exception as e:
        print(f"[nli_scorer] Primary model failed ({e}), using fallback.")
        _tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME_FALLBACK)
        _model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME_FALLBACK)
        model_name_used = MODEL_NAME_FALLBACK

    _model = _model.to(DEVICE)  # explicitly pin to CPU
    _model.eval()
    # id2label varies by checkpoint; normalize to our three buckets by
    # inspecting the label strings rather than assuming index order.
    raw_labels = _model.config.id2label
    _label_map = {}
    for idx, label in raw_labels.items():
        label_lower = label.lower()
        if "entail" in label_lower:
            _label_map[idx] = "supported"
        elif "contra" in label_lower:
            _label_map[idx] = "contradicted"
        else:
            _label_map[idx] = "unsupported"  # neutral -> unsupported
    print(f"[nli_scorer] Loaded {model_name_used}. Label map: {_label_map}")


def score_claim_nli(source_context, claim):
    _load_model()
    inputs = _tokenizer(
        source_context, claim, return_tensors="pt", truncation=True, max_length=512
    )
    # Move inputs to the same device as the model (CPU)
    inputs = {k: v.to(DEVICE) for k, v in inputs.items()}
    with torch.no_grad():
        logits = _model(**inputs).logits
    probs = torch.softmax(logits, dim=-1)[0]
    pred_idx = int(torch.argmax(probs))
    return {
        "verdict": _label_map[pred_idx],
        "confidence": float(probs[pred_idx]),
        "all_probs": {_label_map[i]: float(probs[i]) for i in range(len(probs))},
    }


if __name__ == "__main__":
    # smoke test
    result = score_claim_nli(
        source_context="The Eiffel Tower was completed in 1889 in Paris, France.",
        claim="The Eiffel Tower is located in Paris.",
    )
    print(result)
