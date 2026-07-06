# rag-faithfulness-probe

An open evaluation harness that decomposes a RAG system's answer into atomic
claims and checks each claim's entailment against the specific source it
cites — surfacing confident, well-formatted, unsupported generations that
whole-answer metrics miss.

## Abstract

Retrieval-augmented generation is often treated as a reliability fix for
language models, but a RAG answer can be fluent, well-cited, and still make
claims its own sources do not support — a failure that is hard for a reader
to detect precisely because the output looks grounded. This project treats
faithfulness as a verification problem: it decomposes a generated answer
into atomic claims and independently scores each claim's entailment against
the source it cites, using both a natural-language-inference model and an
LLM-judge, then reports where the two disagree. The aim is a small,
reproducible tool for measuring claim-level groundedness in deployed
retrieval systems, and an empirical look at how far answer-level
faithfulness scores hide claim-level failures. It grew out of two years
building and hardening a production RAG system where unfaithful generation
was not a UX defect but a safety-relevant one.

## Research Questions

1. What fraction of claims in a fluent, well-cited RAG answer are actually
   entailed by the cited source, versus merely plausible-sounding?
2. Where do an NLI model and an LLM-judge disagree about groundedness, and
   what does that disagreement reveal about the difficulty of automated
   faithfulness verification?

## Method

The pipeline runs in five stages. First, a set of `(question, source
context, generated answer)` triples is loaded from a benchmark dataset.
Second, each generated answer is decomposed by an LLM into a list of atomic,
independently checkable factual claims — this step matters because
whole-answer faithfulness scores can hide the fact that one unsupported
clause is buried inside an otherwise well-grounded paragraph.

Third, every claim is scored two independent ways: a natural-language-
inference model treats the source context as the premise and the claim as
the hypothesis, and separately, an LLM-judge is prompted to classify the
same claim as supported, unsupported, or contradicted with a one-sentence
justification. These two methods are deliberately kept independent — the
NLI model is a small, purpose-built classifier, while the LLM-judge is a
general-purpose model reasoning in natural language. Where they agree, that
is reasonably strong evidence either way. Where they disagree, that
disagreement is itself the interesting signal, because it marks claims
where the correct verdict is genuinely ambiguous or where one method's
failure mode is visible.

Fourth, per-example and aggregate scores are computed: a faithfulness score
(fraction of claims both methods mark supported) and an agreement rate
(fraction of claims where the two methods concur). Fifth, results are
written out as structured JSON and CSV reports, and the clearest
disagreement cases are pulled out for qualitative write-up.

## Preliminary Results

*[Fill in after running `python src/pipeline.py` on the full example set —
paste the console summary here: n examples, decomposition failures, mean
faithfulness_score, mean agreement_rate. See `results/aggregate_scores.csv`
for the full per-example table.]*

### Disagreement cases

*[Paste the 3–4 write-ups from `notes/disagreement_cases.md` here once
`results/disagreement_cases_raw.json` has been reviewed and annotated.]*

## Limitations

- Dataset used: *[state explicitly — RAGTruth QA subset, or the HotpotQA +
  self-generated fallback, and if the fallback was used, note that the same
  model both generated and was evaluated, which is not an independent
  benchmark]*
- Small sample (n≈200), single domain, English-only
- The NLI model and the LLM-judge are not independently verified against
  human ground truth in this iteration — both are pattern-matchers, and
  agreement between them is evidence of consistency, not proof of
  correctness
- Claim decomposition is itself an LLM call and can introduce its own
  errors (over-splitting, under-splitting, or dropping claims)

## Roadmap

- Calibration against a human-labelled subset
- Adversarial context construction (deliberately misleading or
  contradictory sources)
- Multilingual extension — testing whether faithfulness and hallucination
  rates hold steady across Bengali and Hindi source documents, not just
  English

## Why this matters for AI safety

Faithfulness failures in retrieval-augmented systems are a small, measurable
instance of a much larger problem in AI safety: verifying that a system's
outputs are actually grounded in what it was given, rather than in what is
merely plausible. As RAG systems are deployed in higher-stakes decision
contexts, the gap between fluent and faithful becomes a safety property, not
a quality-of-life one. This project grew directly out of building and
hardening a production RAG system where that gap had operational
consequences, not just cosmetic ones.

## Reproduce

```bash
pip install -r requirements.txt
ollama pull llama3.1
python src/pipeline.py
```

Cached intermediate results (claim decompositions, per-claim scores) are
stored under `data/` so an interrupted run can resume without redoing
completed work.

## Repo structure

```
rag-faithfulness-probe/
├── README.md
├── requirements.txt
├── src/
│   ├── data_loader.py       # Stage A — load + cache benchmark examples
│   ├── claim_decompose.py   # Stage B — LLM-based atomic claim extraction
│   ├── nli_scorer.py        # Stage C(1) — NLI entailment scoring
│   ├── llm_judge.py         # Stage C(2) — LLM-judge scoring
│   ├── aggregate.py         # Stage D — per-example + overall metrics
│   ├── report_generator.py  # Stage E — write JSON/CSV reports
│   └── pipeline.py          # orchestrates A → E end to end
├── results/
│   ├── faithfulness_report.json
│   └── aggregate_scores.csv
└── notes/
    └── disagreement_cases.md
```
