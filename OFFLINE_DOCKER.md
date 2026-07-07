# Offline Docker Setup — RAG Faithfulness Probe

Everything needed to run this project on a machine with **no internet access**, using Docker.

---

## What Docker Does Here

Docker packages the Python environment (all packages, the right Python version, the right OS libraries) into a portable image. You build that image once on a machine with internet, export it as a file, carry it on a USB drive, and load it on any other machine running Docker — no Python installation, no pip, no dependency conflicts required.

This project uses **two containers** running together:

| Container | Image | What It Does |
|-----------|-------|-------------|
| `ollama` | `ollama/ollama` | Serves the LLaMA-3.1-8B model on an internal port; handles both claim decomposition and LLM-judge calls |
| `pipeline` | `rag-fp-pipeline` | Runs `src/pipeline.py` — loads dataset, scores claims, writes results |

The two containers talk over an internal Docker network (`rag-net`). They never touch the internet once running in offline mode.

Model weights live in **named Docker volumes**, not inside the image itself. This keeps the image small (~1.5 GB) and makes the model weights separately portable.

```
Host machine
├── docker-compose.yml         (orchestrates both containers)
├── data/                      (bind-mount: examples, claim cache, score cache)
├── results/                   (bind-mount: final output lands here)
└── Docker volumes
    ├── rag-fp_ollama-models   (LLaMA-3.1 weights, ~4.7 GB)
    └── rag-fp_hf-cache        (DeBERTa weights, ~1.7 GB)
```

---

## Prerequisites

Install on **both** machines (online and offline):

- **Docker Desktop** — https://www.docker.com/products/docker-desktop  
  Windows installer `.exe` can be downloaded on the online machine and carried to the offline machine.  
  Version required: Docker Desktop 4.x or later (includes Compose v2).

No Python installation is needed on either machine — Python runs inside the container.

---

## Disk Space Required

| Item | Where | Size |
|------|-------|------|
| Docker image build layers | Docker data-root | ~4 GB |
| `transfer/` export folder | Host filesystem | ~8–9 GB |
| Volumes (after restore) | Docker data-root | ~6.5 GB |
| **Total on online machine** | | **~12 GB** |
| **Total on offline machine** | | **~8 GB** |

---

## Part 1 — Online Machine (One Time Only)

Run the scripts in `offline_install/` **in order**. Each script prints clear success/error messages and pauses before exiting.

### Step 0 — Configure Docker (Recommended First)

> Skip this step if Docker Hub is accessible and Docker data is on a local drive.

Run as **Administrator**:
```
offline_install\01_configure_mirror.bat
```

This does two things:

**Registry mirror** — if Docker Hub is blocked on your network (common in corporate environments), you can point Docker at an internal mirror or a public alternative. The script prompts for the mirror URL; press Enter to skip. If you have a mirror URL (e.g., `https://registry.internal.company.com`), enter it here.

**Data-root relocation** — by default Docker stores images and volumes in `%APPDATA%\Docker\...`. On shared/networked Windows environments, this path can resolve to a network drive, causing volume operations to fail with `permission denied` or `protocol not supported` errors. This script moves `data-root` to `C:\DockerData` (a guaranteed local path). Restart Docker Desktop after running.

---

### Step 1 — Build The Image

```
offline_install\02_build_image.bat
```

Builds `rag-fp-pipeline:latest` from the `Dockerfile` in the project root.

- Uses `requirements-docker.txt` which installs CPU-only PyTorch (~230 MB) instead of the default CUDA variant (~2.3 GB). This is the main reason the image stays small.
- No model weights are downloaded at this stage.
- **Expected time:** 5–15 minutes.

---

### Step 2 — Download Model Weights

```
offline_install\03_pull_models.bat
```

Downloads model weights into named Docker volumes:

1. **LLaMA-3.1** — starts the Ollama container and runs `ollama pull llama3.1`. The weights (~4.7 GB, 4-bit quantized) are saved into the `rag-fp_ollama-models` volume at `/root/.ollama/models/`.

2. **DeBERTa-v3-large** — runs a temporary pipeline container that calls `AutoModelForSequenceClassification.from_pretrained(...)`. The weights (~1.7 GB) land in the `rag-fp_hf-cache` volume at `/root/.cache/huggingface/`.

**Expected time:** 20–40 minutes depending on internet speed.

---

### Step 3 — Export For Transfer

```
offline_install\04_export_for_transfer.bat
```

Packages everything into a `transfer/` folder:

| File | Contents | Size |
|------|---------|------|
| `rag-fp-pipeline.tar` | Pipeline Docker image | ~1.5 GB |
| `ollama.tar` | Ollama Docker image | ~1.2 GB |
| `alpine.tar` | Alpine image (volume restore helper) | ~10 MB |
| `ollama-models.tar` | LLaMA-3.1 weights | ~4.7 GB |
| `hf-cache.tar` | DeBERTa weights | ~1.7 GB |
| `docker-compose.yml` | Service config | <1 KB |
| `.env.offline` | Offline environment flags | <1 KB |

> **Dataset note:** The RAGTruth dataset (~50 MB) is downloaded on the first pipeline run and cached to `data/examples.jsonl`. For a truly air-gapped first run, also copy the `data/` folder to the offline machine after running the pipeline once locally, OR accept that the pipeline container will fail on the dataset step and handle it via the fallback (HotpotQA) which does require internet. See `06_run_pipeline.bat` for the two options.

---

## Part 2 — Transfer To The Offline Machine

Copy the entire `transfer/` folder and the `offline_install/` folder (with `05_` and `06_` scripts) to the offline machine via:
- USB drive
- Secure file share
- Internal network share (if available)

You also need to copy `docker-compose.yml` and `.env.offline` from the project root, or let `05_load_on_offline_machine.bat` copy them for you from `transfer/`.

---

## Part 3 — Offline Machine Setup

### Step 4 — Install Docker Desktop

Install Docker Desktop from the `.exe` installer you carried over. After installation, start it and wait for it to show "Docker Desktop is running" in the system tray.

Optionally run `01_configure_mirror.bat` on this machine too to set the local `data-root` (avoids network drive issues).

---

### Step 5 — Load Images And Volumes

```
offline_install\05_load_on_offline_machine.bat
```

Loads the Docker images from the `.tar` files and restores both model volumes. After this script:
- `docker images` shows `rag-fp-pipeline`, `ollama/ollama`, `alpine`
- `docker volume ls` shows `rag-fp_ollama-models` and `rag-fp_hf-cache`

No internet access is used at any point in this step.

---

### Step 6 — Run The Pipeline

```
offline_install\06_run_pipeline.bat
```

Starts both containers and runs the full pipeline. Output files appear in the host `results/` folder as the run completes.

The script activates offline mode by copying `.env.offline` to `.env`, which sets:
```
TRANSFORMERS_OFFLINE=1      # blocks HuggingFace model network calls
HF_DATASETS_OFFLINE=1       # blocks HuggingFace dataset network calls
```

**If the run is interrupted**, re-run the same script. Completed examples are cached in `data/claims/` and `data/scores/` and will be skipped.

---

## Understanding What Happens At Runtime

```
06_run_pipeline.bat
        │
        ▼
docker compose up
        │
        ├── starts  ollama container  (reads rag-fp_ollama-models volume)
        │           └── LLaMA-3.1 ready on http://ollama:11434
        │
        └── starts  pipeline container
                    │
                    ├─ Stage A: reads data/examples.jsonl (host bind-mount)
                    │
                    ├─ Stage B: POST http://ollama:11434  (claim decomposition)
                    │          writes data/claims/{id}.json
                    │
                    ├─ Stage C: DeBERTa loaded from rag-fp_hf-cache volume
                    │           (CPU inference, pinned to cpu device)
                    │          + POST http://ollama:11434  (LLM judge)
                    │          writes data/scores/{id}.json
                    │
                    ├─ Stage D: pure Python, no models
                    │
                    └─ Stage E: writes results/ (host bind-mount)
```

---

## Troubleshooting

### `docker: Error response from daemon: ... network drive`
Run `01_configure_mirror.bat` as Administrator to move `data-root` to `C:\DockerData`, then restart Docker Desktop.

### `Error response from daemon: pull access denied`
The image was not loaded from the tar file. Run `05_load_on_offline_machine.bat` again and check for errors.

### `connection refused` on `http://ollama:11434`
The Ollama container takes a few seconds to start. The pipeline container's `depends_on` is set but does not wait for readiness. If this happens, restart via `06_run_pipeline.bat` — on the second attempt Ollama is already warm.

### `OSError: We couldn't connect to ... huggingface.co`
`TRANSFORMERS_OFFLINE=1` was not set, and the model is missing from the hf-cache volume. Check that `.env.offline` was copied to `.env` and that `05_load_on_offline_machine.bat` completed without errors.

### Pipeline runs slow (1+ hour)
Expected on CPU-only. DeBERTa runs ~1–3 seconds per claim; LLaMA runs 5–30 seconds per claim. For 200 examples × ~5 claims = ~1000 inferences. This is a research run, not a production service.

### Resuming after interruption
Re-run `06_run_pipeline.bat`. The pipeline checks `data/claims/{id}.json` and `data/scores/{id}.json` before processing each example. Completed work is cached and skipped automatically.

---

## File Reference

```
rag-faithfulness-probe/
├── Dockerfile                    Pipeline image definition
├── requirements-docker.txt       CPU-only torch + packages
├── docker-compose.yml            Two-service orchestration
├── .env.offline                  Offline environment flags
└── offline_install/
    ├── 01_configure_mirror.bat   [ONLINE+OFFLINE] Docker daemon config
    ├── 02_build_image.bat        [ONLINE]         Build pipeline image
    ├── 03_pull_models.bat        [ONLINE]         Download LLaMA + DeBERTa
    ├── 04_export_for_transfer.bat[ONLINE]         Package everything to transfer/
    ├── 05_load_on_offline_machine.bat [OFFLINE]   Load images + restore volumes
    └── 06_run_pipeline.bat       [OFFLINE]        Run the pipeline
```
