@echo off
setlocal EnableDelayedExpansion

echo ============================================
echo  ZNUNY: ORIGINAL TO MIRROR - PULL
echo ============================================
echo.

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
echo Mirror branch: %MIRROR_BRANCH%

:: Map main to master for original repo (BitBucket uses master)
set "ORIGINAL_BRANCH=%MIRROR_BRANCH%"
if "%MIRROR_BRANCH%"=="main" set "ORIGINAL_BRANCH=master"
echo Original branch: %ORIGINAL_BRANCH%

:: Switch original repo to target branch
cd /d "%ORIGINAL_DIR%"
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set "CURRENT_ORIG_BRANCH=%%i"

if not "%ORIGINAL_BRANCH%"=="%CURRENT_ORIG_BRANCH%" (
    echo.
    echo Switching original repo to branch: %ORIGINAL_BRANCH%

    :: Check if branch exists locally
    git show-ref --verify --quiet refs/heads/%ORIGINAL_BRANCH%
    if !errorlevel! equ 0 (
        git checkout %ORIGINAL_BRANCH%
    ) else (
        :: Check if branch exists on remote
        git fetch origin %ORIGINAL_BRANCH% 2>nul
        if !errorlevel! equ 0 (
            git checkout -b %ORIGINAL_BRANCH% origin/%ORIGINAL_BRANCH%
        ) else (
            :: Create new branch
            echo Creating new branch: %ORIGINAL_BRANCH%
            git checkout -b %ORIGINAL_BRANCH%
        )
    )
)

echo.
echo Syncing files...
echo Source: %ORIGINAL_DIR% [%ORIGINAL_BRANCH%]
echo Destination: %MIRROR_DIR% [%MIRROR_BRANCH%]
echo.

robocopy "%ORIGINAL_DIR%" "%MIRROR_DIR%" /MIR /XD .git scripts .claude /XF .gitignore CLAUDE.md

echo.
echo ============================================
echo  Git status in mirror repo:
echo ============================================
cd /d "%MIRROR_DIR%"
git status --short

echo.
echo Done!
pause
