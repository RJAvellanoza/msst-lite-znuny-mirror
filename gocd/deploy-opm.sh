#!/bin/bash
# Deploy OPM package to target Znuny server
# Usage: deploy-opm.sh <HOST_IP> <HOST_NAME> <OPM_SOURCE_DIR>
#
# Example: deploy-opm.sh 10.228.33.221 DEV packages/pkg

set -e

HOST=$1
HOST_NAME=$2
OPM_SOURCE_DIR=$3

if [ -z "$HOST" ] || [ -z "$HOST_NAME" ] || [ -z "$OPM_SOURCE_DIR" ]; then
  echo "Usage: $0 <HOST_IP> <HOST_NAME> <OPM_SOURCE_DIR>"
  echo "Example: $0 10.228.33.221 DEV packages/pkg"
  exit 1
fi

echo "========================================"
echo "       DEPLOY TO $HOST_NAME SERVER"
echo "========================================"
echo ""

check_target_host() {
  local HOST=$1
  local HOST_NAME=$2

  echo "--- Target Host Checks: $HOST_NAME ---"
  echo ""

  # Check 1: Port reachable
  echo -n "[Check 1/5] Port 2222 reachable... "
  if timeout 5 bash -c "echo >/dev/tcp/$HOST/2222" 2>/dev/null; then
    echo "PASS"
  else
    echo "FAIL"
    echo ""
    echo "ERROR: Cannot reach $HOST:2222"
    echo ""
    echo "Possible causes:"
    echo "  - Host is down or unreachable"
    echo "  - Firewall blocking port 2222"
    echo "  - Port forwarding not configured on Proxmox"
    echo ""
    echo "Resolution:"
    echo "  1. Check host is running: ping $HOST"
    echo "  2. Check port forwarding: ssh root@\$HOST 'iptables -t nat -L PREROUTING -n | grep 2222'"
    return 1
  fi

  # Check 2: SSH authentication
  echo -n "[Check 2/5] SSH public key auth... "
  if ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$HOST "exit" 2>/dev/null; then
    echo "PASS"
  else
    echo "FAIL"
    echo ""
    echo "ERROR: SSH public key authentication failed to $HOST"
    echo ""
    echo "Possible causes:"
    echo "  - Public key not in /root/.ssh/authorized_keys on target"
    echo "  - Key added to Proxmox host instead of container"
    echo "  - PubkeyAuthentication not enabled in sshd_config"
    echo ""
    echo "Resolution:"
    echo "  1. Add this key to /root/.ssh/authorized_keys INSIDE the container:"
    cat ~/.ssh/id_rsa.pub 2>/dev/null || cat ~/.ssh/id_ed25519.pub 2>/dev/null
    echo ""
    echo "  2. Ensure PubkeyAuthentication yes in /etc/ssh/sshd_config"
    echo "  3. Restart sshd: systemctl restart sshd"
    return 1
  fi

  # Check 3: /tmp writable
  echo -n "[Check 3/5] /tmp writable... "
  if ssh -p 2222 -o StrictHostKeyChecking=no root@$HOST "touch /tmp/.gocd_deploy_test && rm /tmp/.gocd_deploy_test" 2>/dev/null; then
    echo "PASS"
  else
    echo "FAIL"
    echo ""
    echo "ERROR: Cannot write to /tmp on $HOST"
    return 1
  fi

  # Check 4: Disk space (500MB minimum)
  echo -n "[Check 4/5] Disk space (min 500MB)... "
  AVAIL_KB=$(ssh -p 2222 -o StrictHostKeyChecking=no root@$HOST "df /tmp | tail -1 | awk '{print \$4}'" 2>/dev/null)
  AVAIL_MB=$((AVAIL_KB / 1024))
  if [ "$AVAIL_MB" -ge 500 ]; then
    echo "PASS (${AVAIL_MB}MB available)"
  else
    echo "FAIL"
    echo ""
    echo "ERROR: Only ${AVAIL_MB}MB available on /tmp, need 500MB"
    echo ""
    echo "Resolution:"
    echo "  1. Clean up /tmp: ssh -p 2222 root@\$HOST 'rm -rf /tmp/*'"
    echo "  2. Or expand disk"
    return 1
  fi

  # Check 5: Cleanup old OPM files
  echo -n "[Check 5/5] Cleanup old deployments... "
  ssh -p 2222 -o StrictHostKeyChecking=no root@$HOST "rm -f /tmp/MSSTLite-*.opm" 2>/dev/null
  echo "DONE"

  echo ""
  echo "--- All target checks passed ---"
  echo ""
  return 0
}

# Run target host checks
check_target_host "$HOST" "$HOST_NAME"

# Find the OPM file
echo "--- Locating OPM Package ---"
echo ""
OPM_FILE=$(ls ${OPM_SOURCE_DIR}/MSSTLite-*.opm 2>/dev/null | head -1)
if [ -z "$OPM_FILE" ]; then
  echo "ERROR: No MSSTLite OPM file found in ${OPM_SOURCE_DIR}/"
  echo ""
  echo "Contents of ${OPM_SOURCE_DIR}/:"
  ls -la ${OPM_SOURCE_DIR}/ 2>/dev/null || echo "  (directory not found)"
  exit 1
fi
echo "Found: $OPM_FILE"
echo "Size:  $(du -h "$OPM_FILE" | cut -f1)"
echo ""

# Deploy the OPM file
echo "--- Deploying OPM Package ---"
echo ""
echo "Copying $OPM_FILE to $HOST:/tmp/"
scp -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OPM_FILE" root@${HOST}:/tmp/

# Verify deployment
echo ""
echo "--- Verification ---"
ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${HOST} "
  echo ''
  echo 'OPM file on $HOST_NAME server:'
  ls -la /tmp/MSSTLite-*.opm
  echo ''
  echo 'MD5 checksum:'
  md5sum /tmp/MSSTLite-*.opm
"

echo ""
echo "========================================"
echo "       $HOST_NAME DEPLOYMENT SUCCESSFUL"
echo "========================================"
