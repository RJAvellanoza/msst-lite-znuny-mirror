# =============================================================================
# MSST Lite Znuny Mirror Script (PowerShell)
# =============================================================================
# This script handles file synchronization between the original repository
# and the mirror directory for msst-lite-znuny.
# =============================================================================

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------

$ORIGINAL_REPO_PATH = "$env:USERPROFILE\PRJ\MSSTLITE\msst-lite-znuny"
$MIRROR_PATH = "$PSScriptRoot\..\msst-lite-znuny-mirror"

# Resolve to absolute path
$MIRROR_PATH = (Resolve-Path $MIRROR_PATH -ErrorAction SilentlyContinue).Path
if (-not $MIRROR_PATH) {
    $MIRROR_PATH = "$PSScriptRoot\.."
}

# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------

function Write-ColorMessage {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Show-Usage {
    Write-Host "Usage: .\znuny-mirror.ps1 <command>"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  pull    Copy files from original repository to mirror (excludes .git)"
    Write-Host "  push    Copy files from mirror to original repository (excludes .git and scripts)"
    Write-Host ""
    Write-Host "Current paths:"
    Write-Host "  Original: $ORIGINAL_REPO_PATH"
    Write-Host "  Mirror:   $MIRROR_PATH"
}

function Invoke-Pull {
    if (-not (Test-Path $ORIGINAL_REPO_PATH)) {
        Write-ColorMessage "Error: Original repository path does not exist: $ORIGINAL_REPO_PATH" "Red"
        exit 1
    }

    Write-ColorMessage "Pulling files from original to mirror..." "Yellow"
    Write-Host "Source: $ORIGINAL_REPO_PATH"
    Write-Host "Destination: $MIRROR_PATH"

    # /MIR = Mirror (equivalent to rsync --delete)
    # /XD = Exclude directories
    # /XF = Exclude files
    # /NFL /NDL = No file/directory list (cleaner output)
    # /NJH /NJS = No job header/summary
    robocopy $ORIGINAL_REPO_PATH $MIRROR_PATH /MIR /XD .git /NFL /NDL

    if ($LASTEXITCODE -le 7) {
        Write-ColorMessage "Pull completed successfully!" "Green"
    } else {
        Write-ColorMessage "Pull failed with errors. Exit code: $LASTEXITCODE" "Red"
        exit 1
    }
}

function Invoke-Push {
    if (-not (Test-Path $MIRROR_PATH)) {
        Write-ColorMessage "Error: Mirror path does not exist: $MIRROR_PATH" "Red"
        exit 1
    }

    if (-not (Test-Path $ORIGINAL_REPO_PATH)) {
        Write-ColorMessage "Warning: Original repository path does not exist. Creating: $ORIGINAL_REPO_PATH" "Yellow"
        New-Item -ItemType Directory -Path $ORIGINAL_REPO_PATH -Force | Out-Null
    }

    Write-ColorMessage "Pushing files from mirror to original..." "Yellow"
    Write-Host "Source: $MIRROR_PATH"
    Write-Host "Destination: $ORIGINAL_REPO_PATH"

    # Exclude .git and scripts directories
    robocopy $MIRROR_PATH $ORIGINAL_REPO_PATH /MIR /XD .git scripts /NFL /NDL

    if ($LASTEXITCODE -le 7) {
        Write-ColorMessage "Push completed successfully!" "Green"
    } else {
        Write-ColorMessage "Push failed with errors. Exit code: $LASTEXITCODE" "Red"
        exit 1
    }
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

$command = $args[0]

switch ($command) {
    "pull" { Invoke-Pull }
    "push" { Invoke-Push }
    default { Show-Usage; exit 1 }
}
