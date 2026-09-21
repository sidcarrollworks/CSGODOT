@echo off
REM Runs scripts/inspect_assets.sh through Git Bash and waits, so the window
REM does not vanish before the output can be read. Double-clicking this is
REM fine. The same output is written to inspect-output.txt either way.

setlocal
cd /d "%~dp0\.."

set "BASH_EXE="
for %%B in (
  "%ProgramFiles%\Git\bin\bash.exe"
  "%ProgramFiles(x86)%\Git\bin\bash.exe"
  "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
) do if exist %%B if not defined BASH_EXE set "BASH_EXE=%%~B"

if not defined BASH_EXE (
  where bash.exe >nul 2>&1 && for /f "delims=" %%B in ('where bash.exe') do if not defined BASH_EXE set "BASH_EXE=%%B"
)

if not defined BASH_EXE (
  echo Could not find Git Bash.
  echo.
  echo Install Git for Windows from https://git-scm.com/download/win
  echo then run this again.
  echo.
  pause
  exit /b 1
)

"%BASH_EXE%" scripts/inspect_assets.sh

echo.
echo ----------------------------------------------------------------
echo Output is also saved to inspect-output.txt in the project folder.
echo ----------------------------------------------------------------
pause
