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

:: Get current branch from original
cd /d "%ORIGINAL_DIR%"
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set "BRANCH=%%i"
echo Original branch: %BRANCH%

:: Map master to main for mirror repo (GitHub uses main)
set "TARGET_BRANCH=%BRANCH%"
if "%BRANCH%"=="master" set "TARGET_BRANCH=main"
echo Target branch: %TARGET_BRANCH%

:: Switch to mirror and match branch
cd /d "%MIRROR_DIR%"
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set "MIRROR_BRANCH=%%i"
echo Mirror branch: %MIRROR_BRANCH%

if not "%TARGET_BRANCH%"=="%MIRROR_BRANCH%" (
    echo.
    echo Switching mirror repo to branch: %TARGET_BRANCH%

    :: Check if branch exists locally
    git show-ref --verify --quiet refs/heads/%TARGET_BRANCH%
    if !errorlevel! equ 0 (
        git checkout %TARGET_BRANCH%
    ) else (
        :: Check if branch exists on remote
        git fetch origin %TARGET_BRANCH% 2>nul
        if !errorlevel! equ 0 (
            git checkout -b %TARGET_BRANCH% origin/%TARGET_BRANCH%
        ) else (
            :: Create new branch
            echo Creating new branch: %TARGET_BRANCH%
            git checkout -b %TARGET_BRANCH%
        )
    )
)

echo.
echo Syncing files...
echo Source: %ORIGINAL_DIR%
echo Destination: %MIRROR_DIR%
echo.

robocopy "%ORIGINAL_DIR%" "%MIRROR_DIR%" /MIR /XD .git scripts /XF .gitignore

echo.
echo ============================================
echo  Git status in mirror repo:
echo ============================================
git status --short

echo.
echo Done!
pause
