@echo off
setlocal

cd /d "%~dp0"

echo Starting Development Environment...

start "identity-backend" cmd /k "title identity-backend && cd /d apps\identity_server\backend && uv uv run uvicorn app.main:app --port 8000 --reload"
start "identity-web" cmd /k "title identity-web && cd /d apps\identity_server\web && npm run dev"
start "workspace-backend" cmd /k "title workspace-backend && cd /d apps\work_space\backend && uv run uvicorn app.main:app --port 8001 --reload"
start "workspace-web" cmd /k "title workspace-web && cd /d apps\work_space\web && npm run dev"

echo.
echo Press any key to stop all services...
pause >nul

taskkill /FI "WINDOWTITLE eq identity-backend" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq identity-web" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq workspace-backend" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq workspace-web" /T /F >nul 2>&1

echo All services stopped.
endlocal
