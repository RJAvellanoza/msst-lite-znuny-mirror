@echo off
setlocal EnableDelayedExpansion

echo ============================================
echo  ZNUNY: MIRROR TO ORIGINAL - PUSH
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

:: Get current branch from mirror
cd /d "%MIRROR_DIR%"
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set "BRANCH=%%i"
echo Mirror branch: %BRANCH%

:: Switch to original and match branch
cd /d "%ORIGINAL_DIR%"
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set "ORIG_BRANCH=%%i"
echo Original branch: %ORIG_BRANCH%

if not "%BRANCH%"=="%ORIG_BRANCH%" (
    echo.
    echo Switching original repo to branch: %BRANCH%

    :: Check if branch exists locally
    git show-ref --verify --quiet refs/heads/%BRANCH%
    if !errorlevel! equ 0 (
        git checkout %BRANCH%
    ) else (
        :: Check if branch exists on remote
        git fetch origin %BRANCH% 2>nul
        if !errorlevel! equ 0 (
            git checkout -b %BRANCH% origin/%BRANCH%
        ) else (
            :: Create new branch
            echo Creating new branch: %BRANCH%
            git checkout -b %BRANCH%
        )
    )
)

echo.
echo Syncing files...
echo Source: %MIRROR_DIR%
echo Destination: %ORIGINAL_DIR%
echo.

robocopy "%MIRROR_DIR%" "%ORIGINAL_DIR%" /MIR /XD .git scripts /XF .gitignore

echo.
echo ============================================
echo  Git status in original repo:
echo ============================================
git status --short

echo.
echo Done!
pause
