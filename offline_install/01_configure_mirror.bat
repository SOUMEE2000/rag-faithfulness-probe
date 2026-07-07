@echo off
:: ============================================================================
:: 01_configure_mirror.bat  [RUN ON: ONLINE machine, before building]
:: ============================================================================
:: Configures the Docker daemon with:
::   (a) A registry mirror — for corporate/restricted networks where Docker Hub
::       is blocked or rate-limited. Docker routes pulls through the mirror URL.
::   (b) A local data-root — moves Docker's storage off a shared network drive.
::       Shared/mapped drives often break Docker volume operations due to file
::       locking and permission differences. Moving data-root to a local path
::       (C:\DockerData) fixes this.
::
:: Run this script ONCE on each machine (online and offline), then restart
:: Docker Desktop before doing anything else.
::
:: Must be run as Administrator.
:: ============================================================================
setlocal enabledelayedexpansion

net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: This script must be run as Administrator.
    echo Right-click the bat file and choose "Run as administrator".
    pause
    exit /b 1
)

set "DAEMON_JSON=%APPDATA%\Docker\daemon.json"
set "LOCAL_DATA_ROOT=C:\DockerData"

echo ============================================================
echo  Docker Daemon Configurator
echo  Configuring registry mirror + local data-root
echo ============================================================
echo.
echo Docker data will be moved to: %LOCAL_DATA_ROOT%
echo This avoids issues with network/shared drives.
echo.
set /p "MIRROR_URL=Enter registry mirror URL (press Enter to skip, e.g. https://mirror.example.com): "

:: Ensure Docker AppData folder exists
if not exist "%APPDATA%\Docker" mkdir "%APPDATA%\Docker"

:: Build the daemon.json content using PowerShell (handles JSON reliably)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$daemonPath = '%DAEMON_JSON%'; ^
$localRoot = '%LOCAL_DATA_ROOT%'.Replace('\','\\'); ^
$mirror = '%MIRROR_URL%'.Trim(); ^
$cfg = if (Test-Path $daemonPath) { ^
    try { Get-Content $daemonPath -Raw | ConvertFrom-Json } ^
    catch { Write-Warning 'Existing daemon.json is malformed — creating fresh.'; [PSCustomObject]@{} } ^
} else { [PSCustomObject]@{} }; ^
$cfg | Add-Member -NotePropertyName 'data-root' -NotePropertyValue $localRoot -Force; ^
if ($mirror -ne '') { ^
    $cfg | Add-Member -NotePropertyName 'registry-mirrors' -NotePropertyValue @($mirror) -Force; ^
    Write-Host ('Registry mirror set to: ' + $mirror) -ForegroundColor Cyan ^
} else { ^
    Write-Host 'No mirror configured (skipped).' -ForegroundColor Yellow ^
}; ^
$cfg | ConvertTo-Json -Depth 5 | Set-Content $daemonPath; ^
Write-Host ('daemon.json written to: ' + $daemonPath) -ForegroundColor Green; ^
Write-Host ('data-root set to: ' + $localRoot) -ForegroundColor Green"

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to update daemon.json. Check PowerShell errors above.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  ACTION REQUIRED: Restart Docker Desktop now.
echo  Right-click the Docker icon in the system tray
echo  and choose "Restart Docker Desktop".
echo  Wait for Docker to fully restart before running the
echo  next script.
echo ============================================================
pause
endlocal
