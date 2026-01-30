@echo off
setlocal EnableDelayedExpansion

set "MIRROR_DIR=%USERPROFILE%\PRJ\MSSTLITE-MIRROR\msst-lite-znuny-mirror"
set "ORIGINAL_DIR=%USERPROFILE%\PRJ\MSSTLITE\msst-lite-znuny"

:: Check directories exist
if not exist "%MIRROR_DIR%" (
    echo ERROR: Mirror directory not found: %MIRROR_DIR%
    pause
    exit /b 1
)
if not exist "%ORIGINAL_DIR%" (
    echo ERROR: Original directory not found: %ORIGINAL_DIR%
    pause
    exit /b 1
)

:: Get current branch from MIRROR (source of truth)
cd /d "%MIRROR_DIR%"
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set "MIRROR_BRANCH=%%i"

:: Map main to master for original repo (BitBucket uses master)
set "ORIGINAL_BRANCH=%MIRROR_BRANCH%"
if "%MIRROR_BRANCH%"=="main" set "ORIGINAL_BRANCH=master"

:: Switch original repo to target branch
cd /d "%ORIGINAL_DIR%"
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set "CURRENT_ORIG_BRANCH=%%i"

if not "%ORIGINAL_BRANCH%"=="%CURRENT_ORIG_BRANCH%" (
    git show-ref --verify --quiet refs/heads/%ORIGINAL_BRANCH%
    if !errorlevel! equ 0 (
        git checkout %ORIGINAL_BRANCH% >nul 2>&1
    ) else (
        git fetch origin %ORIGINAL_BRANCH% 2>nul
        if !errorlevel! equ 0 (
            git checkout -b %ORIGINAL_BRANCH% origin/%ORIGINAL_BRANCH% >nul 2>&1
        ) else (
            git checkout -b %ORIGINAL_BRANCH% >nul 2>&1
        )
    )
)

echo.
echo ZNUNY PUSH: [%MIRROR_BRANCH%] -^> [%ORIGINAL_BRANCH%]
echo.

robocopy "%MIRROR_DIR%" "%ORIGINAL_DIR%" /MIR /XD .git scripts .claude /XF .gitignore CLAUDE.md /NJH /NJS /NDL /NFL

echo.
echo Git status:
git status --short
echo.
pause
