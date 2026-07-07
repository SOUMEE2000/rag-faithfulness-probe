@echo off
:: ============================================================================
:: 03_pull_models.bat  [RUN ON: ONLINE machine]
:: ============================================================================
:: Downloads model weights into named Docker volumes:
::
::   rag-fp_ollama-models  — LLaMA-3.1-8B (~4.7 GB, pulled by Ollama)
::   rag-fp_hf-cache       — DeBERTa-v3-large (~1.7 GB, downloaded by HuggingFace)
::
:: Both volumes will be exported to .tar files in the next step (04).
:: Nothing is baked into the image — the image stays small and reusable.
::
:: Pre-requisite: 02_build_image.bat must have completed successfully.
:: Run time: 20–40 minutes depending on internet speed.
:: ============================================================================
setlocal

cd /d "%~dp0.."

echo ============================================================
echo  Downloading model weights into Docker volumes
echo  (This requires internet — run only on the online machine)
echo ============================================================
echo.

docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Docker is not running.
    pause & exit /b 1
)

:: ── Step 1: Pull LLaMA-3.1 via Ollama ──────────────────────────────────────
echo [1/2] Starting Ollama container and pulling llama3.1 (~4.7 GB)...
echo       This will take a while — do not close this window.
echo.

docker compose up ollama -d
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to start Ollama container.
    pause & exit /b 1
)

:: Wait for Ollama server to be ready
echo Waiting for Ollama server to start...
:wait_loop
timeout /t 3 /nobreak >nul
docker compose exec ollama curl -s http://localhost:11434 >nul 2>&1
if %ERRORLEVEL% neq 0 goto wait_loop
echo Ollama server is ready.
echo.

docker compose exec ollama ollama pull llama3.1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to pull llama3.1.
    echo Check your internet connection and available disk space (need ~5 GB free).
    docker compose down
    pause & exit /b 1
)
echo LLaMA-3.1 pulled successfully.

:: ── Step 2: Download DeBERTa into hf-cache volume ──────────────────────────
echo.
echo [2/2] Downloading DeBERTa NLI model into hf-cache volume (~1.7 GB)...

:: Write the download script to a temp file so batch escaping is not a problem
set "DLSCRIPT=%TEMP%\dl_deberta_%RANDOM%.py"
(
echo from transformers import AutoTokenizer, AutoModelForSequenceClassification
echo MODEL = "MoritzLaurer/DeBERTa-v3-large-mnli-fever-anli-ling-wanli"
echo print(f"Downloading tokenizer for {MODEL} ...")
echo AutoTokenizer.from_pretrained(MODEL)
echo print(f"Downloading model weights for {MODEL} ...")
echo AutoModelForSequenceClassification.from_pretrained(MODEL)
echo print("DeBERTa download complete.")
) > "%DLSCRIPT%"

:: Mount the temp script into the pipeline container and run it.
:: The hf-cache volume is mounted automatically via docker-compose.
docker compose run --rm ^
    -v "%DLSCRIPT%:/tmp/dl_deberta.py" ^
    pipeline python /tmp/dl_deberta.py

if %ERRORLEVEL% neq 0 (
    echo ERROR: DeBERTa download failed. Review output above.
    del "%DLSCRIPT%" 2>nul
    docker compose down
    pause & exit /b 1
)

del "%DLSCRIPT%" 2>nul

:: Stop all containers — we are done downloading
docker compose down

echo.
echo ============================================================
echo  SUCCESS: All model weights downloaded into Docker volumes.
echo    rag-fp_ollama-models  (LLaMA-3.1)
echo    rag-fp_hf-cache       (DeBERTa)
echo  Next step: run 04_export_for_transfer.bat
echo ============================================================
pause
endlocal
