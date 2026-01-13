# Development Tools

This directory contains scripts and tools for development and troubleshooting purposes only.

**These tools are NOT needed for normal package installation via Znuny Package Manager.**

## Tools

### deploy_smtp.sh

**Purpose**: Manually force deployment of SMTP notification configuration.

**When to use**:
- During development when using symlinks (via `setup.sh`)
- If configuration didn't deploy properly during package installation
- To force reload configuration after manual XML file changes
- For troubleshooting configuration issues

**When NOT to use**:
- After normal package installation (configuration is deployed automatically)
- In production environments (unless troubleshooting)

**Usage**:
```bash
# Auto-detect Znuny installation
./deploy_smtp.sh

# Or specify custom path
ZNUNY_ROOT=/path/to/znuny ./deploy_smtp.sh
```

### validate-templates.sh

**Purpose**: Validates template files for missing includes and syntax errors.

**When to use**:
- Before building a package to ensure all templates are valid
- After modifying template files
- To check for missing template dependencies

**Usage**:
```bash
./validate-templates.sh
```

## Important Notes

1. **Package Installation**: When installing MSSTLite via the Znuny Package Manager (`.opm` file), all configurations are automatically imported and deployed. These scripts are not needed.

2. **Development Mode**: These scripts are primarily useful when developing with the repository cloned and symlinked via `setup.sh`.

3. **Production Use**: Avoid using these scripts in production unless specifically troubleshooting configuration deployment issues.