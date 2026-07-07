# ── Stage: runtime ────────────────────────────────────────────────────────────
# python:3.11-slim keeps the base layer small (~130 MB).
# Model weights (LLaMA, DeBERTa) are NOT baked in; they live in named volumes
# that are exported separately via the offline_install/ scripts.
FROM python:3.11-slim

LABEL maintainer="rag-faithfulness-probe"
LABEL description="RAG Faithfulness Probe — pipeline container (CPU-only)"

# Install curl (used for Ollama connectivity checks in bat scripts).
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements first — Docker layer caches this unless the file changes.
COPY requirements-docker.txt ./requirements-docker.txt

# Install CPU-only torch + all other packages.
# The --extra-index-url is only needed at build time; the offline image
# already has everything installed.
RUN pip install --no-cache-dir -r requirements-docker.txt

# Copy source code last (changes most frequently — keeps earlier layers cached).
COPY src/ ./src/

# pipeline.py uses relative paths (data/, results/) anchored to its own
# directory, so we set WORKDIR to /app/src.
WORKDIR /app/src

CMD ["python", "pipeline.py"]
