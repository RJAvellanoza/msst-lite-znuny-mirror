#!/usr/bin/env bash
# pipeline.sh — GoCD pipeline helper for znuny-dev-deploy
#
# Provides build, preflight, and deploy commands called by GoCD stages.
# Each function is self-contained and expects to run from the GoCD
# workspace root (where znuny-source/ is checked out).
#
# Usage:
#   gocd/pipeline.sh build
#   gocd/pipeline.sh preflight <environment>
#   gocd/pipeline.sh deploy <environment>
#
# Arguments:
#   environment  — inventory name: dev, ref (matches ansible/inventory/<env>.yaml)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "${SCRIPT_DIR}")"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

log() { echo "=== $* ==="; }

# Extract the version from an OPM filename.
# MSSTLite-1.0.35.opm → 1.0.35
extract_version() {
    local opm_path="$1"
    local filename
    filename="$(basename "${opm_path}")"
    # Strip prefix "MSSTLite-" and suffix ".opm"
    local version="${filename#MSSTLite-}"
    version="${version%.opm}"
    echo "${version}"
}

# Stamp CI version into MSSTLite.sopm before building.
# Reads MAJOR.MINOR from the committed SOPM version, replaces the patch
# with GO_PIPELINE_COUNTER. This ensures each CI build produces a unique,
# monotonically increasing version that matches across pipeline logs,
# OPM filename, and the Znuny package_repository table.
#
# Example: SOPM has 1.0.35, GO_PIPELINE_COUNTER=42 → stamps 1.0.42
# Locally (no counter): defaults to patch 0 → 1.0.0
stamp_ci_version() {
    local sopm="${SOURCE_DIR}/MSSTLite.sopm"
    if [[ ! -f "${sopm}" ]]; then
        echo "ERROR: MSSTLite.sopm not found at ${sopm}" >&2
        exit 1
    fi

    local current_version
    current_version=$(grep -m 1 '<Version>' "${sopm}" | sed 's/.*<Version>\(.*\)<\/Version>.*/\1/')

    if [[ -z "${current_version}" ]]; then
        echo "ERROR: Could not read <Version> from MSSTLite.sopm" >&2
        exit 1
    fi

    # Extract MAJOR.MINOR from MAJOR.MINOR.BUILD
    local major_minor="${current_version%.*}"
    local patch="${GO_PIPELINE_COUNTER:-0}"
    local ci_version="${major_minor}.${patch}"

    echo "Stamping CI version: ${current_version} → ${ci_version}"
    sed -i "s|<Version>${current_version}</Version>|<Version>${ci_version}</Version>|" "${sopm}"

    echo "${ci_version}"
}

require_arg() {
    local arg_name="$1"
    local arg_value="${2:-}"
    if [[ -z "${arg_value}" ]]; then
        echo "ERROR: ${arg_name} argument is required" >&2
        echo "Usage: $(basename "$0") <command> <environment>" >&2
        exit 1
    fi
}

# --------------------------------------------------------------------------- #
# Commands
# --------------------------------------------------------------------------- #

cmd_build() {
    log "Building MSSTLite OPM"

    # build-package.sh runs inside the source directory
    cd "${SOURCE_DIR}"

    # Stamp CI version into SOPM (MAJOR.MINOR from SOPM + pipeline counter as patch)
    # This runs BEFORE build-package.sh, which will skip auto-increment in --ci mode
    local version
    version="$(stamp_ci_version)"

    # Run the existing build script in CI mode (non-interactive, no auto-install)
    # build-package.sh --ci:
    #   - Skips interactive prompts for unlisted files
    #   - Skips auto-install
    #   - Skips version auto-increment (uses stamped version as-is)
    #   - Copies OPM to .build/ directory
    ./build-package.sh --ci

    # Verify the OPM artifact was produced
    local opm_file
    opm_file=$(find .build/ -name "MSSTLite-*.opm" 2>/dev/null | head -1)
    if [[ -z "${opm_file}" ]]; then
        echo "ERROR: No OPM file found in .build/ after build" >&2
        exit 1
    fi

    local version
    version="$(extract_version "${opm_file}")"

    ls -lh "${opm_file}"

    log "Build complete: MSSTLite ${version}"
}

cmd_preflight() {
    local env="$1"
    local inventory="${SOURCE_DIR}/ansible/inventory/${env}.yaml"

    if [[ ! -f "${inventory}" ]]; then
        echo "ERROR: Inventory file not found: ${inventory}" >&2
        exit 1
    fi

    log "Running preflight checks for ${env}"

    ANSIBLE_CONFIG="${SOURCE_DIR}/ansible/ansible.cfg" \
    ansible-playbook -i "${inventory}" \
        "${SOURCE_DIR}/ansible/playbooks/preflight.yaml"

    log "Preflight passed for ${env}"
}

cmd_deploy() {
    local env="$1"
    local inventory="${SOURCE_DIR}/ansible/inventory/${env}.yaml"

    # Find the OPM artifact from the build stage (fetched by GoCD)
    local artifact_path
    artifact_path="$(cd "${SOURCE_DIR}/.." && pwd)/package"
    local opm_file
    opm_file=$(find "${artifact_path}" -name "MSSTLite-*.opm" 2>/dev/null | head -1)

    if [[ ! -f "${inventory}" ]]; then
        echo "ERROR: Inventory file not found: ${inventory}" >&2
        exit 1
    fi

    if [[ -z "${opm_file}" || ! -f "${opm_file}" ]]; then
        echo "ERROR: OPM artifact not found in ${artifact_path}" >&2
        echo "Expected: ${artifact_path}/MSSTLite-*.opm" >&2
        exit 1
    fi

    local version
    version="$(extract_version "${opm_file}")"

    log "Deploying MSSTLite ${version} to ${env}"
    echo "Artifact: ${opm_file}"

    ANSIBLE_CONFIG="${SOURCE_DIR}/ansible/ansible.cfg" \
    ARTIFACT_PATH="${opm_file}" \
    DEPLOY_VERSION="${version}" \
    ansible-playbook -i "${inventory}" \
        "${SOURCE_DIR}/ansible/playbooks/deploy-znuny.yaml"

    log "Deployment complete: MSSTLite ${version} to ${env}"
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

main() {
    local command="${1:-}"

    if [[ -z "${command}" ]]; then
        echo "Usage: $(basename "$0") <build|preflight|deploy> [environment]" >&2
        exit 1
    fi

    shift

    case "${command}" in
        build)
            cmd_build
            ;;
        preflight)
            require_arg "environment" "${1:-}"
            cmd_preflight "$1"
            ;;
        deploy)
            require_arg "environment" "${1:-}"
            cmd_deploy "$1"
            ;;
        *)
            echo "ERROR: Unknown command: ${command}" >&2
            echo "Usage: $(basename "$0") <build|preflight|deploy> [environment]" >&2
            exit 1
            ;;
    esac
}

main "$@"
