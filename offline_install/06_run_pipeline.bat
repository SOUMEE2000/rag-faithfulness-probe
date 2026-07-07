@echo off
:: ============================================================================
:: 06_run_pipeline.bat  [RUN ON: OFFLINE machine]
:: ============================================================================
:: Starts the full RAG Faithfulness Probe pipeline in offline mode.
::
:: What this script does:
::   1. Activates offline mode (blocks all outbound network calls).
::   2. Ensures output directories exist on the host.
::   3. Starts the Ollama container, then the pipeline container.
::   4. The pipeline processes all examples and writes results to results\.
::   5. Shuts down containers when the pipeline exits.
::
:: Results land on your host machine (not inside Docker):
::   results\faithfulness_report.json
::   results\aggregate_scores.csv
::   results\disagreement_cases_raw.json
::
:: Note on resuming: if the pipeline is interrupted, re-run this script.
::   Completed examples are cached in data\claims\ and data\scores\ and
::   will be skipped automatically — only remaining work is re-done.
::
:: Pre-requisite: 05_load_on_offline_machine.bat must have completed.
:: ============================================================================
setlocal

cd /d "%~dp0.."

echo ============================================================
echo  RAG Faithfulness Probe — Pipeline Runner (Offline Mode)
echo ============================================================
echo.

docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Docker Desktop is not running.
    echo Start Docker Desktop and wait for it to be ready, then retry.
    pause & exit /b 1
)

:: ── Activate offline mode ────────────────────────────────────────────────────
:: Copy .env.offline -> .env so docker compose picks it up.
:: This sets TRANSFORMERS_OFFLINE=1 and HF_DATASETS_OFFLINE=1.
if exist .env.offline (
    copy .env.offline .env /y >nul
    echo Offline environment activated (TRANSFORMERS_OFFLINE=1, HF_DATASETS_OFFLINE=1).
) else (
    echo WARNING: .env.offline not found. HuggingFace libraries may attempt
    echo          network calls and fail. Run 05_load_on_offline_machine.bat first.
)

:: ── Ensure output directories exist ─────────────────────────────────────────
if not exist data mkdir data
if not exist data\claims mkdir data\claims
if not exist data\scores mkdir data\scores
if not exist results mkdir results
if not exist notes mkdir notes

:: ── Note on first-run dataset download ──────────────────────────────────────
:: The RAGTruth dataset (~50 MB) is fetched from HuggingFace on the FIRST run
:: and cached to data\examples.jsonl.  If HF_DATASETS_OFFLINE=1 and the cache
:: file does not exist yet, data_loader.py will fail.
::
:: TWO OPTIONS for a fully air-gapped first run:
::   Option A (easiest): On the online machine, run the pipeline once locally
::     (python src\pipeline.py) to populate data\examples.jsonl, then copy
::     the data\ folder alongside the transfer\ folder.
::   Option B: On the online machine, add data\examples.jsonl to the transfer
::     package and copy it to data\ here before running this script.
::
if not exist data\examples.jsonl (
    echo.
    echo WARNING: data\examples.jsonl not found.
    echo The pipeline needs the RAGTruth dataset.
    echo See the note in this script about Option A / Option B above.
    echo If you have internet access NOW, remove .env (or set HF_DATASETS_OFFLINE=0)
    echo and re-run — the dataset will be downloaded and cached automatically.
    echo.
    set /p "CONTINUE=Continue anyway? (y/n): "
    if /i "!CONTINUE!" neq "y" exit /b 0
)

:: ── Start pipeline ───────────────────────────────────────────────────────────
echo.
echo Starting containers...
echo   Ollama  : serving LLaMA-3.1 on internal port 11434
echo   Pipeline: running src/pipeline.py
echo.
echo Progress will appear below. This may take 1-4 hours for 200 examples
echo on CPU depending on hardware.
echo.

docker compose up --abort-on-container-exit

set EXIT_CODE=%ERRORLEVEL%
docker compose down 2>nul

echo.
if %EXIT_CODE% equ 0 (
    echo ============================================================
    echo  Pipeline finished successfully.
    echo  Results written to:
    echo    results\faithfulness_report.json
    echo    results\aggregate_scores.csv
    echo    results\disagreement_cases_raw.json
    echo  Now manually write up disagreement_cases.md in notes\
    echo  per the template in README.md.
    echo ============================================================
) else (
    echo ============================================================
    echo  Pipeline exited with code %EXIT_CODE%.
    echo  Completed examples are cached in data\claims\ and data\scores\.
    echo  Re-run this script to resume from where it stopped.
    echo ============================================================
)
pause
endlocal
