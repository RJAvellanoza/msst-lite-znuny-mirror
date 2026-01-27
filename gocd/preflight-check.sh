#!/bin/bash
# Pre-flight validation for GoCD deployment pipeline
# Checks SSH keys, permissions, environment variables, and Proxmox snapshot capability
#
# General Checks:
#   1. SSH private key exists
#   2. SSH key permissions (600)
#   3. SSH config file (optional)
#   4. Environment variables (DEV_ZNUNY_HOST required)
#   5. Version format validation
#
# Environment Checks (DEV and REF):
#   1. SSH to Proxmox host (port 22) for snapshots
#   2. pct command available on Proxmox host
#   3. Container ID valid

set -e

echo "========================================"
echo "       PRE-FLIGHT CHECKS"
echo "========================================"
echo ""
echo "Timestamp: $(date -Iseconds)"
echo "Agent: $(hostname)"
echo ""

CHECKS_PASSED=0
CHECKS_WARNED=0
CHECKS_FAILED=0

# ==============================================================================
# ENVIRONMENT CHECK FUNCTION
# ==============================================================================

# Run environment-specific checks
# Arguments: ENV_NAME, HOST_VAR_VALUE
check_environment() {
  local ENV_NAME="$1"
  local PROXMOX_HOST="$2"
  local CONTAINER_ID="${ZNUNY_CONTAINER_ID:-}"
  local ENV_PASSED=0
  local ENV_WARNED=0
  local ENV_FAILED=0

  echo ""
  echo "--- $ENV_NAME Environment Checks ---"
  echo ""

  # Check 1/3: SSH to Proxmox host (port 22)
  echo -n "[Check 1/3] SSH to Proxmox host (port 22)... "
  if [ -z "$PROXMOX_HOST" ]; then
    echo "SKIP (${ENV_NAME}_ZNUNY_HOST not set)"
    ENV_WARNED=$((ENV_WARNED + 1))
  else
    if ssh -p 22 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" "exit" 2>/dev/null; then
      echo "PASS"
      ENV_PASSED=$((ENV_PASSED + 1))
    else
      echo "FAIL"
      echo ""
      echo "ERROR: SSH to $ENV_NAME Proxmox host port 22 failed"
      echo "Host: $PROXMOX_HOST"
      echo ""
      echo "Possible causes:"
      echo "  - GoCD agent's public key not in Proxmox host's /root/.ssh/authorized_keys"
      echo "  - Firewall blocking port 22 on Proxmox host"
      echo "  - PubkeyAuthentication not enabled in Proxmox host's sshd_config"
      echo ""
      echo "Resolution:"
      echo "  1. SSH to Proxmox host manually and add GoCD agent's public key"
      echo "  2. Ensure PubkeyAuthentication yes in /etc/ssh/sshd_config"
      echo "  3. Restart sshd: systemctl restart sshd"
      ENV_FAILED=$((ENV_FAILED + 1))
    fi
  fi

  # Check 2/3: pct command exists on Proxmox host
  echo -n "[Check 2/3] pct command available... "
  if [ -z "$PROXMOX_HOST" ]; then
    echo "SKIP (${ENV_NAME}_ZNUNY_HOST not set)"
    ENV_WARNED=$((ENV_WARNED + 1))
  elif [ $ENV_FAILED -gt 0 ]; then
    echo "SKIP (SSH failed)"
    ENV_WARNED=$((ENV_WARNED + 1))
  else
    if ssh -p 22 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" "which pct" >/dev/null 2>&1; then
      echo "PASS"
      ENV_PASSED=$((ENV_PASSED + 1))
    else
      echo "FAIL"
      echo ""
      echo "ERROR: pct command not found on $ENV_NAME Proxmox host"
      echo "Host: $PROXMOX_HOST"
      echo ""
      echo "This indicates the host is not a Proxmox VE installation"
      ENV_FAILED=$((ENV_FAILED + 1))
    fi
  fi

  # Check 3/3: Container ID is valid
  echo -n "[Check 3/3] Container ID valid... "
  if [ -z "$CONTAINER_ID" ]; then
    echo "SKIP (ZNUNY_CONTAINER_ID not set)"
    ENV_WARNED=$((ENV_WARNED + 1))
  elif [ -z "$PROXMOX_HOST" ]; then
    echo "SKIP (${ENV_NAME}_ZNUNY_HOST not set)"
    ENV_WARNED=$((ENV_WARNED + 1))
  elif [ $ENV_FAILED -gt 0 ]; then
    echo "SKIP (previous check failed)"
    ENV_WARNED=$((ENV_WARNED + 1))
  else
    CONTAINER_STATUS=$(ssh -p 22 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" "pct status $CONTAINER_ID 2>/dev/null" || echo "not_found")
    if echo "$CONTAINER_STATUS" | grep -qE "running|stopped"; then
      echo "PASS (Container $CONTAINER_ID exists)"
      ENV_PASSED=$((ENV_PASSED + 1))
    else
      echo "FAIL"
      echo ""
      echo "ERROR: Container $CONTAINER_ID not found on $ENV_NAME Proxmox host"
      echo "Host: $PROXMOX_HOST"
      echo ""
      echo "Resolution:"
      echo "  1. Verify ZNUNY_CONTAINER_ID is set correctly"
      echo "  2. Check container exists: ssh root@$PROXMOX_HOST 'pct list'"
      ENV_FAILED=$((ENV_FAILED + 1))
    fi
  fi

  # Update global counters
  CHECKS_PASSED=$((CHECKS_PASSED + ENV_PASSED))
  CHECKS_WARNED=$((CHECKS_WARNED + ENV_WARNED))
  CHECKS_FAILED=$((CHECKS_FAILED + ENV_FAILED))

  # Return failure count for this environment
  return $ENV_FAILED
}

# ==============================================================================
# GENERAL CHECKS
# ==============================================================================

echo "--- General Checks ---"
echo ""

# Check 1: SSH private key exists
echo -n "[Check 1/5] SSH private key exists... "
if [ -f ~/.ssh/id_rsa ]; then
  echo "PASS"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
elif [ -f ~/.ssh/id_ed25519 ]; then
  echo "PASS (ed25519)"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo "FAIL"
  echo ""
  echo "ERROR: No SSH private key found"
  echo "Expected: ~/.ssh/id_rsa or ~/.ssh/id_ed25519"
  echo ""
  echo "Resolution:"
  echo "  1. Generate key: ssh-keygen -t rsa -b 4096"
  echo "  2. Or copy existing key to ~/.ssh/"
  exit 1
fi

# Check 2: SSH key permissions
echo -n "[Check 2/5] SSH key permissions... "
KEY_FILE=$(ls ~/.ssh/id_rsa 2>/dev/null || ls ~/.ssh/id_ed25519 2>/dev/null)
KEY_PERMS=$(stat -c %a "$KEY_FILE" 2>/dev/null || stat -f %Lp "$KEY_FILE" 2>/dev/null)
if [ "$KEY_PERMS" = "600" ]; then
  echo "PASS (600)"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo "FAIL"
  echo ""
  echo "ERROR: SSH key permissions are $KEY_PERMS, expected 600"
  echo ""
  echo "Resolution:"
  echo "  chmod 600 $KEY_FILE"
  exit 1
fi

# Check 3: SSH config exists (optional)
echo -n "[Check 3/5] SSH config file... "
if [ -f ~/.ssh/config ]; then
  echo "PASS"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo "WARN (optional)"
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
fi

# Check 4: Environment variables configured
echo -n "[Check 4/5] Environment variables... "
ENV_OK=true

if [ -z "${DEV_ZNUNY_HOST}" ]; then
  ENV_OK=false
fi

if [ "$ENV_OK" = "true" ]; then
  echo "PASS"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  echo "           DEV_ZNUNY_HOST: $DEV_ZNUNY_HOST"
  if [ -n "${REF_ZNUNY_HOST}" ]; then
    echo "           REF_ZNUNY_HOST: $REF_ZNUNY_HOST"
  else
    echo "           REF_ZNUNY_HOST: NOT configured (deploy-ref will skip)"
    CHECKS_WARNED=$((CHECKS_WARNED + 1))
  fi
  if [ -n "${ZNUNY_CONTAINER_ID}" ]; then
    echo "           ZNUNY_CONTAINER_ID: $ZNUNY_CONTAINER_ID"
  else
    echo "           ZNUNY_CONTAINER_ID: NOT configured (snapshots disabled)"
    CHECKS_WARNED=$((CHECKS_WARNED + 1))
  fi
else
  echo "FAIL"
  echo ""
  echo "ERROR: Required environment variables not configured"
  echo ""
  echo "Missing variables:"
  [ -z "${DEV_ZNUNY_HOST}" ] && echo "  - DEV_ZNUNY_HOST"
  echo ""
  echo "Resolution:"
  echo "  1. Go to GoCD UI: Admin -> Environments -> cicd-v2-test-env"
  echo "  2. Add environment variables"
  exit 1
fi

# Check 5: Version format validation
echo -n "[Check 5/5] Version format... "

# Find SOPM file (look in common locations)
SOPM_FILE=""
for path in "MSSTLite.sopm" "znuny-build/MSSTLite.sopm" "../MSSTLite.sopm" "../../MSSTLite.sopm" "$GO_WORKING_DIR/MSSTLite.sopm"; do
  if [ -f "$path" ]; then
    SOPM_FILE="$path"
    break
  fi
done

if [ -z "$SOPM_FILE" ]; then
  echo "SKIP (SOPM not found in build context)"
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
else
  VERSION=$(grep '<Version>' "$SOPM_FILE" | sed 's/.*<Version>\([^<]*\)<\/Version>.*/\1/')

  if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    PATCH=$(echo "$VERSION" | cut -d. -f3)
    if [ "$PATCH" = "0" ]; then
      echo "PASS"
      echo "           Version: $VERSION (RELEASE - will build as-is)"
    else
      echo "PASS"
      echo "           Version: $VERSION (DEV - will auto-version with pipeline counter)"
    fi
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo "FAIL"
    echo ""
    echo "ERROR: Invalid version format '$VERSION'"
    echo ""
    echo "Expected: MAJOR.MINOR.PATCH (e.g., 3.2.0 or 3.2.1)"
    echo ""
    echo "See: docs/VERSIONING.md"
    exit 1
  fi
fi

# ==============================================================================
# ENVIRONMENT-SPECIFIC CHECKS
# ==============================================================================

# DEV Environment (required)
DEV_FAILED=0
check_environment "DEV" "${DEV_ZNUNY_HOST:-}" || DEV_FAILED=$?

# REF Environment (optional)
REF_FAILED=0
if [ -n "${REF_ZNUNY_HOST}" ]; then
  check_environment "REF" "${REF_ZNUNY_HOST}" || REF_FAILED=$?
else
  echo ""
  echo "--- REF Environment Checks ---"
  echo ""
  echo "SKIPPED (REF_ZNUNY_HOST not configured)"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

echo ""
echo "========================================"
echo "       PRE-FLIGHT SUMMARY"
echo "========================================"
echo "Checks passed:  $CHECKS_PASSED"
echo "Warnings:       $CHECKS_WARNED"
echo "Failed:         $CHECKS_FAILED"
echo ""

# Deployment status for each environment
echo "--- Deployment Readiness ---"
echo ""

# DEV status
if [ $DEV_FAILED -gt 0 ]; then
  echo "  DEV:  NOT READY - $DEV_FAILED check(s) failed"
  echo "        Deployment to DEV will be BLOCKED"
else
  echo "  DEV:  READY"
fi

# REF status
if [ -z "${REF_ZNUNY_HOST}" ]; then
  echo "  REF:  SKIPPED - REF_ZNUNY_HOST not configured"
elif [ $REF_FAILED -gt 0 ]; then
  echo "  REF:  NOT READY - $REF_FAILED check(s) failed"
  echo "        WARNING: deploy-ref stage may fail"
else
  echo "  REF:  READY"
fi

echo ""
echo "--- Disclaimer ---"
echo ""
echo "  * DEV checks are REQUIRED - pipeline fails if DEV is not ready"
echo "  * REF checks are OPTIONAL - pipeline continues even if REF fails"
echo "  * Manual deploy stages will only succeed for READY environments"
echo ""

# Exit with error if DEV failed
if [ $DEV_FAILED -gt 0 ]; then
  echo "========================================"
  echo "RESULT: FAILED - DEV environment not ready"
  echo "========================================"
  exit 1
fi

echo "========================================"
echo "RESULT: PASSED - Ready for deployment"
echo "========================================"
