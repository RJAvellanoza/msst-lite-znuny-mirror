# MSSTLite Znuny Mirror - Claude Code Configuration

## Parent Project Rules

This repository is part of the MSSTLITE project. See `../CLAUDE.md` for global project rules including:
- Temporary file locations
- Checkpoint conventions
- Plan mode workflow rules

## Repository Overview

This repository contains Znuny/OTRS customizations for MSSTLite:
- **130 Perl modules** (.pm) - Backend logic
- **56 Template Toolkit files** (.tt) - UI templates
- **51 XML SysConfig files** - Configuration definitions
- **37 Shell scripts** - Build and deployment

## Tech Stack

| Technology | Purpose |
|------------|---------|
| Perl 5 | Backend modules |
| Template Toolkit | HTML rendering |
| XML | SysConfig definitions |
| PostgreSQL/MySQL | Database |
| Apache + mod_perl | Web server |
| JavaScript/jQuery | Frontend |

## Key Directories

```
Custom/
├── Kernel/Modules/           # Frontend controllers
├── Kernel/System/            # Backend business logic
├── Kernel/Output/HTML/       # Templates, filters, widgets
├── Kernel/Config/Files/XML/  # SysConfig definitions
└── Kernel/GenericInterface/  # REST/SOAP API handlers

ansible/                       # Deployment automation
├── ansible.cfg                # Ansible configuration
├── inventory/dev.yaml         # DEV environment targets (CT 104)
├── inventory/ref.yaml         # REF environment targets (CT 104)
├── playbooks/
│   ├── preflight.yaml         # Target reachability validation
│   └── deploy-znuny.yaml     # Deployment orchestration with rollback
└── roles/
    ├── snapshot/              # Pre-deploy Proxmox snapshot
    ├── znuny-deploy/          # OPM package installation
    └── health-check/          # Post-deploy verification

gocd/
└── pipeline.sh                # GoCD entry point (build/preflight/deploy)
```

## Available Subagents

This repository has specialized subagents in `.claude/agents/`:
- `perl-expert` - Perl/Znuny module development
- `template-toolkit-expert` - .tt template debugging
- `sysconfig-expert` - XML configuration analysis
- `incident-api-debugger` - REST API troubleshooting
- `license-module-expert` - License/encryption debugging
- `database-migration-expert` - Migration script development

## Common Commands

```bash
# Syntax check Perl module
perl -c Custom/Kernel/System/MyModule.pm

# Build package (local, auto-increments version)
./build-package.sh

# Build package (CI mode, no prompts, no install)
./build-package.sh --ci

# Development setup (creates symlinks)
./setup.sh

# Clear cache and rebuild config
/opt/otrs/bin/otrs.Console.pl Maint::Config::Rebuild
```

## CI/CD Pipeline

GoCD pipelines (`znuny-dev-deploy`, `znuny-ref-deploy`) with three stages each:

```
build → preflight → deploy
```

- **Build**: `build-package.sh --ci` produces OPM artifact
- **Preflight**: Ansible validates Proxmox host + container running
- **Deploy**: Ansible pushes OPM → uninstall old → install new → rebuild config → health check
- **Rollback**: Automatic Proxmox snapshot rollback on any failure

Version in CI: `MAJOR.MINOR` from `MSSTLite.sopm` + GoCD pipeline counter as patch.

See `ansible/README.md` for full deployment documentation.
