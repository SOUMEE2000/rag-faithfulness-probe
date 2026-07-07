# rag-faithfulness-probe

> Claim-level faithfulness evaluation for RAG systems — fully local, no API keys, reproducible.

An open evaluation harness that decomposes a RAG system's generated answer into
atomic claims and independently checks each claim's entailment against the
retrieved source — surfacing confident, well-formatted, unsupported generations
that whole-answer metrics miss.

---

## Abstract

Retrieval-augmented generation is often treated as a reliability fix for language
models, but a RAG answer can be fluent, well-cited, and still make claims its own
sources do not support. This project treats faithfulness as a verification problem:
it decomposes each generated answer into atomic claims and scores every claim two
independent ways — a natural-language-inference model and an LLM judge — then
reports where the two disagree. The result is a small, fully local, reproducible
tool for measuring claim-level groundedness, and an empirical look at how much
answer-level faithfulness scores hide claim-level failures. It grew out of two
years building and hardening a production RAG system where unfaithful generation
was not a UX defect but a safety-relevant one.

---

## Research Questions

1. What fraction of claims in a fluent, well-cited RAG answer are actually entailed
   by the cited source, versus merely plausible-sounding?
2. Where do an NLI model and an LLM judge disagree about groundedness, and what
   does that disagreement reveal about the difficulty of automated faithfulness
   verification?

---

## Method

The pipeline runs in five stages:

| Stage | Module | Description |
|-------|--------|-------------|
| A | `data_loader.py` | Load `(question, source context, generated answer)` triples from RAGTruth QA subset; cache to `data/examples.jsonl` |
| B | `claim_decompose.py` | Decompose each answer into atomic, independently checkable claims via LLaMA-3.1 |
| C | `nli_scorer.py` + `llm_judge.py` | Score each claim two ways: DeBERTa-v3-large NLI model + LLaMA-3.1 judge |
| D | `aggregate.py` | Compute per-example `faithfulness_score` and `agreement_rate` |
| E | `report_generator.py` | Write `results/faithfulness_report.json` and `results/aggregate_scores.csv` |

Decomposition and judging are kept in separate prompt contexts so the two scoring
methods remain as independent as the single-model constraint allows. Where they
agree, that is reasonably strong evidence. Where they disagree, that disagreement
is itself the signal — marking claims where automated faithfulness verification is
genuinely difficult.

---

## Preliminary Results

*Fill in after running the pipeline. Paste console output here:*

```
n examples:               [fill]
decomposition failures:   [fill]
mean faithfulness_score:  [fill]
mean agreement_rate:      [fill]
```

*Full per-example table: [`results/aggregate_scores.csv`](results/aggregate_scores.csv)*

### Disagreement Cases

*Paste the 3–4 annotated cases from [`notes/disagreement_cases.md`](notes/disagreement_cases.md)
after reviewing [`results/disagreement_cases_raw.json`](results/disagreement_cases_raw.json).*

---

## How To Run

### Option 1 — Local (Python + Ollama)

**Requirements:** Python 3.10+, [Ollama](https://ollama.com/download) installed and running.

```bash
pip install -r requirements.txt
ollama pull llama3.1          # ~4.7 GB, one-time download
cd src
python pipeline.py
```

### Option 2 — Docker (No Local Python Required)

**Requirements:** [Docker Desktop](https://www.docker.com/products/docker-desktop) 4.x+.

```bash
docker compose up
```

> **Note on torch in Docker:** The Docker image uses the **CPU-only** PyTorch wheel
> (`torch==2.2.0+cpu`, ~230 MB) instead of the default CUDA build (~2.3 GB). This
> keeps the image lean and avoids GPU driver compatibility issues inside containers.
> DeBERTa inference is pinned to CPU regardless of host hardware.
> LLaMA runs through Ollama in a separate container which **does** use GPU if
> available on the host — see [GPU acceleration](#gpu-acceleration) below.

#### GPU Acceleration

**For LLaMA (via Ollama) — GPU is automatic** if the host has a compatible NVIDIA
GPU and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) is installed.
No changes to the Compose file are needed; Ollama detects and uses the GPU on startup.

**To also run DeBERTa on GPU** (speeds up NLI scoring from ~2 s/claim to ~0.1 s/claim),
make two changes:

1. Switch `requirements-docker.txt` to the CUDA wheel:

```diff
-  --extra-index-url https://download.pytorch.org/whl/cpu
-  torch==2.2.0+cpu
+  torch==2.2.0+cu121
```

2. Change `DEVICE` in `src/nli_scorer.py`:

```diff
-  DEVICE = "cpu"
+  DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
```

Then rebuild: `docker compose build pipeline`.

> ⚠️ Running both LLaMA (Ollama) **and** DeBERTa on GPU simultaneously requires
> ~7–8 GB VRAM. On a 6 GB card, keep DeBERTa on CPU (`DEVICE = "cpu"`) and let
> Ollama use the GPU exclusively — this is the default configuration.

---

## Offline / Air-Gapped Setup

The pipeline runs fully offline after a one-time internet setup on any machine
with Docker. Model weights (LLaMA-3.1, DeBERTa) are exported as Docker volumes
and transported alongside the image via USB or a secure file share.

**`offline_install/` scripts** (Windows `.bat`, run in order):

| Script | Machine | What It Does |
|--------|---------|-------------|
| `01_configure_mirror.bat` | Both | Configure registry mirror + move Docker data-root off shared/network drives (run as Admin) |
| `02_build_image.bat` | Online | Build the slim pipeline image |
| `03_pull_models.bat` | Online | Download LLaMA-3.1 and DeBERTa into named Docker volumes |
| `04_export_for_transfer.bat` | Online | Package images + volumes into `transfer/` (~8–9 GB) |
| `05_load_on_offline_machine.bat` | Offline | Load images and restore volumes from `transfer/` |
| `06_run_pipeline.bat` | Offline | Start containers and run the pipeline |

Full guide including disk requirements, troubleshooting, and the first-run dataset
bootstrap: **[OFFLINE_DOCKER.md](OFFLINE_DOCKER.md)**

---

## Limitations

### Methodological

- **Same model decomposes and judges.** LLaMA-3.1 breaks the answer into claims
  and then judges those same claims. The model's biases compound — it tends to
  agree with its own outputs, which inflates the agreement rate.
- **Agreement is not correctness.** Both the NLI model and the LLM judge are
  pattern-matchers. They can agree and still both be wrong in the same direction;
  agreement is evidence of consistency, not accuracy.
- **No human ground truth.** There are no human-labelled faithfulness labels to
  calibrate against in this iteration. We measure internal consistency between two
  automated methods, not verified correctness.
- **Claim decomposition errors propagate silently.** Over-splitting, under-splitting,
  or dropping claims corrupt all downstream metrics without a visible error signal.
- **Non-determinism.** At default temperature, repeated runs may produce different
  claim decompositions and verdicts for the same input. Pin `temperature=0`
  throughout for fully reproducible output.

### Coverage

- **512-token hard cutoff on NLI.** DeBERTa truncates the source context at 512
  tokens (~380 words). Source passages where the key fact appears late will be
  systematically misscored as unsupported.
- **Single domain, English only.** QA subset of RAGTruth. Results may not
  generalise to summarisation, data-to-text tasks, or non-English text.
- **Small sample.** n ≈ 200 is illustrative, not statistically robust.

### Fallback Risk

- **HotpotQA fallback contaminates independence.** If RAGTruth is inaccessible and
  the HotpotQA fallback is triggered, LLaMA both *generates* the answers and
  *evaluates* them — a fundamental circularity. This must be stated explicitly in
  any write-up that uses the fallback path.

---

## Roadmap

- Calibration against a human-labelled subset of RAGTruth
- Adversarial context construction — deliberately misleading or contradictory sources
- Multilingual extension — Bengali and Hindi source documents
- Parallelised scoring to reduce wall-clock time on large example sets

---

## Why This Matters For AI Safety

Faithfulness failures in retrieval-augmented systems are a small, measurable instance
of a much larger problem in AI safety: verifying that a system's outputs are grounded
in what it was given, rather than in what is merely plausible. As RAG systems are
deployed in higher-stakes decision contexts — clinical, legal, financial — the gap
between fluent and faithful becomes a safety property, not a quality-of-life one.
This project grew directly out of building and hardening a production RAG system where
that gap had operational consequences, not just cosmetic ones.

---

## Repo Structure

```
rag-faithfulness-probe/
├── README.md
├── OFFLINE_DOCKER.md               # air-gapped Docker setup guide
│
├── Dockerfile                      # python:3.11-slim, CPU-only torch, no weights
├── docker-compose.yml              # ollama + pipeline services, pinned project name
├── requirements.txt                # local dev (default torch with CUDA)
├── requirements-docker.txt         # Docker build (CPU-only torch, ~230 MB)
├── .env.offline                    # offline mode env flags
│
├── offline_install/
│   ├── 01_configure_mirror.bat     # registry mirror + local data-root (Admin)
│   ├── 02_build_image.bat          # build slim pipeline image
│   ├── 03_pull_models.bat          # download LLaMA-3.1 + DeBERTa into volumes
│   ├── 04_export_for_transfer.bat  # export images + volumes to transfer/
│   ├── 05_load_on_offline_machine.bat  # restore on offline machine
│   └── 06_run_pipeline.bat         # run pipeline in offline mode
│
├── src/
│   ├── pipeline.py                 # entry point: runs stages A → E
│   ├── data_loader.py              # stage A — load + cache benchmark examples
│   ├── claim_decompose.py          # stage B — LLM claim extraction
│   ├── nli_scorer.py               # stage C(1) — DeBERTa NLI, pinned to CPU
│   ├── llm_judge.py                # stage C(2) — LLaMA judge via Ollama
│   ├── aggregate.py                # stage D — faithfulness + agreement metrics
│   └── report_generator.py        # stage E — JSON + CSV output
│
├── data/                           # auto-created; gitignored except examples.jsonl
│   ├── examples.jsonl
│   ├── claims/
│   └── scores/
│
├── results/
│   ├── faithfulness_report.json
│   ├── aggregate_scores.csv
│   └── disagreement_cases_raw.json
│
└── notes/
    ├── disagreement_cases.md       # manual write-up of 3–4 disagreement cases
    └── findings_note.md            # source for the findings PDF
```

---

## Hardware Requirements

| Setup | CPU | RAM | GPU | Estimated Run Time |
|-------|-----|-----|-----|--------------------|
| Local / Docker (CPU only) | Any modern x86 | 8 GB+ | Not required | 1–4 hours (200 examples) |
| Local (GPU, LLaMA only) | Any | 8 GB+ | 6 GB VRAM | 30–60 min |
| Local (GPU, LLaMA + DeBERTa) | Any | 8 GB+ | 8 GB+ VRAM | 15–30 min |

> The default Docker configuration runs DeBERTa on **CPU** and LLaMA via Ollama
> on **GPU if available**, or CPU if not. No configuration change is needed for
> this split — it is the recommended setup for hardware with ≤ 6 GB VRAM.
