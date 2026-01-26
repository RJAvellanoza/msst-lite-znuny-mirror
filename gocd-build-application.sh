#!/bin/bash
# GoCD Build Orchestration Script for MSSTLite
# Version: 2.0 (2026-01-26)
#
# This script handles automatic versioning:
# - If PATCH = 0 in SOPM → Use as-is (release version)
# - If PATCH > 0 in SOPM → Replace with pipeline counter (dev build)
#
# Usage: ./gocd-build-application.sh <APP_BUILD_DIR> <APP_CHECKOUT_DEST>
#
# Required Environment Variables:
#   GO_PIPELINE_NAME    - Pipeline identifier
#   GO_PIPELINE_COUNTER - Auto-incrementing build number
#   WRAPPER_WORKING_DIR - GoCD agent working directory
#
# See docs/VERSIONING.md for full documentation

# Strict mode:
#   -e : Exit immediately if a command exits with non-zero status
#   -u : Treat unset variables as an error
#   -o pipefail : Return value of pipeline is the last command to exit with non-zero
set -euo pipefail

# ==============================================================================
# PARAMETER VALIDATION
# ==============================================================================

APP_BUILD_DIR="$1"
APP_CHECKOUT_DEST="$2"

# Check required parameters
if [ -z "$APP_BUILD_DIR" ] || [ -z "$APP_CHECKOUT_DEST" ]; then
    echo "ERROR: Missing required parameters"
    echo "Usage: $0 <APP_BUILD_DIR> <APP_CHECKOUT_DEST>"
    exit 1
fi

# Check required environment variables
MISSING_VARS=""
[ -z "$GO_PIPELINE_NAME" ] && MISSING_VARS="$MISSING_VARS GO_PIPELINE_NAME"
[ -z "$GO_PIPELINE_COUNTER" ] && MISSING_VARS="$MISSING_VARS GO_PIPELINE_COUNTER"
[ -z "$WRAPPER_WORKING_DIR" ] && MISSING_VARS="$MISSING_VARS WRAPPER_WORKING_DIR"

if [ -n "$MISSING_VARS" ]; then
    echo "ERROR: Missing required environment variables:$MISSING_VARS"
    exit 1
fi

# Validate GO_PIPELINE_COUNTER is a number
if ! [[ "$GO_PIPELINE_COUNTER" =~ ^[0-9]+$ ]]; then
    echo "ERROR: GO_PIPELINE_COUNTER must be a number, got: $GO_PIPELINE_COUNTER"
    exit 1
fi

# ==============================================================================
# BUILD INFO
# ==============================================================================

echo "========================================"
echo "       GoCD Build Orchestration"
echo "========================================"
echo ""
echo "Pipeline: ${GO_PIPELINE_NAME}"
echo "Counter:  ${GO_PIPELINE_COUNTER}"
echo "Label:    ${GO_PIPELINE_LABEL}"
echo ""

# ==============================================================================
# PREPARE BUILD DIRECTORY
# ==============================================================================

# Clean and create build directory
rm -rf "$APP_BUILD_DIR"
mkdir -p "$APP_BUILD_DIR"

# Copy source files to build directory
SOURCE_DIR="$WRAPPER_WORKING_DIR/pipelines/$GO_PIPELINE_NAME"
if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: Source directory not found: $SOURCE_DIR"
    exit 1
fi
cp -r "$SOURCE_DIR"/* "$APP_BUILD_DIR"

# Create symlink to Znuny installation
ln -sf /opt/otrs "$APP_BUILD_DIR"/znuny-root

# Change to checkout directory
cd "$APP_BUILD_DIR"/"$APP_CHECKOUT_DEST"
chmod go+w .

# ==============================================================================
# VERSION INJECTION FUNCTION
# ==============================================================================

# inject_version: Modifies SOPM version for dev builds
#
# Arguments:
#   $1 - Path to SOPM file
#
# Behavior:
#   - PATCH = 0: Keep version as-is (release)
#   - PATCH > 0: Replace PATCH with GO_PIPELINE_COUNTER (dev build)
#
inject_version() {
    local SOPM="$1"

    # Skip if file doesn't exist
    if [ ! -f "$SOPM" ]; then
        echo "  SKIP: $SOPM not found"
        return
    fi

    # Extract current version from SOPM
    local CURRENT=$(grep '<Version>' "$SOPM" | sed 's/.*<Version>\([^<]*\)<\/Version>.*/\1/')

    # Validate version was found
    if [ -z "$CURRENT" ]; then
        echo "  ERROR: No <Version> tag found in $SOPM"
        return 1
    fi

    # Validate version format (X.Y.Z where X, Y, Z are numbers)
    if ! [[ "$CURRENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  ERROR: Invalid version format in $SOPM: $CURRENT (expected X.Y.Z)"
        return 1
    fi

    # Parse version components
    local MAJOR=$(echo "$CURRENT" | cut -d. -f1)
    local MINOR=$(echo "$CURRENT" | cut -d. -f2)
    local PATCH=$(echo "$CURRENT" | cut -d. -f3)

    # Determine action based on PATCH value
    if [ "$PATCH" = "0" ]; then
        # PATCH is 0 → Release version, keep as-is
        echo "  $SOPM: $CURRENT (RELEASE - keeping as-is)"
    else
        # PATCH > 0 → Dev build, inject pipeline counter
        local NEW_VERSION="${MAJOR}.${MINOR}.${GO_PIPELINE_COUNTER}"
        sed -i "s|<Version>${CURRENT}</Version>|<Version>${NEW_VERSION}</Version>|" "$SOPM"
        echo "  $SOPM: $CURRENT -> $NEW_VERSION (auto-versioned)"
    fi
}

# ==============================================================================
# VERSION INJECTION
# ==============================================================================

echo "=== Version Injection ==="
inject_version "MSSTLite.sopm"
# NOTE: znuny-users-groups.sopm is versioned independently (not auto-versioned)
# See docs/VERSIONING.md "Pending Questions" section for details
echo ""

# ==============================================================================
# BUILD PACKAGES
# ==============================================================================

echo "=== Building Packages ==="

# Build MSSTLite (primary package)
# Note: Using "echo y" instead of "yes" to avoid SIGPIPE (exit 141) when script closes stdin
echo "y" | ./build-package.sh --no-install --skip-version-increment

# Build znuny-users-groups (secondary package) - only if exists
SECONDARY_SOPM="$APP_BUILD_DIR/$APP_CHECKOUT_DEST/package-definitions/znuny-users-groups.sopm"
if [ -f "$SECONDARY_SOPM" ]; then
    /usr/bin/env perl /opt/otrs/bin/otrs.Console.pl Dev::Package::Build "$SECONDARY_SOPM" .
else
    echo "SKIP: znuny-users-groups.sopm not found"
fi

# Build TicketRestAPI (optional package) - only if exists
if [ -f "TicketRestAPI.sopm" ]; then
    /usr/bin/env perl /opt/otrs/bin/otrs.Console.pl Dev::Package::Build \
        "$APP_BUILD_DIR"/"$APP_CHECKOUT_DEST"/TicketRestAPI.sopm .
fi

# ==============================================================================
# COPY ARTIFACTS
# ==============================================================================

# Verify OPM files were created
OPM_COUNT=$(ls -1 *.opm 2>/dev/null | wc -l)
if [ "$OPM_COUNT" -eq 0 ]; then
    echo "ERROR: No .opm files were created"
    exit 1
fi

# Copy artifacts back to pipeline workspace for deployment stages
cp *.opm "$WRAPPER_WORKING_DIR/pipelines/$GO_PIPELINE_NAME"/

# ==============================================================================
# BUILD SUMMARY
# ==============================================================================

echo ""
echo "========================================"
echo "       Build Complete"
echo "========================================"
echo ""
echo "Packages built:"
ls -la "$WRAPPER_WORKING_DIR/pipelines/$GO_PIPELINE_NAME"/*.opm
