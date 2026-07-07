@echo off
:: ============================================================================
:: 05_load_on_offline_machine.bat  [RUN ON: OFFLINE machine]
:: ============================================================================
:: Loads Docker images and restores model volumes from the transfer\ folder
:: that was exported on the online machine.
::
:: Before running this script:
::   1. Install Docker Desktop on this machine (no internet needed for install
::      if you have the Docker Desktop installer .exe from the online machine).
::   2. Copy the entire transfer\ folder to this machine (USB / secure share).
::   3. Place transfer\ in the same directory as this bat file, or update
::      the TRANSFER_DIR variable below.
::   4. Run 01_configure_mirror.bat (optional but recommended if Docker data
::      is or might be on a network/shared drive).
::
:: After this script completes, run 06_run_pipeline.bat to start the pipeline.
:: ============================================================================
setlocal

cd /d "%~dp0.."

:: Path to the transfer folder — adjust if you placed it elsewhere
set "TRANSFER_DIR=%CD%\transfer"

echo ============================================================
echo  Loading images and restoring volumes (OFFLINE MODE)
echo  Transfer folder: %TRANSFER_DIR%
echo ============================================================
echo.

if not exist "%TRANSFER_DIR%" (
    echo ERROR: transfer\ folder not found at %TRANSFER_DIR%
    echo Copy the transfer\ folder from the online machine to this location.
    pause & exit /b 1
)

docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Docker Desktop is not running.
    echo Start Docker Desktop and wait for it to be ready, then retry.
    pause & exit /b 1
)

:: ── Load Docker images ───────────────────────────────────────────────────────
echo [1/5] Loading Alpine image (volume restore helper)...
docker load -i "%TRANSFER_DIR%\alpine.tar"
if %ERRORLEVEL% neq 0 ( echo ERROR loading alpine.tar & pause & exit /b 1 )

echo [2/5] Loading Ollama image...
docker load -i "%TRANSFER_DIR%\ollama.tar"
if %ERRORLEVEL% neq 0 ( echo ERROR loading ollama.tar & pause & exit /b 1 )

echo [3/5] Loading pipeline image...
docker load -i "%TRANSFER_DIR%\rag-fp-pipeline.tar"
if %ERRORLEVEL% neq 0 ( echo ERROR loading rag-fp-pipeline.tar & pause & exit /b 1 )

:: ── Create and restore named volumes ────────────────────────────────────────
echo.
echo [4/5] Restoring Ollama model volume (rag-fp_ollama-models)...
echo       LLaMA weights are ~4.7 GB — this will take a few minutes.
docker volume create rag-fp_ollama-models >nul 2>&1
docker run --rm ^
    -v rag-fp_ollama-models:/dest ^
    -v "%TRANSFER_DIR%":/src ^
    alpine tar xf /src/ollama-models.tar -C /dest
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to restore ollama-models volume.
    pause & exit /b 1
)

echo [5/5] Restoring HuggingFace cache volume (rag-fp_hf-cache)...
docker volume create rag-fp_hf-cache >nul 2>&1
docker run --rm ^
    -v rag-fp_hf-cache:/dest ^
    -v "%TRANSFER_DIR%":/src ^
    alpine tar xf /src/hf-cache.tar -C /dest
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to restore hf-cache volume.
    pause & exit /b 1
)

:: ── Copy config files to project root ───────────────────────────────────────
echo.
echo Copying docker-compose.yml and .env.offline to project root...
if not exist "%CD%\docker-compose.yml" (
    copy "%TRANSFER_DIR%\docker-compose.yml" "%CD%\" /y >nul
)
copy "%TRANSFER_DIR%\.env.offline" "%CD%\" /y >nul

:: ── Create output directories ────────────────────────────────────────────────
echo Creating output directories (data\, results\, notes\)...
if not exist data mkdir data
if not exist data\claims mkdir data\claims
if not exist data\scores mkdir data\scores
if not exist results mkdir results
if not exist notes mkdir notes

echo.
echo ============================================================
echo  SUCCESS: All images loaded, all volumes restored.
echo  Loaded images:
docker images --filter reference=rag-fp-pipeline --filter reference=ollama/ollama --filter reference=alpine --format "  {{.Repository}}:{{.Tag}}  ({{.Size}})"
echo.
echo  Volumes:
docker volume ls --filter name=rag-fp --format "  {{.Name}}"
echo.
echo  Next step: run 06_run_pipeline.bat
echo ============================================================
pause
endlocal
