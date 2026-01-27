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

**Checks performed:**

| Check | Required | Description |
|-------|----------|-------------|
| 1. SSH key exists | Yes | `~/.ssh/id_rsa` or `~/.ssh/id_ed25519` |
| 2. SSH key permissions | Yes | Must be 600 |
| 3. SSH config exists | No | Warning only if missing |
| 4. Environment variables | Yes | `DEV_ZNUNY_HOST` must be set |
| 5. Version format | Yes | Must be X.Y.Z format |
| 6. SSH to Proxmox host | Yes | Port 22 connectivity for snapshots |
| 7. pct command available | Yes | Proxmox container tool exists |
| 8. Container ID valid | Yes | Container exists on Proxmox host |

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

**Target host checks:**

| Check | Description |
|-------|-------------|
| Port 2222 reachable | TCP connectivity test (5s timeout) |
| SSH public key auth | BatchMode SSH connection test |
| /tmp writable | Touch test file |
| Disk space | Minimum 500MB available |
| Cleanup | Removes old MSSTLite-*.opm files |

**Deployment flow:**

| Step | Description |
|------|-------------|
| 1. Pre-deploy snapshot | Creates `pre-MSSTLite-X.Y.Z` snapshot (if CONTAINER_ID provided) |
| 2. Copy OPM | SCP package to container's /tmp |
| 3. User detection | Auto-detects `otrs` or `znuny` user |
| 4. Uninstall | Removes existing MSSTLite package (if any) |
| 5. Install | Fresh install of new OPM package |
| 6. Post-install | Rebuilds config and clears cache |

**Note:** Uses `Uninstall + Install` instead of `Reinstall` because `Reinstall` only refreshes files without updating the version in the database.

## Network Architecture

```
GoCD Agent (10.228.33.225, Container 201)
    |
    +-- SSH port 22 --> Proxmox Host --> pct snapshot <CONTAINER_ID>
    |                   (for snapshots)
    |
    +-- SSH port 2222 --> Proxmox Host --> iptables DNAT --> Container:22
                          (for deployment)
```

## Troubleshooting

### SSH to Proxmox Host Failed (Port 22)

**Symptoms:** Preflight fails at "SSH to Proxmox host (port 22)" check

**Common causes:**
1. GoCD agent's public key not added to Proxmox host's `/root/.ssh/authorized_keys`
2. `PubkeyAuthentication` not enabled in Proxmox host's `/etc/ssh/sshd_config`
3. Firewall blocking port 22

**Resolution:**
```bash
# Verify key is on Proxmox host (not in container)
ssh root@<PROXMOX_HOST> "cat /root/.ssh/authorized_keys"

# Check sshd_config on Proxmox host
ssh root@<PROXMOX_HOST> "grep PubkeyAuthentication /etc/ssh/sshd_config"
```

### SSH to Container Failed (Port 2222)

**Symptoms:** Deploy stage fails at "SSH public key auth" check

**Common causes:**
1. Public key added to Proxmox host instead of container
2. `PubkeyAuthentication` not enabled in container's sshd_config
3. Wrong permissions on `.ssh/` or `authorized_keys`

**Resolution:**
```bash
# Verify key is inside the container
ssh root@<PROXMOX_HOST> "pct exec <CONTAINER_ID> -- cat /root/.ssh/authorized_keys"

# Check sshd_config inside container
ssh root@<PROXMOX_HOST> "pct exec <CONTAINER_ID> -- grep PubkeyAuthentication /etc/ssh/sshd_config"
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

### Port 2222 Not Reachable

**Symptoms:** Deploy stage fails at "Port 2222 reachable" check

**Common causes:**
1. Proxmox host is down
2. Port forwarding not configured
3. Firewall blocking the port

**Resolution:**
```bash
# Check port forwarding on Proxmox host
ssh root@<PROXMOX_HOST> "iptables -t nat -L PREROUTING -n | grep 2222"
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

## Related Documentation

- [Versioning Guide](../docs/VERSIONING.md) - Complete versioning documentation with flow diagrams
