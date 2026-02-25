# Znuny Deployment — Ansible

Ansible playbooks for automated MSSTLite OPM package deployment via GoCD pipelines.

## Architecture

```
GoCD Agent → SSH → Proxmox Host → pct push/exec → LXC Container (Znuny)
```

Ansible connects to Proxmox hosts via SSH. Containers run on an isolated network
(`172.16.18.x`) not directly reachable from GoCD. All container interaction uses
Proxmox `pct push` (file transfer) and `pct exec` (command execution).

## Directory Structure

```
ansible/
├── ansible.cfg                          # Ansible configuration
├── inventory/
│   ├── dev.yaml                         # DEV environment targets
│   └── ref.yaml                         # REF environment targets
├── playbooks/
│   ├── preflight.yaml                   # Target reachability validation
│   └── deploy-znuny.yaml               # Main deployment orchestration
└── roles/
    ├── snapshot/tasks/main.yaml         # Pre-deploy container snapshot
    ├── znuny-deploy/tasks/main.yaml     # OPM package installation
    └── health-check/tasks/main.yaml     # Post-deploy verification
```

## Setup Guide

### Prerequisites

1. **Ansible** installed on the GoCD agent (2.14+):

   ```bash
   # Install pip3 (if not present)
   apt update && apt install -y python3-pip

   # Install Ansible (--break-system-packages required on Debian 12+)
   pip3 install ansible --break-system-packages

   # Verify
   ansible --version
   ```

2. **SSH access** from GoCD agent to Proxmox host(s):

   ```bash
   # Generate SSH key on GoCD agent (if not already done)
   ssh-keygen -t ed25519 -C "gocd-agent"

   # Copy public key to Proxmox host(s)
   ssh-copy-id root@10.228.33.221   # DEV
   ssh-copy-id root@10.228.33.223   # REF

   # Verify access
   ssh root@10.228.33.221 "pct list"   # DEV
   ssh root@10.228.33.223 "pct list"   # REF
   ```

3. **No additional environment variables** required for Znuny deployment.
   Unlike Zabbix, Znuny OPM installation uses `Console.pl` as the system user
   and does not need API credentials.

   | Variable | Required | Default | Description |
   |----------|----------|---------|-------------|
   | `ARTIFACT_PATH` | Yes | — | Path to `MSSTLite-*.opm` artifact |
   | `DEPLOY_VERSION` | No | `unknown` | Version extracted from OPM filename |

### Adding a New Environment

Create a new inventory file in `inventory/`. For example, `inventory/ref.yaml`:

```yaml
all:
  children:
    proxmox_hosts:
      hosts:
        ref-proxmox:
          ansible_host: <REF_PROXMOX_IP>
          ansible_user: root
          znuny_containers:
            - ct_id: <CONTAINER_ID>
              ct_name: <CONTAINER_NAME>
              znuny_url: "http://<CONTAINER_IP>/otrs/index.pl"
```

Then run with `-i inventory/ref.yaml` — no playbook or role changes needed.

For multi-host environments (e.g., Norway with multiple Proxmox hosts), list all
hosts under `proxmox_hosts` — Ansible deploys to all of them using the same playbook:

```yaml
all:
  children:
    proxmox_hosts:
      hosts:
        norway-dc1-host1:
          ansible_host: <IP>
          ansible_user: root
          znuny_containers:
            - ct_id: 104
              ct_name: lsmp-itsm-1
              znuny_url: "http://<IP>/otrs/index.pl"
        norway-dc1-host2:
          ansible_host: <IP>
          ansible_user: root
          znuny_containers:
            - ct_id: 104
              ct_name: lsmp-itsm-2
              znuny_url: "http://<IP>/otrs/index.pl"
```

## Deployment Reference

### Pipeline Stages

Two GoCD pipelines share the same stages and roles:

| Pipeline | Trigger | Target |
|----------|---------|--------|
| `znuny-dev-deploy` | Push to `develop` | DEV (10.228.33.221, CT 104) |
| `znuny-ref-deploy` | Push to `master` | REF (10.228.33.223, CT 104) |

Each pipeline has three stages:

```
build → preflight → deploy
```

#### Stage 1: Build

- Runs `build-package.sh --ci` inside the source directory
- Version is auto-incremented from `MSSTLite.sopm` (single source of truth)
- Produces `MSSTLite-{version}.opm` in `.build/`
- Publishes OPM as a GoCD artifact

#### Stage 2: Preflight

- Verifies Proxmox host is reachable via SSH
- Verifies all Znuny containers are in `running` state
- Fails with clear error if any target is unreachable

#### Stage 3: Deploy

Runs three Ansible roles in sequence:

1. **snapshot** — Creates a Proxmox snapshot (`pre-deploy-{version}-{date}`)
   for rollback capability
2. **znuny-deploy** — Pushes OPM into container, detects Znuny user/home,
   uninstalls old package, installs new OPM, rebuilds config, clears cache
3. **health-check** — Verifies apache2 is active, web returns HTTP 200/302,
   and MSSTLite is listed in Package Manager

If any phase fails, the rescue block rolls back all containers to the
pre-deploy snapshot.

### OPM Installation Flow

```
1. Push OPM to container /tmp/
2. Detect user (otrs or znuny)
3. Detect home (/opt/otrs or /opt/znuny)
4. Check if MSSTLite already installed
5. If yes: Uninstall via Console.pl
   5a. If uninstall fails: DELETE from package_repository (DB fallback)
6. Install new OPM via Console.pl
7. Rebuild configuration
8. Clear cache
```

### Manual Execution

Run playbooks manually from the `ansible/` directory:

```bash
cd ansible/

# Preflight only
ansible-playbook -i inventory/dev.yaml playbooks/preflight.yaml -v

# Full deploy
ARTIFACT_PATH=/path/to/MSSTLite-2.0.1.opm \
DEPLOY_VERSION=2.0.1 \
ansible-playbook -i inventory/dev.yaml playbooks/deploy-znuny.yaml -v

# Dry run (check mode — no changes made)
ARTIFACT_PATH=/path/to/MSSTLite-2.0.1.opm \
ansible-playbook -i inventory/dev.yaml playbooks/deploy-znuny.yaml --check -v
```

### Rollback

If a deployment fails, the pipeline automatically rolls back to the pre-deploy
snapshot. To manually restore:

```bash
# List snapshots on CT 104
pct listsnapshot 104

# Rollback to a specific snapshot
pct rollback 104 pre-deploy-2-0-1-20260218

# Start the container after rollback
pct start 104
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `UNREACHABLE` on Proxmox host | SSH key not configured | Run `ssh-copy-id root@<host>` |
| `container is not running` | Container stopped | Start with `pct start <ct_id>` |
| `Znuny web returned HTTP 000` | Apache not started | Check `systemctl status apache2` inside container |
| `Artifact not found` | `ARTIFACT_PATH` not set or wrong path | Verify artifact exists at the specified path |
| `MSSTLite package not found` | Install failed silently | Check `otrs.Console.pl Admin::Package::List` inside container |
| `unknown` user detected | Neither `otrs` nor `znuny` user exists | Verify Znuny installation inside the container |
| Uninstall fails with DB error | Orphaned package_repository entry | The playbook handles this automatically via DB fallback |
| Build fails with `read -p` | Missing `--ci` flag | Ensure `build-package.sh` is called with `--ci` |
