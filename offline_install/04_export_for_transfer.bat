@echo off
:: ============================================================================
:: 04_export_for_transfer.bat  [RUN ON: ONLINE machine]
:: ============================================================================
:: Packages everything needed to run on an offline machine into a single
:: transfer\ folder. Copy the entire transfer\ folder to USB or a network
:: share to move to the offline machine.
::
:: Contents of transfer\ after this script:
::   rag-fp-pipeline.tar    — pipeline Docker image
::   ollama.tar             — Ollama Docker image
::   alpine.tar             — Alpine image (used for volume restore)
::   ollama-models.tar      — LLaMA-3.1 model weights volume
::   hf-cache.tar           — DeBERTa model weights volume
::   docker-compose.yml     — Compose config (copy to project root offline)
::   .env.offline           — Environment file for offline mode
::
:: Total size: ~8–9 GB.  Ensure the destination drive has 10 GB free.
::
:: Pre-requisite: 03_pull_models.bat must have completed successfully.
:: ============================================================================
setlocal

cd /d "%~dp0.."

echo ============================================================
echo  Exporting images and volumes for offline transfer
echo ============================================================
echo.

docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Docker is not running.
    pause & exit /b 1
)

:: Create transfer directory
if not exist transfer mkdir transfer

:: ── Pull Alpine (needed for volume operations on offline machine) ───────────
echo Pulling alpine image for volume restore helper...
docker pull alpine:latest
if %ERRORLEVEL% neq 0 (
    echo WARNING: Could not pull alpine. Trying with existing local image.
)

:: ── Save Docker images ──────────────────────────────────────────────────────
echo.
echo [1/5] Saving pipeline image  (rag-fp-pipeline.tar)...
docker save rag-fp-pipeline:latest -o transfer\rag-fp-pipeline.tar

echo [2/5] Saving Ollama image    (ollama.tar)...
docker save ollama/ollama:latest -o transfer\ollama.tar

echo [3/5] Saving Alpine image    (alpine.tar)...
docker save alpine:latest -o transfer\alpine.tar

:: ── Export named volumes ─────────────────────────────────────────────────────
echo.
echo [4/5] Exporting Ollama model volume (ollama-models.tar) ...
echo       This may take several minutes for the 4.7 GB LLaMA weights.
docker run --rm ^
    -v rag-fp_ollama-models:/src ^
    -v "%CD%\transfer":/dest ^
    alpine tar cf /dest/ollama-models.tar -C /src .

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to export ollama-models volume.
    echo Make sure 03_pull_models.bat was completed successfully.
    pause & exit /b 1
)

echo [5/5] Exporting HuggingFace cache volume (hf-cache.tar) ...
docker run --rm ^
    -v rag-fp_hf-cache:/src ^
    -v "%CD%\transfer":/dest ^
    alpine tar cf /dest/hf-cache.tar -C /src .

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to export hf-cache volume.
    pause & exit /b 1
)

:: ── Copy config files ────────────────────────────────────────────────────────
echo.
echo Copying configuration files...
copy docker-compose.yml transfer\ /y >nul
copy .env.offline transfer\ /y >nul

:: ── Summary ──────────────────────────────────────────────────────────────────
echo.
echo ============================================================
echo  Transfer package ready in: %CD%\transfer\
echo ============================================================
echo.
dir transfer /b
echo.
echo Copy the entire "transfer\" folder to your USB drive or
echo secure file share, then run 05_load_on_offline_machine.bat
echo on the offline machine.
echo ============================================================
pause
endlocal
