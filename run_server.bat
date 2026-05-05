@echo off
REM Simple helper to activate the venv and run the FastAPI server
SETLOCAL
SET VENV_DIR=%~dp0server\.venv
IF NOT EXIST "%VENV_DIR%\Scripts\activate.bat" (
  echo Virtual environment not found at %VENV_DIR%\. Run server\install_homr_env.ps1 first.
  exit /b 1
)
call "%VENV_DIR%\Scripts\activate.bat"
python -m uvicorn server.convert_server:app --host 0.0.0.0 --port 8000
