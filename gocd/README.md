# GoCD Pipeline Configuration

This directory contains the GoCD pipeline definition and deployment scripts for MSSTLite OPM package automation.

## Contents

| File | Purpose |
|------|---------|
| `build-application-v2-test.gocd.yaml` | Pipeline definition (YAML as Code) |
| `preflight-check.sh` | Pre-deployment validation script |
| `deploy-opm.sh` | OPM deployment script with target host checks |
| `README.md` | This documentation |

## Pipeline Structure

```
git push → build (auto) → preflight (auto) → deploy-dev (manual) → deploy-ref (manual)
```

| Stage | Trigger | Description |
|-------|---------|-------------|
| `build` | Auto (on git push) | Builds OPM package using `gocd-build-application.sh` |
| `preflight` | Auto (on build success) | Validates SSH keys, permissions, environment variables |
| `deploy-dev` | Manual | Deploys OPM to DEV server |
| `deploy-ref` | Manual | Deploys OPM to REF server |

## Versioning

The pipeline automatically handles version numbers based on the SOPM file:

| SOPM Version | Pipeline Counter | Built Package | Type |
|--------------|------------------|---------------|------|
| `3.2.0` | 45 | MSSTLite-3.2.0.opm | Release |
| `3.2.1` | 46 | MSSTLite-3.2.46.opm | Dev build |

**Rules:**
- **PATCH = 0** → Builds exact version (for releases)
- **PATCH > 0** → Replaces PATCH with pipeline counter (for dev builds)

**Full documentation:** See [docs/VERSIONING.md](../docs/VERSIONING.md)

### Quick Reference

| I want to... | Set SOPM version to |
|--------------|---------------------|
| Release 3.2.0 | `<Version>3.2.0</Version>` |
| Resume dev builds | `<Version>3.2.1</Version>` |

## Prerequisites

### GoCD Agent Requirements

- SSH private key at `~/.ssh/id_rsa` (permissions: 600)
- Network access to target hosts on port 2222

### Environment Variables

Configure these as **secure variables** in GoCD UI:

| Variable | Required | Description |
|----------|----------|-------------|
| `DEV_ZNUNY_HOST` | Yes | IP address of DEV Proxmox host |
| `REF_ZNUNY_HOST` | No | IP address of REF Proxmox host |

**Path:** Admin → Environments → `cicd-v2-test-env` → Environment Variables (Secure)

### Target Host Requirements

Each target host must have:
- Port 2222 forwarded to container port 22
- GoCD agent's public key in `/root/.ssh/authorized_keys` (inside container)
- `PubkeyAuthentication yes` in `/etc/ssh/sshd_config`

## Setup Instructions

### 1. Configure GoCD Config Repository

In GoCD UI: Admin → Config Repositories → Add

| Field | Value |
|-------|-------|
| Plugin | YAML Configuration Plugin |
| Material URL | `ssh://git@bitbucket.mot-solutions.com:7999/msstlite/msst-lite-znuny.git` |
| Branch | `feature/CICD_TEST_RJ` |
| YAML Pattern | `gocd/*.gocd.yaml` |

### 2. Configure Environment Variables

1. Go to Admin → Environments → `cicd-v2-test-env`
2. Add secure environment variables:
   - `DEV_ZNUNY_HOST` = `10.228.33.221`
   - `REF_ZNUNY_HOST` = (your REF host IP)

### 3. Configure SSH on Target Hosts

On each target Proxmox host, add the GoCD agent's public key **inside the container**:

```bash
# Access the container (example for DEV)
pct exec 104 -- bash

# Add public key
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "ssh-rsa AAAA... build@GoCD-dev" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Enable public key authentication
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
```

## Scripts Reference

### preflight-check.sh

Validates deployment prerequisites before any deployment stage runs.

**Checks performed:**
| Check | Required | Description |
|-------|----------|-------------|
| SSH key exists | Yes | `~/.ssh/id_rsa` or `~/.ssh/id_ed25519` |
| SSH key permissions | Yes | Must be 600 |
| SSH config exists | No | Warning only if missing |
| Environment variables | Yes | `DEV_ZNUNY_HOST` must be set |

### deploy-opm.sh

Deploys OPM package to a target Znuny server.

**Usage:**
```bash
./deploy-opm.sh <HOST_IP> <HOST_NAME> <OPM_SOURCE_DIR>
```

**Example:**
```bash
./deploy-opm.sh 10.228.33.221 DEV packages/pkg
```

**Target host checks:**
| Check | Description |
|-------|-------------|
| Port 2222 reachable | TCP connectivity test (5s timeout) |
| SSH public key auth | BatchMode SSH connection test |
| /tmp writable | Touch test file |
| Disk space | Minimum 500MB available |
| Cleanup | Removes old MSSTLite-*.opm files |

## Troubleshooting

### SSH Authentication Failed

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
1. Go to GoCD UI: Admin → Environments → `cicd-v2-test-env`
2. Add the missing variable as a secure environment variable

## Network Architecture

```
GoCD Agent (10.228.33.225, Container 201)
    |
    | ssh -p 2222 root@<PROXMOX_HOST>
    v
Proxmox Host (e.g., 10.228.33.221:2222)
    |
    | iptables DNAT to container:22
    v
Znuny Container (e.g., 172.16.18.22:22)
```

## Related Documentation

- [Versioning Guide](../docs/VERSIONING.md) - Complete versioning documentation with flow diagrams
- [SSH Setup Guide](../CICD/ssh-setup-guide.md)
- [Pipeline Architecture](../CICD/gocd-pipeline-architecture.md)
