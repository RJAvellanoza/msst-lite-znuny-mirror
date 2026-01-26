# MSSTLite Versioning Guide

## Document Metadata

| Field | Value |
|-------|-------|
| Version | 2.0 |
| Last Updated | 2026-01-26 |
| Author | RJ Avellanoza |
| Audience | Developers, CI/CD Engineers |

---

## Overview

MSSTLite uses **Semantic Versioning** with CI/CD automation.

**Format:** `MAJOR.MINOR.PATCH` (e.g., 3.2.0)

---

## Quick Reference

| I want to... | Set SOPM version to | Result |
|--------------|---------------------|--------|
| Release version 3.2.0 | `3.2.0` | Builds exactly 3.2.0 |
| Continue dev builds | `3.2.1` | CI auto-versions (3.2.47, 3.2.48...) |
| Major release 4.0.0 | `4.0.0` | Builds exactly 4.0.0 |

---

## How It Works

### Key Concept

> **The pipeline modifies a temporary copy of the SOPM file before building. The git repository is never changed.**

### Release Versions (PATCH = 0)

When you set PATCH to `0`, the CI builds that **exact version**:

```xml
<Version>3.2.0</Version>  <!-- CI builds: MSSTLite-3.2.0.opm -->
```

Use this for:
- Official releases
- Version milestones
- Production deployments

### Development Builds (PATCH > 0)

When PATCH is greater than `0`, CI **replaces it** with the pipeline counter:

```xml
<Version>3.2.1</Version>  <!-- CI builds: MSSTLite-3.2.{PIPELINE_COUNTER}.opm -->
```

Example: If pipeline counter is 47, output is `MSSTLite-3.2.47.opm`

Use this for:
- Development builds
- Testing on DEV/REF environments
- Continuous integration

---

## Pipeline Versioning Flow

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GOCD PIPELINE VERSIONING FLOW                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  STEP 1: GIT CHECKOUT                                                       │
│  ════════════════════                                                       │
│                                                                             │
│    Git Repository                    Pipeline Workspace                     │
│    ┌──────────────────┐              ┌──────────────────┐                   │
│    │ MSSTLite.sopm    │  ──COPY──►   │ MSSTLite.sopm    │                   │
│    │ Version: 3.2.1   │              │ Version: 3.2.1   │                   │
│    └──────────────────┘              └──────────────────┘                   │
│                                                                             │
│  STEP 2: VERSION INJECTION (inject_version function)                        │
│  ═══════════════════════════════════════════════════                        │
│                                                                             │
│    Pipeline Workspace                GO_PIPELINE_COUNTER = 47               │
│    ┌──────────────────┐                                                     │
│    │ MSSTLite.sopm    │  ──sed -i──►  Version: 3.2.1 → 3.2.47               │
│    │ Version: 3.2.47  │              (PATCH replaced with counter)          │
│    └──────────────────┘                                                     │
│                                                                             │
│  STEP 3: BUILD PACKAGE                                                      │
│  ═════════════════════                                                      │
│                                                                             │
│    Pipeline Workspace                                                       │
│    ┌──────────────────┐              ┌─────────────────────────┐            │
│    │ MSSTLite.sopm    │  ──BUILD──►  │ MSSTLite-3.2.47.opm     │            │
│    │ Version: 3.2.47  │              │ (artifact)              │            │
│    └──────────────────┘              └─────────────────────────┘            │
│                                                                             │
│  STEP 4: CLEANUP                                                            │
│  ═══════════════                                                            │
│                                                                             │
│    Git Repository                    Pipeline Workspace                     │
│    ┌──────────────────┐              ┌──────────────────┐                   │
│    │ MSSTLite.sopm    │              │     DISCARDED    │                   │
│    │ Version: 3.2.1   │              │                  │                   │
│    │ (UNCHANGED)      │              └──────────────────┘                   │
│    └──────────────────┘                                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Version Decision Logic

```
┌─────────────────────────────────────────────────────────────────┐
│                    VERSION DECISION TREE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    Read SOPM Version (e.g., 3.2.1)                              │
│                │                                                │
│                ▼                                                │
│    Parse: MAJOR.MINOR.PATCH                                     │
│            3   .  2  .  1                                       │
│                │                                                │
│                ▼                                                │
│    ┌─────────────────────┐                                      │
│    │   Is PATCH == 0 ?   │                                      │
│    └──────────┬──────────┘                                      │
│               │                                                 │
│      ┌───YES──┴───NO───┐                                        │
│      ▼                 ▼                                        │
│  ┌─────────┐    ┌─────────────────┐                             │
│  │ RELEASE │    │   DEV BUILD     │                             │
│  │ MODE    │    │   MODE          │                             │
│  ├─────────┤    ├─────────────────┤                             │
│  │ Keep    │    │ Replace PATCH   │                             │
│  │ as-is   │    │ with pipeline   │                             │
│  │         │    │ counter         │                             │
│  ├─────────┤    ├─────────────────┤                             │
│  │ 3.2.0   │    │ 3.2.1 → 3.2.47  │                             │
│  │ stays   │    │ (counter=47)    │                             │
│  │ 3.2.0   │    │                 │                             │
│  └─────────┘    └─────────────────┘                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow Table

| Step | Input | Operation | Output | Persisted? |
|------|-------|-----------|--------|------------|
| 1. Checkout | Git repo | Copy to workspace | Workspace copy | No |
| 2. Inject | SOPM (3.2.1) | sed -i (if PATCH>0) | SOPM (3.2.47) | No |
| 3. Build | SOPM (3.2.47) | Dev::Package::Build | .opm file | Yes |
| 4. Deploy | .opm file | SCP + Install | Installed package | Yes |
| 5. Cleanup | Workspace | Delete | Empty | N/A |

---

## Local vs CI Builds

| Mode | Command | Version Behavior |
|------|---------|------------------|
| Local | `./build-package.sh` | Always increments PATCH (e.g., 3.2.5 → 3.2.6) |
| CI | `./build-package.sh --skip-version-increment` | Uses version injected by pipeline |

### Local Build Behavior

When running `./build-package.sh` locally (without flags):
- PATCH is **always** incremented
- The SOPM file is updated with the new version
- Useful for testing builds on development containers

```bash
# Example: SOPM has 3.2.5
./build-package.sh
# Result: Builds MSSTLite-3.2.6.opm, SOPM updated to 3.2.6
```

### CI Build Behavior

When running with `--skip-version-increment` (CI mode):
- Version is **not modified** by build-package.sh
- Pipeline injects the correct version before calling build script
- PATCH=0 → exact version (release), PATCH>0 → pipeline counter (dev)

---

## Version Workflow

### Starting a New Release Cycle

```
1. Current: 3.1.x (dev builds)
2. Ready for release: Change SOPM to 3.2.0
3. CI builds: MSSTLite-3.2.0.opm (release)
4. After release: Change SOPM to 3.2.1
5. CI builds: MSSTLite-3.2.47.opm (dev continues)
```

### When to Bump MAJOR

Increment MAJOR for **breaking changes**:

```xml
<!-- Before: 2.5.x -->
<Version>3.0.0</Version>  <!-- Breaking change release -->
<!-- After release: -->
<Version>3.0.1</Version>  <!-- Dev continues -->
```

### When to Bump MINOR

Increment MINOR for **new features** (backwards compatible):

```xml
<!-- Before: 3.2.x -->
<Version>3.3.0</Version>  <!-- Feature release -->
<!-- After release: -->
<Version>3.3.1</Version>  <!-- Dev continues -->
```

---

## Examples

### Version Matrix

| SOPM Version | Pipeline # | Built Package | Type |
|--------------|------------|---------------|------|
| 3.2.0 | 45 | MSSTLite-3.2.0.opm | Release |
| 3.2.1 | 46 | MSSTLite-3.2.46.opm | Dev build |
| 3.2.1 | 47 | MSSTLite-3.2.47.opm | Dev build |
| 3.3.0 | 48 | MSSTLite-3.3.0.opm | Release |
| 3.3.1 | 49 | MSSTLite-3.3.49.opm | Dev build |

### Example: Development Build (YAML)

```yaml
input:
  git_repository:
    file: MSSTLite.sopm
    version: "3.2.1"
  pipeline:
    counter: 47

processing:
  patch_value: 1  # Greater than 0
  action: REPLACE_PATCH_WITH_COUNTER

output:
  built_artifact: MSSTLite-3.2.47.opm
  git_repository_changed: false
```

### Example: Release Build (YAML)

```yaml
input:
  git_repository:
    file: MSSTLite.sopm
    version: "3.2.0"
  pipeline:
    counter: 48

processing:
  patch_value: 0  # Equals 0
  action: KEEP_AS_IS

output:
  built_artifact: MSSTLite-3.2.0.opm
  git_repository_changed: false
```

---

## Checklist for Releases

- [ ] Update `<Version>` in MSSTLite.sopm to X.Y.0
- [ ] Update CHANGELOG.md with release notes
- [ ] Commit and push
- [ ] Verify CI builds exact version
- [ ] After deployment, change SOPM to X.Y.1 for dev builds

---

## Branch-Specific Pipelines

Each release branch has its own pipeline with independent counter:

| Branch | Pipeline | Counter |
|--------|----------|---------|
| master | znuny-build-pipeline | Starts at 1 |
| R1.1 | znuny-rel1.1-pipeline | Starts at 1 |
| R2.0 | znuny-rel2.0-pipeline | Starts at 1 |
| R3.0 | znuny-rel3.0-pipeline | Starts at 1 |

When creating a new release branch, create a new pipeline in GoCD.

---

## Script Reference

### File: `gocd-build-application.sh`

```bash
inject_version() {
    local SOPM="$1"

    # Extract current version from SOPM file
    local CURRENT=$(grep '<Version>' "$SOPM" | sed 's/.*<Version>\([^<]*\)<\/Version>.*/\1/')

    # Parse version components
    local MAJOR=$(echo "$CURRENT" | cut -d. -f1)
    local MINOR=$(echo "$CURRENT" | cut -d. -f2)
    local PATCH=$(echo "$CURRENT" | cut -d. -f3)

    # Decision: Release or Dev build?
    if [ "$PATCH" = "0" ]; then
        # RELEASE: Keep version unchanged
        return
    else
        # DEV BUILD: Replace PATCH with pipeline counter
        local NEW_VERSION="${MAJOR}.${MINOR}.${GO_PIPELINE_COUNTER}"
        sed -i "s|<Version>${CURRENT}</Version>|<Version>${NEW_VERSION}</Version>|" "$SOPM"
    fi
}
```

### Key Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `GO_PIPELINE_COUNTER` | GoCD environment | Auto-incrementing build number |
| `GO_PIPELINE_NAME` | GoCD environment | Pipeline identifier |
| `APP_BUILD_DIR` | Script parameter | Temporary build workspace |

---

## Important Rules

### Rule 1: Git Repository Never Changes

The pipeline **never commits** version changes back to git. The version in git is the "source of truth" for determining build type (release vs dev).

### Rule 2: PATCH=0 Means Release

When a developer sets PATCH to `0`, they are signaling: "I want this exact version built."

### Rule 3: PATCH>0 Means Development

When PATCH is greater than `0`, the pipeline assumes this is a development build and auto-versions it.

### Rule 4: Pipeline Counter Always Increases

The `GO_PIPELINE_COUNTER` increments with every pipeline run, including failed builds. This ensures unique version numbers.

---

## Troubleshooting

### "Why is my version not 3.2.0?"

Check if PATCH is 0 in your SOPM:
```xml
<Version>3.2.0</Version>  <!-- Correct for release -->
<Version>3.2.1</Version>  <!-- Will be auto-versioned -->
```

### "Why did version jump from 3.2.45 to 3.2.52?"

Pipeline counter increments even for failed builds. This is normal.

### "How do I find which build created version 3.2.47?"

Version 3.2.47 = Pipeline run #47. Check GoCD build history.

---

## Related Files

| File | Purpose |
|------|---------|
| `MSSTLite.sopm` | Contains the version number |
| `gocd-build-application.sh` | Injects pipeline counter into version (CI only) |
| `build-package.sh` | Build script (local: increments, CI: uses injected version) |
| `gocd/README.md` | CI/CD pipeline configuration |

---

## Quick Reference (Structured)

### Code Analysis

```yaml
file_purpose: "Automatic version injection for CI/CD builds"
key_function: "inject_version()"
decision_point: "PATCH value determines build type"
side_effects: "Modifies temporary file only, not git repository"
```

### Modification Guidelines

```yaml
safe_to_modify:
  - Version parsing logic
  - Logging/echo statements
  - Error handling

requires_caution:
  - sed command (affects version in built package)
  - File paths (must match pipeline workspace structure)

do_not_modify:
  - GO_PIPELINE_COUNTER usage (breaks version traceability)
  - --skip-version-increment flag (breaks local vs CI distinction)
```

### Common Issues

```yaml
common_issues:
  - issue: "Wrong version in built package"
    check: "PATCH value in SOPM"

  - issue: "sed command not working"
    check: "Version format (must be X.Y.Z)"

  - issue: "File not found"
    check: "APP_BUILD_DIR and APP_CHECKOUT_DEST paths"
```

---

## Pending Questions (For Team Discussion)

### Versioning for Secondary Packages

**Package:** `package-definitions/znuny-users-groups.sopm`

**Current Status:** Versioned independently (not auto-versioned by CI)

**Question:** How should `znuny-users-groups` be versioned?

| Option | Description |
|--------|-------------|
| A. Manual versioning | Developer manually updates version when changes are made |
| B. Same as MSSTLite | Follow MSSTLite version (e.g., both become 3.2.47) |
| C. Linked but independent | Use same MAJOR.MINOR as MSSTLite, but own PATCH |

**Decision needed by:** [TBD]
**Decided:** [Pending]

---

## Changelog

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-26 | RJ Avellanoza | Initial documentation |
| 2.0 | 2026-01-26 | RJ Avellanoza | Merged pipeline flow documentation |
