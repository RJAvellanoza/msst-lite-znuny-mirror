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
# Environment Variables:
#   ZNUNY_CONTAINER_IP - (Optional) Container IP address. If not set, will be
#                        queried from the Proxmox host using pct exec.
#
# Example: deploy-opm.sh 10.228.33.221 DEV packages/pkg 104
#
# Connection Method:
#   Uses SSH ProxyJump through the Proxmox host to reach the container.
#   This is more secure than port forwarding as it requires authentication
#   to both the Proxmox host and the container.
#
#   GoCD Agent ---> Proxmox Host (port 22) ---> Container (port 22)
#
# If CONTAINER_ID is provided, a pre-deployment snapshot is created before
# installing the package. The snapshot is named "pre-MSSTLite-X.Y.Z" where
# X.Y.Z is the version from the OPM filename.

set -euo pipefail

HOST="${1:-}"
HOST_NAME="${2:-}"
OPM_SOURCE_DIR="${3:-}"
CONTAINER_ID="${4:-}"

# Container IP can be set via environment variable or will be auto-detected
CONTAINER_IP="${ZNUNY_CONTAINER_IP:-}"

# SSH options for Proxmox host connections (snapshots)
SSH_OPTS_HOST="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# SSH options for container connections (via ProxyJump)
SSH_OPTS_CONTAINER="-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Validate required arguments
if [ -z "$HOST" ] || [ -z "$HOST_NAME" ] || [ -z "$OPM_SOURCE_DIR" ]; then
  echo "Usage: $0 <HOST_IP> <HOST_NAME> <OPM_SOURCE_DIR> [CONTAINER_ID]"
  echo ""
  echo "Arguments:"
  echo "  HOST_IP        - IP address of the Proxmox host"
  echo "  HOST_NAME      - Environment name (DEV, REF, PROD)"
  echo "  OPM_SOURCE_DIR - Directory containing the OPM file"
  echo "  CONTAINER_ID   - (Optional) Proxmox container ID for snapshots"
  echo ""
  echo "Environment Variables:"
  echo "  ZNUNY_CONTAINER_IP - (Optional) Container IP. Auto-detected if not set."
  echo ""
  echo "Example: $0 10.228.33.221 DEV packages/pkg 104"
  exit 1
fi

# ==============================================================================
# CONTAINER IP DETECTION
# ==============================================================================

get_container_ip() {
  local HOST="$1"
  local CONTAINER_ID="$2"

  # Status messages go to stderr so they don't pollute the return value
  echo "Querying container IP from Proxmox host..." >&2
  local IP
  IP=$(ssh -p 22 $SSH_OPTS_HOST root@"$HOST" "pct exec $CONTAINER_ID -- hostname -I | awk '{print \$1}'" 2>/dev/null)

  if [ -z "$IP" ]; then
    echo "ERROR: Could not determine container IP address" >&2
    echo "" >&2
    echo "Possible causes:" >&2
    echo "  - Container is not running" >&2
    echo "  - Container ID is incorrect" >&2
    echo "  - Network not configured in container" >&2
    echo "" >&2
    echo "Resolution:" >&2
    echo "  1. Check container status: ssh root@$HOST 'pct status $CONTAINER_ID'" >&2
    echo "  2. Set ZNUNY_CONTAINER_IP environment variable manually" >&2
    return 1
  fi

  # Only the IP goes to stdout (captured by caller)
  echo "$IP"
}

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
  EXISTING_SNAPSHOTS=$(ssh -p 22 $SSH_OPTS_HOST root@"$HOST" "pct listsnapshot $CONTAINER_ID 2>/dev/null | grep 'pre-MSSTLite-' | awk '{print \$1}'" || true)

  if [ -n "$EXISTING_SNAPSHOTS" ]; then
    echo "Found existing pre-deploy snapshots:"
    echo "$EXISTING_SNAPSHOTS"
    for OLD_SNAP in $EXISTING_SNAPSHOTS; do
      echo "Deleting old snapshot: $OLD_SNAP"
      if ssh -p 22 $SSH_OPTS_HOST root@"$HOST" "pct delsnapshot $CONTAINER_ID $OLD_SNAP" 2>/dev/null; then
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
  if ssh -p 22 $SSH_OPTS_HOST root@"$HOST" "pct snapshot $CONTAINER_ID $SNAPSHOT_NAME --description 'Pre-deployment snapshot for MSSTLite $VERSION'"; then
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
  if ssh -p 22 $SSH_OPTS_HOST root@"$HOST" "pct listsnapshot $CONTAINER_ID | grep -q '$SNAPSHOT_NAME'"; then
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
echo "Connection Method: SSH ProxyJump (secure)"
echo ""

# Determine container IP
if [ -z "$CONTAINER_IP" ]; then
  if [ -z "$CONTAINER_ID" ]; then
    echo "ERROR: Either ZNUNY_CONTAINER_IP or CONTAINER_ID must be provided"
    echo "       Container IP is needed for ProxyJump connection"
    exit 1
  fi
  CONTAINER_IP=$(get_container_ip "$HOST" "$CONTAINER_ID")
fi

echo "Proxmox Host: $HOST"
echo "Container IP: $CONTAINER_IP"
if [ -n "$CONTAINER_ID" ]; then
  echo "Container ID: $CONTAINER_ID"
fi
echo ""

# Build ProxyJump SSH command components
PROXY_JUMP="-o ProxyJump=root@${HOST}"

check_target_host() {
  local HOST=$1
  local HOST_NAME=$2
  local CONTAINER_IP=$3

  echo "--- Target Host Checks: $HOST_NAME ---"
  echo ""

  # Check 1: Proxmox host reachable
  echo -n "[Check 1/5] Proxmox host reachable (port 22)... "
  if timeout 5 bash -c "echo >/dev/tcp/$HOST/22" 2>/dev/null; then
    echo "PASS"
  else
    echo "FAIL"
    echo ""
    echo "ERROR: Cannot reach Proxmox host $HOST:22"
    echo ""
    echo "Possible causes:"
    echo "  - Host is down or unreachable"
    echo "  - Firewall blocking port 22"
    echo ""
    echo "Resolution:"
    echo "  1. Check host is running: ping $HOST"
    return 1
  fi

  # Check 2: SSH to Proxmox host
  echo -n "[Check 2/5] SSH to Proxmox host... "
  if ssh -p 22 $SSH_OPTS_HOST root@"$HOST" "exit" 2>/dev/null; then
    echo "PASS"
  else
    echo "FAIL"
    echo ""
    echo "ERROR: SSH authentication failed to Proxmox host $HOST"
    echo ""
    echo "Resolution:"
    echo "  1. Add public key to /root/.ssh/authorized_keys on Proxmox host"
    return 1
  fi

  # Check 3: ProxyJump to container
  echo -n "[Check 3/5] ProxyJump to container ($CONTAINER_IP)... "
  if ssh $SSH_OPTS_CONTAINER $PROXY_JUMP root@"$CONTAINER_IP" "exit" 2>/dev/null; then
    echo "PASS"
  else
    echo "FAIL"
    echo ""
    echo "ERROR: ProxyJump SSH to container failed"
    echo ""
    echo "Possible causes:"
    echo "  - Public key not in /root/.ssh/authorized_keys inside container"
    echo "  - Container is not running"
    echo "  - Container IP is incorrect"
    echo ""
    echo "Resolution:"
    echo "  1. Add public key to container: ssh root@$HOST 'pct exec $CONTAINER_ID -- mkdir -p /root/.ssh'"
    echo "  2. Verify container is running: ssh root@$HOST 'pct status $CONTAINER_ID'"
    return 1
  fi

  # Check 4: /tmp writable in container
  echo -n "[Check 4/5] /tmp writable in container... "
  if ssh $SSH_OPTS_CONTAINER $PROXY_JUMP root@"$CONTAINER_IP" "touch /tmp/.gocd_deploy_test && rm /tmp/.gocd_deploy_test" 2>/dev/null; then
    echo "PASS"
  else
    echo "FAIL"
    echo ""
    echo "ERROR: Cannot write to /tmp in container"
    return 1
  fi

  # Check 5: Disk space (500MB minimum)
  echo -n "[Check 5/5] Disk space (min 500MB)... "
  AVAIL_KB=$(ssh $SSH_OPTS_CONTAINER $PROXY_JUMP root@"$CONTAINER_IP" "df /tmp | tail -1 | awk '{print \$4}'" 2>/dev/null)
  AVAIL_MB=$((AVAIL_KB / 1024))
  if [ "$AVAIL_MB" -ge 500 ]; then
    echo "PASS (${AVAIL_MB}MB available)"
  else
    echo "FAIL"
    echo ""
    echo "ERROR: Only ${AVAIL_MB}MB available on /tmp, need 500MB"
    echo ""
    echo "Resolution:"
    echo "  1. Clean up /tmp in container"
    echo "  2. Or expand disk"
    return 1
  fi

  # Cleanup old OPM files
  echo -n "Cleanup old deployments... "
  ssh $SSH_OPTS_CONTAINER $PROXY_JUMP root@"$CONTAINER_IP" "rm -f /tmp/MSSTLite-*.opm" 2>/dev/null || true
  echo "DONE"

  echo ""
  echo "--- All target checks passed ---"
  echo ""
  return 0
}

# Run target host checks
check_target_host "$HOST" "$HOST_NAME" "$CONTAINER_IP"

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
  echo "To enable snapshots, set the ZNUNY_CONTAINER_ID environment variable"
  echo "or pass it as the 4th argument."
  echo ""
fi

# Deploy the OPM file
echo "--- Deploying OPM Package ---"
echo ""
echo "Copying $OPM_FILE to container:/tmp/ (via ProxyJump)"
scp $SSH_OPTS_CONTAINER $PROXY_JUMP "$OPM_FILE" root@"${CONTAINER_IP}":/tmp/

# Verify deployment
echo ""
echo "--- Verification ---"
ssh $SSH_OPTS_CONTAINER $PROXY_JUMP root@"${CONTAINER_IP}" "
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

# Install package using Uninstall + Install approach (ensures version updates in DB)
# NOTE: otrs.Console.pl refuses to run as root, must use 'su' to switch to otrs/znuny user
ssh $SSH_OPTS_CONTAINER $PROXY_JUMP root@"${CONTAINER_IP}" "
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

  # Check if package is already installed
  echo 'Checking current package status...'
  INSTALLED_VERSION=\$(su -c 'bin/otrs.Console.pl Admin::Package::List' -s /bin/bash \$OTRS_USER 2>/dev/null | grep 'MSSTLite' | awk '{print \$2}' || true)

  if [ -n \"\$INSTALLED_VERSION\" ]; then
    echo \"Currently installed: MSSTLite \$INSTALLED_VERSION\"
    echo ''
    echo 'Uninstalling existing package...'

    # Try normal uninstall first
    if su -c 'bin/otrs.Console.pl Admin::Package::Uninstall MSSTLite' -s /bin/bash \$OTRS_USER 2>&1; then
      echo 'Uninstall successful'
    else
      echo ''
      echo 'WARNING: Normal uninstall failed (package file missing from repository)'
      echo 'Removing package entry directly from database...'

      # Get database credentials from Kernel/Config.pm
      DB_HOST=\$(grep -oP \"DatabaseHost\\s*=>\\s*'\\K[^']+\" Kernel/Config.pm || echo 'localhost')
      DB_NAME=\$(grep -oP \"DatabaseName\\s*=>\\s*'\\K[^']+\" Kernel/Config.pm || echo 'otrs')
      DB_USER=\$(grep -oP \"DatabaseUser\\s*=>\\s*'\\K[^']+\" Kernel/Config.pm || echo 'otrs')
      DB_PASS=\$(grep -oP \"DatabasePw\\s*=>\\s*'\\K[^']+\" Kernel/Config.pm || echo '')

      echo \"Database: \$DB_NAME@\$DB_HOST (user: \$DB_USER)\"

      # Remove from package_repository table (connect to external DB host)
      if PGPASSWORD=\"\$DB_PASS\" psql -h \"\$DB_HOST\" -U \"\$DB_USER\" -d \"\$DB_NAME\" -c \"DELETE FROM package_repository WHERE name = 'MSSTLite';\" 2>&1; then
        echo 'Package entry removed from database'
      else
        echo 'WARNING: Could not remove from database, continuing anyway...'
      fi
    fi
    echo ''
  else
    echo 'No existing MSSTLite package found'
    echo ''
  fi

  # Install the package
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
