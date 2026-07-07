@echo off
:: ============================================================================
:: 02_build_image.bat  [RUN ON: ONLINE machine]
:: ============================================================================
:: Builds the rag-fp-pipeline Docker image using CPU-only PyTorch.
:: The image contains only Python packages — NO model weights.
:: Model weights are downloaded separately by 03_pull_models.bat and live
:: in named Docker volumes.
::
:: Expected image size: ~1.5–2 GB (Python 3.11-slim + CPU torch + transformers)
:: Run time: 5–15 minutes depending on internet speed.
::
:: Pre-requisite: Docker Desktop must be running.
:: ============================================================================
setlocal

:: Change to project root (parent of offline_install/)
cd /d "%~dp0.."

echo ============================================================
echo  Building rag-fp-pipeline Docker image
echo  (CPU-only torch — no model weights baked in)
echo ============================================================
echo.
echo Project root: %CD%
echo.

:: Verify Docker is running
docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Docker is not running or not installed.
    echo Start Docker Desktop and wait for it to be ready before retrying.
    pause
    exit /b 1
)

:: Build with CPU requirements file
docker build ^
    -f Dockerfile ^
    -t rag-fp-pipeline:latest ^
    --progress=plain ^
    .

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Image build failed. Review the output above.
    echo Common causes:
    echo   - No internet access (PyPI / PyTorch mirror unreachable)
    echo   - Docker Hub rate limit (run 01_configure_mirror.bat first)
    echo   - Insufficient disk space (need ~5 GB free)
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  SUCCESS: Image built as rag-fp-pipeline:latest
echo  Next step: run 03_pull_models.bat
echo ============================================================
pause
endlocal
