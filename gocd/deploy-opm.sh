#!/bin/bash
# Deploy OPM package to target Znuny server with pre-deployment snapshots
#
# Usage: deploy-opm.sh <HOST_IP> <HOST_NAME> <OPM_SOURCE_DIR> [CONTAINER_ID]
#
# Arguments:
#   HOST_IP        - IP address of the Proxmox host
#   HOST_NAME      - Environment name (DEV, REF, PROD)
#   OPM_SOURCE_DIR - Directory containing the OPM file
#   CONTAINER_ID   - (Optional) Proxmox container ID for snapshots
#
# Example: deploy-opm.sh 10.228.33.221 DEV packages/pkg 104
#
# If CONTAINER_ID is provided, a pre-deployment snapshot is created before
# installing the package. The snapshot is named "pre-MSSTLite-X.Y.Z" where
# X.Y.Z is the version from the OPM filename.

set -e

HOST=$1
HOST_NAME=$2
OPM_SOURCE_DIR=$3
CONTAINER_ID="${4:-}"

# SSH options for consistency
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if [ -z "$HOST" ] || [ -z "$HOST_NAME" ] || [ -z "$OPM_SOURCE_DIR" ]; then
  echo "Usage: $0 <HOST_IP> <HOST_NAME> <OPM_SOURCE_DIR> [CONTAINER_ID]"
  echo "Example: $0 10.228.33.221 DEV packages/pkg 104"
  exit 1
fi

# ==============================================================================
# SNAPSHOT FUNCTIONS
# ==============================================================================

# Extract version from OPM filename (MSSTLite-X.Y.Z.opm -> X.Y.Z)
extract_version_from_opm() {
  local OPM_FILE="$1"
  basename "$OPM_FILE" | sed 's/MSSTLite-\([0-9]*\.[0-9]*\.[0-9]*\)\.opm/\1/'
}

# Create pre-deployment snapshot
# Arguments: HOST, CONTAINER_ID, VERSION
create_pre_deploy_snapshot() {
  local HOST="$1"
  local CONTAINER_ID="$2"
  local VERSION="$3"
  # Replace dots with dashes - Proxmox doesn't allow dots in snapshot names
  local VERSION_SAFE="${VERSION//./-}"
  local SNAPSHOT_NAME="pre-MSSTLite-${VERSION_SAFE}"

  echo ""
  echo "--- Creating Pre-Deployment Snapshot ---"
  echo ""
  echo "Proxmox Host: $HOST"
  echo "Container ID: $CONTAINER_ID"
  echo "Snapshot Name: $SNAPSHOT_NAME"
  echo ""

  # Check if old pre-deploy snapshot exists and delete it
  echo "Checking for existing pre-deploy snapshots..."
  local EXISTING_SNAPSHOTS
  EXISTING_SNAPSHOTS=$(ssh -p 22 $SSH_OPTS root@"$HOST" "pct listsnapshot $CONTAINER_ID 2>/dev/null | grep 'pre-MSSTLite-' | awk '{print \$1}'" || true)

  if [ -n "$EXISTING_SNAPSHOTS" ]; then
    echo "Found existing pre-deploy snapshots:"
    echo "$EXISTING_SNAPSHOTS"
    for OLD_SNAP in $EXISTING_SNAPSHOTS; do
      echo "Deleting old snapshot: $OLD_SNAP"
      if ssh -p 22 $SSH_OPTS root@"$HOST" "pct delsnapshot $CONTAINER_ID $OLD_SNAP" 2>/dev/null; then
        echo "  Deleted: $OLD_SNAP"
      else
        echo "  Warning: Failed to delete $OLD_SNAP (may not exist)"
      fi
    done
  else
    echo "No existing pre-deploy snapshots found"
  fi

  # Create new snapshot
  echo ""
  echo "Creating snapshot: $SNAPSHOT_NAME"
  if ssh -p 22 $SSH_OPTS root@"$HOST" "pct snapshot $CONTAINER_ID $SNAPSHOT_NAME --description 'Pre-deployment snapshot for MSSTLite $VERSION'"; then
    echo "Snapshot created successfully"
  else
    echo ""
    echo "ERROR: Failed to create snapshot"
    echo ""
    echo "Possible causes:"
    echo "  - Insufficient storage space"
    echo "  - Container is in an invalid state"
    echo "  - Permission denied"
    echo ""
    echo "Resolution:"
    echo "  1. Check Proxmox storage: ssh root@$HOST 'pvesm status'"
    echo "  2. Check container status: ssh root@$HOST 'pct status $CONTAINER_ID'"
    return 1
  fi

  # Verify snapshot was created
  echo "Verifying snapshot..."
  if ssh -p 22 $SSH_OPTS root@"$HOST" "pct listsnapshot $CONTAINER_ID | grep -q '$SNAPSHOT_NAME'"; then
    echo "Snapshot verified: $SNAPSHOT_NAME"
    echo ""
    return 0
  else
    echo "ERROR: Snapshot verification failed"
    return 1
  fi
}

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================

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

# Extract version for snapshot naming
VERSION=$(extract_version_from_opm "$OPM_FILE")
# Replace dots with dashes for Proxmox snapshot name (dots not allowed)
VERSION_SAFE="${VERSION//./-}"
echo "Version: $VERSION"
echo ""

# Create pre-deployment snapshot (if container ID provided)
if [ -n "$CONTAINER_ID" ]; then
  if ! create_pre_deploy_snapshot "$HOST" "$CONTAINER_ID" "$VERSION"; then
    echo ""
    echo "========================================"
    echo "       SNAPSHOT CREATION FAILED"
    echo "========================================"
    echo ""
    echo "Deployment aborted. No changes were made to the container."
    exit 1
  fi
else
  echo "--- Skipping Snapshot ---"
  echo "Container ID not provided. Proceeding without snapshot."
  echo "To enable snapshots, set the CONTAINER_ID environment variable"
  echo "or pass it as the 4th argument."
  echo ""
fi

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

# Get the OPM filename for installation
OPM_FILENAME=$(basename "$OPM_FILE")

echo ""
echo "--- Installing OPM Package ---"
echo ""

# Install package using Uninstall + Install approach (consistent with build-package.sh)
# NOTE: otrs.Console.pl refuses to run as root, must use 'su' to switch to otrs/znuny user
ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${HOST} "
  cd /opt/otrs

  # Detect the correct user (otrs or znuny)
  if id -u otrs >/dev/null 2>&1; then
    OTRS_USER=otrs
  elif id -u znuny >/dev/null 2>&1; then
    OTRS_USER=znuny
  else
    echo 'ERROR: Neither otrs nor znuny user found!'
    exit 1
  fi
  echo \"Using user: \$OTRS_USER\"

  # Always uninstall first (ignore errors if not installed)
  echo 'Removing existing package (if any)...'
  su -c 'bin/otrs.Console.pl Admin::Package::Uninstall MSSTLite' -s /bin/bash \$OTRS_USER 2>/dev/null || true
  echo ''

  # Always install fresh
  echo 'Installing package...'
  su -c 'bin/otrs.Console.pl Admin::Package::Install /tmp/${OPM_FILENAME}' -s /bin/bash \$OTRS_USER

  INSTALL_STATUS=\$?
  if [ \$INSTALL_STATUS -ne 0 ]; then
    echo ''
    echo 'ERROR: Package installation failed!'
    exit \$INSTALL_STATUS
  fi

  echo ''
  echo '--- Post-Installation Steps ---'
  echo ''

  echo 'Rebuilding configuration...'
  su -c 'bin/otrs.Console.pl Maint::Config::Rebuild' -s /bin/bash \$OTRS_USER

  echo ''
  echo 'Clearing cache...'
  su -c 'bin/otrs.Console.pl Maint::Cache::Delete' -s /bin/bash \$OTRS_USER

  echo ''
  echo '--- Verifying Installation ---'
  echo ''
  echo 'Installed packages:'
  su -c 'bin/otrs.Console.pl Admin::Package::List' -s /bin/bash \$OTRS_USER | grep -E '(MSSTLite|Name|-----)'
"

DEPLOY_STATUS=$?

if [ $DEPLOY_STATUS -ne 0 ]; then
  echo ""
  echo "========================================"
  echo "       $HOST_NAME DEPLOYMENT FAILED"
  echo "========================================"
  echo ""
  if [ -n "$CONTAINER_ID" ]; then
    echo "A snapshot was created before installation."
    echo ""
    echo "To rollback to pre-deployment state, run:"
    echo ""
    echo "  ssh root@$HOST 'pct rollback $CONTAINER_ID pre-MSSTLite-$VERSION_SAFE'"
    echo ""
    echo "Or with optional container stop (recommended for clean state):"
    echo ""
    echo "  ssh root@$HOST 'pct stop $CONTAINER_ID && pct rollback $CONTAINER_ID pre-MSSTLite-$VERSION_SAFE && pct start $CONTAINER_ID'"
    echo ""
  fi
  exit $DEPLOY_STATUS
fi

echo ""
echo "========================================"
echo "       $HOST_NAME DEPLOYMENT SUCCESSFUL"
echo "========================================"
echo ""
echo "Package installed and configuration rebuilt."
echo "No Apache restart performed - changes active for new requests."

if [ -n "$CONTAINER_ID" ]; then
  echo ""
  echo "--- Rollback Information ---"
  echo "Snapshot: pre-MSSTLite-$VERSION_SAFE"
  echo ""
  echo "If issues occur, rollback with:"
  echo "  ssh root@$HOST 'pct rollback $CONTAINER_ID pre-MSSTLite-$VERSION_SAFE'"
fi
