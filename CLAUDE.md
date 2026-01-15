# MSSTLite Znuny Mirror - Claude Code Configuration

## Parent Project Rules

This repository is part of the MSSTLITE project. See `../CLAUDE.md` for global project rules including:
- Temporary file locations
- Checkpoint conventions
- **Plan mode workflow rules**

## Plan Mode Rules

**IMPORTANT**: When in plan mode, follow this workflow strictly:

1. **Explore & Research**: Thoroughly investigate the codebase and gather all necessary context
2. **Write Plan**: Document the complete plan in the designated plan file
3. **Summarize**: Provide a clear summary of what the plan contains
4. **Wait for Review**: Ask the user explicitly: "Would you like to review the full plan file before I request approval?"
5. **User Review**: Allow the user time to read the plan file and request any changes
6. **Request Approval**: Only call `ExitPlanMode` after the user explicitly says "proceed", "approved", "looks good", or similar confirmation
7. **Implement**: Begin implementation only after ExitPlanMode approval is granted

**DO NOT** call `ExitPlanMode` immediately after writing the plan. Always wait for explicit user confirmation first.

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

# Build package
./build-package.sh

# Development setup (creates symlinks)
./setup.sh

# Clear cache and rebuild config
/opt/otrs/bin/otrs.Console.pl Maint::Config::Rebuild
```
