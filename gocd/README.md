# GoCD Pipeline Configuration

This directory contains the GoCD pipeline definition and deployment scripts for MSSTLite OPM package automation.

## Contents

| File | Purpose |
|------|---------|
| `build-application-v2-test.gocd.yaml` | Pipeline definition (YAML as Code) |
| `preflight-check.sh` | Pre-deployment validation script |
| `deploy-opm.sh` | OPM deployment script with snapshots |
| `README.md` | This documentation |

## Pipeline Structure

```
git push --> build (auto) --> preflight (auto) --> deploy-dev (manual) --> deploy-ref (manual)
```

| Stage | Trigger | Description |
|-------|---------|-------------|
| `build` | Auto (on git push) | Builds OPM package using `gocd-build-application.sh` |
| `preflight` | Auto (on build success) | Validates SSH keys, permissions, environment variables, Proxmox connectivity |
| `deploy-dev` | Manual | Creates snapshot, deploys OPM to DEV server |
| `deploy-ref` | Manual | Creates snapshot, deploys OPM to REF server |

## Snapshot Feature

The pipeline automatically creates Proxmox container snapshots before deploying packages, enabling safe rollback if deployment fails.

### How It Works

1. Before installing the OPM package, the pipeline creates a snapshot named `pre-MSSTLite-X.Y.Z`
2. If deployment fails, rollback instructions are displayed
3. Old pre-deploy snapshots are automatically deleted before creating new ones
4. Only one pre-deploy snapshot is kept per environment

### Snapshot Naming

Dots are replaced with dashes (Proxmox doesn't allow dots in snapshot names):

| Deploying Package | Snapshot Name |
|-------------------|---------------|
| MSSTLite-2.1.14.opm | `pre-MSSTLite-2-1-14` |
| MSSTLite-3.0.0.opm | `pre-MSSTLite-3-0-0` |

### Rollback Procedure

If deployment fails or issues are discovered after deployment:

```bash
# Quick rollback (may cause brief service interruption)
ssh root@<PROXMOX_HOST> 'pct rollback <CONTAINER_ID> pre-MSSTLite-X.Y.Z'

# Clean rollback (recommended)
ssh root@<PROXMOX_HOST> 'pct stop <CONTAINER_ID> && pct rollback <CONTAINER_ID> pre-MSSTLite-X.Y.Z && pct start <CONTAINER_ID>'
```

Example for DEV:
```bash
ssh root@10.228.33.221 'pct rollback 104 pre-MSSTLite-2-1-14'
```

## Versioning

The pipeline automatically handles version numbers based on the SOPM file:

| SOPM Version | Pipeline Counter | Built Package | Type |
|--------------|------------------|---------------|------|
| `3.2.0` | 45 | MSSTLite-3.2.0.opm | Release |
| `3.2.1` | 46 | MSSTLite-3.2.46.opm | Dev build |

**Rules:**
- **PATCH = 0** --> Builds exact version (for releases)
- **PATCH > 0** --> Replaces PATCH with pipeline counter (for dev builds)

**Full documentation:** See [docs/VERSIONING.md](../docs/VERSIONING.md)

### Quick Reference

| I want to... | Set SOPM version to |
|--------------|---------------------|
| Release 3.2.0 | `<Version>3.2.0</Version>` |
| Resume dev builds | `<Version>3.2.1</Version>` |

## Prerequisites

### GoCD Agent Requirements

- SSH private key at `~/.ssh/id_rsa` (permissions: 600)
- Network access to target Proxmox hosts on port 22 (for snapshots)
- Network access to target containers on port 2222 (for deployment)

### Environment Variables

Configure these as **secure variables** in GoCD UI:

| Variable | Required | Description |
|----------|----------|-------------|
| `DEV_ZNUNY_HOST` | Yes | IP address of DEV Proxmox host |
| `REF_ZNUNY_HOST` | No | IP address of REF Proxmox host |
| `ZNUNY_CONTAINER_ID` | Yes | Container ID for Znuny (e.g., 104) - same for all environments |

**Path:** Admin --> Environments --> `cicd-v2-test-env` --> Environment Variables (Secure)

### Target Host Requirements

Each target requires SSH access to **both** the Proxmox host and the container:

| Connection | Port | Purpose | Key Location |
|------------|------|---------|--------------|
| Proxmox host | 22 | Create snapshots | Host's `/root/.ssh/authorized_keys` |
| Container | 2222 | Deploy OPM | Container's `/root/.ssh/authorized_keys` |

## Setup Instructions

### 1. Configure GoCD Config Repository

In GoCD UI: Admin --> Config Repositories --> Add

| Field | Value |
|-------|-------|
| Plugin | YAML Configuration Plugin |
| Material URL | `ssh://git@bitbucket.mot-solutions.com:7999/msstlite/msst-lite-znuny.git` |
| Branch | `feature/CICD_TEST_RJ` |
| YAML Pattern | `gocd/*.gocd.yaml` |

### 2. Configure Environment Variables

1. Go to Admin --> Environments --> `cicd-v2-test-env`
2. Add secure environment variables:
   - `DEV_ZNUNY_HOST` = `10.228.33.221`
   - `REF_ZNUNY_HOST` = (your REF host IP)
   - `ZNUNY_CONTAINER_ID` = `104` (same for all environments)

### 3. SSH Setup for Proxmox Host (Port 22)

The GoCD agent needs SSH access to the Proxmox host to create snapshots.

**On the Proxmox host (not inside the container):**

```bash
# Step 1: Create .ssh directory
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Step 2: Add GoCD agent's public key
echo '<GOCD_AGENT_PUBLIC_KEY>' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Step 3: Verify sshd_config (if SSH fails)
grep -E "^#?PubkeyAuthentication|^#?AuthorizedKeysFile" /etc/ssh/sshd_config

# If commented out, edit /etc/ssh/sshd_config and uncomment:
#   PubkeyAuthentication yes
#   AuthorizedKeysFile .ssh/authorized_keys

# Step 4: Restart sshd (only if config changed)
systemctl restart sshd

# Step 5: Verify pct command exists
which pct

# Step 6: Test snapshot capability
pct listsnapshot <CONTAINER_ID>
```

**Required permissions:**

| Path | Numeric | Symbolic | Why |
|------|---------|----------|-----|
| `/root/.ssh/` | `700` | `drwx------` | Only owner can access directory |
| `/root/.ssh/authorized_keys` | `600` | `-rw-------` | SSH refuses if group/others have access |

**Verify with:**

```bash
ls -la /root/.ssh/
# Expected:
# drwx------  2 root root 4096 Jan 27 10:00 .
# -rw-------  1 root root  742 Jan 27 10:00 authorized_keys
```

### 4. SSH Setup for Container (Port 2222)

The GoCD agent needs SSH access to the container to deploy OPM packages.

**Inside the container:**

```bash
# Access the container
pct exec <CONTAINER_ID> -- bash

# Add public key
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo '<GOCD_AGENT_PUBLIC_KEY>' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Enable public key authentication (if needed)
grep -E "^#?PubkeyAuthentication" /etc/ssh/sshd_config
# If commented, edit and uncomment: PubkeyAuthentication yes
systemctl restart sshd

# Exit container
exit
```

**Required permissions (inside container):**

| Path | Numeric | Symbolic | Why |
|------|---------|----------|-----|
| `/root/.ssh/` | `700` | `drwx------` | Only owner can access directory |
| `/root/.ssh/authorized_keys` | `600` | `-rw-------` | SSH refuses if group/others have access |

**Verify with:**

```bash
ls -la /root/.ssh/
# Expected:
# drwx------  2 root root 4096 Jan 27 10:00 .
# -rw-------  1 root root  742 Jan 27 10:00 authorized_keys
```

**Permission breakdown:**

```
drwx------  (700 for directories)
│││└┴┴┴┴┴┴── others/group: no permissions (------)
│└┴──────── owner: read, write, execute (rwx)
└─────────── d = directory

-rw-------  (600 for files)
│││└┴┴┴┴┴┴── others/group: no permissions (------)
│└┴──────── owner: read, write (rw-)
└─────────── - = regular file
```

### 5. Test SSH Connections

From the GoCD agent:

```bash
# Test SSH to Proxmox host (port 22) - for snapshots
ssh -p 22 -o StrictHostKeyChecking=no root@<PROXMOX_HOST> "hostname && pct list"

# Test SSH to container (port 2222) - for deployment
ssh -p 2222 -o StrictHostKeyChecking=no root@<PROXMOX_HOST> "hostname"
```

## Scripts Reference

### preflight-check.sh

Validates deployment prerequisites before any deployment stage runs.

**General Checks (1-5):**

| Check | Required | Description |
|-------|----------|-------------|
| 1. SSH key exists | Yes | `~/.ssh/id_rsa` or `~/.ssh/id_ed25519` |
| 2. SSH key permissions | Yes | Must be 600 |
| 3. SSH config exists | No | Warning only if missing |
| 4. Environment variables | Yes | `DEV_ZNUNY_HOST` must be set |
| 5. Version format | Yes | Must be X.Y.Z format |

**Environment Checks (per environment):**

| Check | Required | Description |
|-------|----------|-------------|
| 1. SSH to Proxmox host | Yes | Port 22 connectivity for snapshots |
| 2. pct command available | Yes | Proxmox container tool exists |
| 3. Container ID valid | Yes | Container exists on Proxmox host |

**Deployment Readiness:**

The preflight summary shows deployment status for each environment:

| Status | Meaning |
|--------|---------|
| `READY` | All checks passed, deployment will succeed |
| `NOT READY` | One or more checks failed |
| `SKIPPED` | Environment not configured (e.g., REF_ZNUNY_HOST not set) |

**Important:**
- DEV checks are **required** - pipeline fails if DEV is not ready
- REF checks are **optional** - pipeline continues even if REF fails
- Manual deploy stages will only succeed for READY environments

### deploy-opm.sh

Deploys OPM package to a target Znuny server with pre-deployment snapshots.

**Usage:**
```bash
./deploy-opm.sh <HOST_IP> <HOST_NAME> <OPM_SOURCE_DIR> [CONTAINER_ID]
```

**Example:**
```bash
./deploy-opm.sh 10.228.33.221 DEV packages/pkg 104
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `HOST_IP` | Yes | IP address of the Proxmox host |
| `HOST_NAME` | Yes | Environment name (DEV, REF) |
| `OPM_SOURCE_DIR` | Yes | Directory containing the OPM file |
| `CONTAINER_ID` | No | Proxmox container ID for snapshots |

**Environment Variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `ZNUNY_CONTAINER_IP` | No | Container IP (auto-detected if not set) |

**Target host checks:**

| Check | Description |
|-------|-------------|
| Proxmox host reachable | Port 22 connectivity test |
| SSH to Proxmox host | BatchMode SSH connection test |
| ProxyJump to container | SSH via Proxmox to container |
| /tmp writable | Touch test file in container |
| Disk space | Minimum 500MB available |

**Deployment flow:**

| Step | Description |
|------|-------------|
| 1. Pre-deploy snapshot | Creates `pre-MSSTLite-X.Y.Z` snapshot (if CONTAINER_ID provided) |
| 2. Copy OPM | SCP via ProxyJump to container's /tmp |
| 3. User detection | Auto-detects `otrs` or `znuny` user |
| 4. Uninstall | Removes existing MSSTLite package (if any) |
| 5. Install | Fresh install of new OPM package |
| 6. Post-install | Rebuilds config and clears cache |

**Note:** Uses `Uninstall + Install` instead of `Reinstall` because `Reinstall` only refreshes files without updating the version in the database.

### Snapshot Limitation: Database on Separate Container

**Important:** Container snapshots do NOT include the PostgreSQL database if it runs on a separate container.

```
┌─────────────────────────────┐     ┌─────────────────────────────┐
│   Znuny Container (104)     │     │   PostgreSQL Container      │
├─────────────────────────────┤     ├─────────────────────────────┤
│ /opt/otrs/var/packages/     │     │ package_repository table    │
│   ✅ Affected by snapshot   │     │   ❌ NOT affected           │
└─────────────────────────────┘     └─────────────────────────────┘
```

After a container rollback, a mismatch can occur:
- **Filesystem:** Reverted (package files gone/restored)
- **Database:** Unchanged (still thinks package is installed)

**How the script handles this:**

1. Try normal uninstall via `Admin::Package::Uninstall`
2. If uninstall fails with "File not found in local repository":
   - Extract DB credentials from `Kernel/Config.pm`
   - Delete package entry directly: `DELETE FROM package_repository WHERE name = 'MSSTLite'`
3. Proceed with fresh install

**Why this is safe for MSSTLite:**
- `CodeUninstall` is empty (intentionally does nothing)
- `CodeInstall` is idempotent (checks before creating entities)
- No custom tables are created (uses existing Znuny tables)

## Network Architecture

```
GoCD Agent (10.228.33.225, Container 201)
    |
    +-- SSH port 22 --> Proxmox Host --> pct snapshot <CONTAINER_ID>
    |                   (for snapshots)
    |
    +-- SSH ProxyJump --> Proxmox Host (port 22) --> Container (port 22)
                          (for deployment - more secure than port forwarding)
```

### Connection Method: SSH ProxyJump

The pipeline uses SSH ProxyJump for secure container access:

```
GoCD Agent ---> Proxmox Host (port 22) ---> Container (port 22)
```

**Why ProxyJump instead of port forwarding:**

| Aspect | Port Forwarding (2222) | ProxyJump |
|--------|------------------------|-----------|
| Exposed ports | Port 2222 open to network | No additional ports |
| Authentication layers | 1 (container only) | 2 (Proxmox + container) |
| Security | Single barrier | Defense in depth |

**Requirements:**
- GoCD agent's public key must be in **both**:
  1. Proxmox host's `/root/.ssh/authorized_keys`
  2. Container's `/root/.ssh/authorized_keys`

## Troubleshooting

### SSH to Proxmox Host Failed (Port 22)

**Symptoms:** Preflight fails at "SSH to Proxmox host (port 22)" check

**Common causes:**
1. GoCD agent's public key not added to Proxmox host's `/root/.ssh/authorized_keys`
2. `PubkeyAuthentication` not enabled in Proxmox host's `/etc/ssh/sshd_config`
3. Firewall blocking port 22

**Resolution:**
```bash
# Verify key is on Proxmox host
ssh root@<PROXMOX_HOST> "cat /root/.ssh/authorized_keys"

# Check sshd_config on Proxmox host
ssh root@<PROXMOX_HOST> "grep PubkeyAuthentication /etc/ssh/sshd_config"
```

### ProxyJump to Container Failed

**Symptoms:** Preflight fails at "ProxyJump to container" check

**Common causes:**
1. Public key not in container's `/root/.ssh/authorized_keys`
2. `PubkeyAuthentication` not enabled in container's sshd_config
3. Wrong permissions on `.ssh/` (`700`/`drwx------`) or `authorized_keys` (`600`/`-rw-------`)
4. Container's sshd not running

**Resolution:**
```bash
# Verify key is inside the container
ssh root@<PROXMOX_HOST> "pct exec <CONTAINER_ID> -- cat /root/.ssh/authorized_keys"

# Check permissions inside container
ssh root@<PROXMOX_HOST> "pct exec <CONTAINER_ID> -- ls -la /root/.ssh/"

# Check sshd_config inside container
ssh root@<PROXMOX_HOST> "pct exec <CONTAINER_ID> -- grep PubkeyAuthentication /etc/ssh/sshd_config"

# Restart sshd in container if needed
ssh root@<PROXMOX_HOST> "pct exec <CONTAINER_ID> -- systemctl restart sshd"
```

### known_hosts Conflict (REMOTE HOST IDENTIFICATION HAS CHANGED)

**Symptoms:**
```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Host key for 172.16.18.22 has changed...
```

**Cause:** DEV and REF containers have the same IP (172.16.18.22) but different host keys.

**Resolution:**
```bash
# Remove conflicting entry
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "172.16.18.22"
```

**Note:** Deploy scripts use `-o UserKnownHostsFile=/dev/null` to prevent this issue.

### No Route to Host (Direct Container Access)

**Symptoms:** `ssh: connect to host 172.16.18.22 port 22: No route to host`

**Cause:** Container IP is not routable from GoCD agent.

**Resolution:** Use ProxyJump (already configured in scripts):
```bash
# Correct
ssh -o ProxyJump=root@<PROXMOX_HOST> root@172.16.18.22 "hostname"
```

### Snapshot Creation Failed

**Symptoms:** Deploy fails at "Creating Pre-Deployment Snapshot"

**Common causes:**
1. Insufficient storage space on Proxmox
2. Container is in an invalid state
3. Permission denied on Proxmox host

**Resolution:**
```bash
# Check Proxmox storage
ssh root@<PROXMOX_HOST> "pvesm status"

# Check container status
ssh root@<PROXMOX_HOST> "pct status <CONTAINER_ID>"

# Try manual snapshot
ssh root@<PROXMOX_HOST> "pct snapshot <CONTAINER_ID> test-snapshot"
```

### Environment Variable Not Configured

**Symptoms:** Preflight stage fails at "Environment variables" check

**Resolution:**
1. Go to GoCD UI: Admin --> Environments --> `cicd-v2-test-env`
2. Add the missing variable as a secure environment variable

### Container ID Not Found

**Symptoms:** Preflight fails at "Container ID valid" check

**Resolution:**
```bash
# List all containers on Proxmox host
ssh root@<PROXMOX_HOST> "pct list"

# Verify ZNUNY_CONTAINER_ID matches an existing container
```

### Container IP Auto-Detection Failed

**Symptoms:** Deploy fails with "Could not determine container IP address"

**Common causes:**
1. Container is not running
2. Network not configured in container

**Resolution:**
```bash
# Check container status
ssh root@<PROXMOX_HOST> "pct status <CONTAINER_ID>"

# Start container if stopped
ssh root@<PROXMOX_HOST> "pct start <CONTAINER_ID>"

# Or set ZNUNY_CONTAINER_IP manually in GoCD environment variables
```

### Package Already Installed After Rollback

**Symptoms:**
```
Error: File 'MSSTLite' not found in local repository or invalid package version.
...
Error: Package is already installed.
```

**Root Cause:**

After rolling back the Znuny container snapshot, the database (on a separate PostgreSQL container) still thinks the package is installed, but the package files are gone from the filesystem.

| Component | After Rollback |
|-----------|----------------|
| `/opt/otrs/var/packages/MSSTLite-*.opm` | Missing (rolled back) |
| `package_repository` table | Still has MSSTLite entry |

**Resolution:**

The deploy script handles this automatically by:
1. Detecting the uninstall failure
2. Removing the package entry directly from the database
3. Proceeding with fresh install

If you need to fix this manually:

```bash
# Connect to PostgreSQL container and run:
psql -U otrs -d otrs -c "DELETE FROM package_repository WHERE name = 'MSSTLite';"
```

**Prevention:**

This is expected behavior when:
- PostgreSQL runs on a separate container
- Only the Znuny container is snapshot/rolled back

For true rollback capability, you would need to snapshot both containers or use `pg_dump` before deployment.

## Related Documentation

- [Versioning Guide](../docs/VERSIONING.md) - Complete versioning documentation with flow diagrams
