#!/bin/bash
# Pre-flight validation for GoCD deployment pipeline
# Checks SSH keys, permissions, and environment variables

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
echo -n "[Check 1/4] SSH private key exists... "
if [ -f ~/.ssh/id_rsa ]; then
  echo "PASS"
  ((CHECKS_PASSED++))
elif [ -f ~/.ssh/id_ed25519 ]; then
  echo "PASS (ed25519)"
  ((CHECKS_PASSED++))
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
echo -n "[Check 2/4] SSH key permissions... "
KEY_FILE=$(ls ~/.ssh/id_rsa 2>/dev/null || ls ~/.ssh/id_ed25519 2>/dev/null)
KEY_PERMS=$(stat -c %a "$KEY_FILE" 2>/dev/null || stat -f %Lp "$KEY_FILE" 2>/dev/null)
if [ "$KEY_PERMS" = "600" ]; then
  echo "PASS (600)"
  ((CHECKS_PASSED++))
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
echo -n "[Check 3/4] SSH config file... "
if [ -f ~/.ssh/config ]; then
  echo "PASS"
  ((CHECKS_PASSED++))
else
  echo "WARN (optional)"
  ((CHECKS_WARNED++))
fi

# Check 4: Environment variables configured
echo -n "[Check 4/4] Environment variables... "
ENV_OK=true

if [ -z "${DEV_ZNUNY_HOST}" ]; then
  ENV_OK=false
fi

if [ "$ENV_OK" = "true" ]; then
  echo "PASS"
  ((CHECKS_PASSED++))
  echo "           DEV_ZNUNY_HOST: configured"
  if [ -n "${REF_ZNUNY_HOST}" ]; then
    echo "           REF_ZNUNY_HOST: configured"
  else
    echo "           REF_ZNUNY_HOST: NOT configured (deploy-ref will skip)"
    ((CHECKS_WARNED++))
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
