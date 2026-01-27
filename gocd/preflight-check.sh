#!/bin/bash
# Pre-flight validation for GoCD deployment pipeline
# Checks SSH keys, permissions, environment variables, and Proxmox snapshot capability
#
# Checks performed:
#   1. SSH private key exists
#   2. SSH key permissions (600)
#   3. SSH config file (optional)
#   4. Environment variables (DEV_ZNUNY_HOST required)
#   5. Version format validation
#   6. SSH to Proxmox host (port 22) for snapshots
#   7. pct command available on Proxmox host
#   8. Container ID valid

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

# Check 1: SSH private key exists
echo -n "[Check 1/8] SSH private key exists... "
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
echo -n "[Check 2/8] SSH key permissions... "
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
echo -n "[Check 3/8] SSH config file... "
if [ -f ~/.ssh/config ]; then
  echo "PASS"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo "WARN (optional)"
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
fi

# Check 4: Environment variables configured
echo -n "[Check 4/8] Environment variables... "
ENV_OK=true

if [ -z "${DEV_ZNUNY_HOST}" ]; then
  ENV_OK=false
fi

if [ "$ENV_OK" = "true" ]; then
  echo "PASS"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  echo "           DEV_ZNUNY_HOST: configured"
  if [ -n "${REF_ZNUNY_HOST}" ]; then
    echo "           REF_ZNUNY_HOST: configured"
  else
    echo "           REF_ZNUNY_HOST: NOT configured (deploy-ref will skip)"
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
  echo "  2. Add secure environment variables"
  exit 1
fi

# Check 5: Version format validation
echo -n "[Check 5/8] Version format... "

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

# Check 6: SSH to Proxmox host (port 22) for snapshot capability
echo -n "[Check 6/8] SSH to Proxmox host (port 22)... "
PROXMOX_HOST="${DEV_ZNUNY_HOST:-}"
if [ -z "$PROXMOX_HOST" ]; then
  echo "SKIP (DEV_ZNUNY_HOST not set)"
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
else
  if ssh -p 22 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" "exit" 2>/dev/null; then
    echo "PASS"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo "FAIL"
    echo ""
    echo "ERROR: SSH to Proxmox host port 22 failed"
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
    echo ""
    echo "Note: This is DIFFERENT from the container - snapshot requires host access (port 22)"
    exit 1
  fi
fi

# Check 7: pct command exists on Proxmox host
echo -n "[Check 7/8] pct command on Proxmox host... "
if [ -z "$PROXMOX_HOST" ]; then
  echo "SKIP (DEV_ZNUNY_HOST not set)"
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
else
  if ssh -p 22 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" "which pct" >/dev/null 2>&1; then
    echo "PASS"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo "FAIL"
    echo ""
    echo "ERROR: pct command not found on Proxmox host"
    echo ""
    echo "This indicates the host at $PROXMOX_HOST is not a Proxmox VE installation"
    echo "or the pct tool is not in the PATH."
    exit 1
  fi
fi

# Check 8: Container ID is valid (if provided)
echo -n "[Check 8/8] Container ID valid... "
CONTAINER_ID="${ZNUNY_CONTAINER_ID:-}"
if [ -z "$CONTAINER_ID" ]; then
  echo "SKIP (ZNUNY_CONTAINER_ID not set - snapshots will be disabled)"
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
elif [ -z "$PROXMOX_HOST" ]; then
  echo "SKIP (DEV_ZNUNY_HOST not set)"
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
else
  CONTAINER_STATUS=$(ssh -p 22 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" "pct status $CONTAINER_ID 2>/dev/null" || echo "not_found")
  if echo "$CONTAINER_STATUS" | grep -qE "running|stopped"; then
    echo "PASS (Container $CONTAINER_ID exists)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo "FAIL"
    echo ""
    echo "ERROR: Container $CONTAINER_ID not found on Proxmox host $PROXMOX_HOST"
    echo ""
    echo "Resolution:"
    echo "  1. Verify ZNUNY_CONTAINER_ID is set correctly in GoCD environment"
    echo "  2. Check container exists: ssh root@$PROXMOX_HOST 'pct list'"
    exit 1
  fi
fi

# Summary
echo ""
echo "========================================"
echo "       PRE-FLIGHT SUMMARY"
echo "========================================"
echo "Checks passed:  $CHECKS_PASSED"
echo "Warnings:       $CHECKS_WARNED"
echo ""
echo "All critical checks passed - ready for deployment"
echo "========================================"
