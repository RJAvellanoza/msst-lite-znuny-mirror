#!/bin/bash

# =============================================================================
# MSST Lite Znuny Mirror Script
# =============================================================================
# This script handles file synchronization between the original repository
# and the mirror directory for msst-lite-znuny.
# =============================================================================

# -----------------------------------------------------------------------------
# CONFIGURATION - Edit these paths as needed
# -----------------------------------------------------------------------------

# Path to the original repository (source for pull, destination for push)
ORIGINAL_REPO_PATH="/path/to/original/msst-lite-znuny"

# Path to the mirror directory (destination for pull, source for push)
MIRROR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/msst-lite-znuny-mirror"

# -----------------------------------------------------------------------------
# DO NOT EDIT BELOW THIS LINE
# -----------------------------------------------------------------------------

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored message
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Check if rsync is available
check_rsync() {
    if ! command -v rsync &> /dev/null; then
        print_msg "$RED" "Error: rsync is not installed. Please install rsync to use this script."
        exit 1
    fi
}

# Validate paths
validate_paths() {
    if [[ "$ORIGINAL_REPO_PATH" == "/path/to/original/msst-lite-znuny" ]]; then
        print_msg "$RED" "Error: Please configure ORIGINAL_REPO_PATH in the script."
        exit 1
    fi
}

# Pull: Copy files from original repository to mirror (excluding .git)
pull_files() {
    validate_paths

    if [[ ! -d "$ORIGINAL_REPO_PATH" ]]; then
        print_msg "$RED" "Error: Original repository path does not exist: $ORIGINAL_REPO_PATH"
        exit 1
    fi

    print_msg "$YELLOW" "Pulling files from original to mirror..."
    print_msg "$NC" "Source: $ORIGINAL_REPO_PATH"
    print_msg "$NC" "Destination: $MIRROR_PATH"

    rsync -av --delete \
        --exclude='.git' \
        --exclude='.git/' \
        "$ORIGINAL_REPO_PATH/" "$MIRROR_PATH/"

    if [[ $? -eq 0 ]]; then
        print_msg "$GREEN" "Pull completed successfully!"
    else
        print_msg "$RED" "Pull failed with errors."
        exit 1
    fi
}

# Push: Copy files from mirror to original repository (excluding .git and scripts)
push_files() {
    validate_paths

    if [[ ! -d "$MIRROR_PATH" ]]; then
        print_msg "$RED" "Error: Mirror path does not exist: $MIRROR_PATH"
        exit 1
    fi

    if [[ ! -d "$ORIGINAL_REPO_PATH" ]]; then
        print_msg "$YELLOW" "Warning: Original repository path does not exist. Creating: $ORIGINAL_REPO_PATH"
        mkdir -p "$ORIGINAL_REPO_PATH"
    fi

    print_msg "$YELLOW" "Pushing files from mirror to original..."
    print_msg "$NC" "Source: $MIRROR_PATH"
    print_msg "$NC" "Destination: $ORIGINAL_REPO_PATH"

    rsync -av --delete \
        --exclude='.git' \
        --exclude='.git/' \
        --exclude='scripts' \
        --exclude='scripts/' \
        "$MIRROR_PATH/" "$ORIGINAL_REPO_PATH/"

    if [[ $? -eq 0 ]]; then
        print_msg "$GREEN" "Push completed successfully!"
    else
        print_msg "$RED" "Push failed with errors."
        exit 1
    fi
}

# Show usage
usage() {
    echo "Usage: $0 {pull|push}"
    echo ""
    echo "Commands:"
    echo "  pull    Copy files from original repository to mirror (excludes .git)"
    echo "  push    Copy files from mirror to original repository (excludes .git and scripts)"
    echo ""
    echo "Configuration:"
    echo "  Edit ORIGINAL_REPO_PATH at the top of this script to set the original repository path."
    echo ""
    echo "Current paths:"
    echo "  Original: $ORIGINAL_REPO_PATH"
    echo "  Mirror:   $MIRROR_PATH"
}

# Main
check_rsync

case "$1" in
    pull)
        pull_files
        ;;
    push)
        push_files
        ;;
    *)
        usage
        exit 1
        ;;
esac
