#!/bin/bash
# Build Package Script for MSSTLite
# Version: 2.4 (2026-01-26)
#
# This script:
# 1. Copies files from Custom/ to proper Kernel/ structure
# 2. Builds the package using Znuny's Dev::Package::Build
# 3. Automatically installs the package (unless --no-install is specified)
#
# Usage: ./build-package.sh [--no-install] [--skip-version-increment]
#
# Flags:
#   --no-install              Build only, don't install
#   --skip-version-increment  Don't increment version after build (used by CI)
#
# Environment Modes:
#   Local (default):  Requires root. Builds, fixes permissions, and installs.
#   CI (--no-install): No root required. Builds package only, skips privileged
#                      operations (otrs.SetPermissions.pl, su znuny).
#
# IMPORTANT: When running in CI/CD pipelines (e.g., GoCD), always use --no-install
#            as the pipeline agent typically runs as a non-privileged user and
#            cannot execute su or root-level commands.
#
# See docs/VERSIONING.md for versioning documentation

# Check for flags
AUTO_INSTALL=true
SKIP_VERSION_INCREMENT=false

for arg in "$@"; do
    case $arg in
        --no-install)
            AUTO_INSTALL=false
            echo "Auto-install disabled"
            ;;
        --skip-version-increment)
            SKIP_VERSION_INCREMENT=true
            echo "Version increment disabled (CI mode)"
            ;;
    esac
done

echo "Preparing files for package build..."

# Run template validation first (if script exists)
if [ -f "./dev/tools/validate-templates.sh" ]; then
    echo "Running template validation..."
    if ./dev/tools/validate-templates.sh; then
        echo "Template validation passed"
    else
        echo "Template validation failed - aborting build"
        exit 1
    fi
    echo ""
else
    echo "Skipping template validation (validate-templates.sh not found)"
    echo ""
fi

# Clean old build files to prevent stale file issues
echo "Cleaning old build files..."
rm -rf Kernel/
rm -rf var/

# Create directory structure
mkdir -p Kernel/Config/Files/XML
mkdir -p Kernel/Language
mkdir -p Kernel/Modules
mkdir -p Kernel/System
mkdir -p Kernel/System/Ticket/Event
mkdir -p Kernel/Output/HTML/FilterContent
mkdir -p Kernel/Output/HTML/Notification
mkdir -p Kernel/Output/HTML/Preferences
mkdir -p Kernel/Output/HTML/Templates/Standard

# Copy configuration files
echo "Copying configuration files..."
# Copy both .pm and .xml files from Config/Files
if ls Custom/Kernel/Config/Files/*.pm >/dev/null 2>&1; then
    cp Custom/Kernel/Config/Files/*.pm Kernel/Config/Files/
fi
if ls Custom/Kernel/Config/Files/XML/*.xml >/dev/null 2>&1; then
    cp Custom/Kernel/Config/Files/XML/*.xml Kernel/Config/Files/XML/
fi

# Copy language files
echo "Copying language files..."
cp Custom/Kernel/Language/*.pm Kernel/Language/ 2>/dev/null || true

# Copy module files
echo "Copying module files..."
cp Custom/Kernel/Modules/*.pm Kernel/Modules/ 2>/dev/null || true

# Copy system files
echo "Copying system files..."
cp Custom/Kernel/System/*.pm Kernel/System/ 2>/dev/null || true
cp -r Custom/Kernel/System/Ticket Kernel/System/ 2>/dev/null || true
mkdir -p Kernel/System/GenericAgent
cp Custom/Kernel/System/GenericAgent/*.pm Kernel/System/GenericAgent/ 2>/dev/null || true
mkdir -p Kernel/System/Console/Command
cp Custom/Kernel/System/Console/Command/*.pm Kernel/System/Console/Command/ 2>/dev/null || true

# Copy GenericInterface files
mkdir -p Kernel/GenericInterface
cp Custom/Kernel/GenericInterface/*.pm Kernel/GenericInterface/ 2>/dev/null || true

# Copy GenericInterface Invoker modules
echo "Copying GenericInterface modules..."
mkdir -p Kernel/GenericInterface/Invoker/TwilioSMS
cp -r Custom/Kernel/GenericInterface/Invoker/TwilioSMS/*.pm Kernel/GenericInterface/Invoker/TwilioSMS/ 2>/dev/null || true

# Copy GenericInterface Operation modules
mkdir -p Kernel/GenericInterface/Operation/Incident
cp -r Custom/Kernel/GenericInterface/Operation/Incident/*.pm Kernel/GenericInterface/Operation/Incident/ 2>/dev/null || true

# Copy output modules
echo "Copying output modules..."
cp Custom/Kernel/Output/HTML/FilterContent/*.pm Kernel/Output/HTML/FilterContent/ 2>/dev/null || true
cp Custom/Kernel/Output/HTML/Notification/*.pm Kernel/Output/HTML/Notification/ 2>/dev/null || true
cp Custom/Kernel/Output/HTML/Preferences/*.pm Kernel/Output/HTML/Preferences/ 2>/dev/null || true
mkdir -p Kernel/Output/HTML/Dashboard
cp Custom/Kernel/Output/HTML/Dashboard/*.pm Kernel/Output/HTML/Dashboard/ 2>/dev/null || true
mkdir -p Kernel/Output/HTML/Layout
cp Custom/Kernel/Output/HTML/Layout/*.pm Kernel/Output/HTML/Layout/ 2>/dev/null || true

# Copy templates
echo "Copying template files..."
cp Custom/Kernel/Output/HTML/Templates/Standard/*.tt Kernel/Output/HTML/Templates/Standard/ 2>/dev/null || true

# Create directory structure for package files
mkdir -p var/packagesetup

# Copy package setup files
echo "Copying package setup files..."
if [ -d "Custom/var/packagesetup" ]; then
    mkdir -p var/packagesetup
    cp -r Custom/var/packagesetup/* var/packagesetup/ 2>/dev/null || true
fi

# Copy webservice files
echo "Copying webservice files..."
if [ -d "Custom/var/webservices" ]; then
    mkdir -p var/webservices
    cp -r Custom/var/webservices/* var/webservices/ 2>/dev/null || true
fi

# Copy category CSV files
echo "Copying category files..."
if [ -d "Custom/var/categories" ]; then
    mkdir -p var/categories
    cp Custom/var/categories/*.csv var/categories/ 2>/dev/null || true
fi

# Copy httpd files for incident module
# Copy httpd files for UI/UX
echo "Copying httpd files..."
if [ -d "Custom/var/httpd" ]; then
    mkdir -p var/httpd/htdocs/js
    mkdir -p var/httpd/htdocs/skins/Agent/default/css
    mkdir -p var/httpd/htdocs/skins/Agent/motorola/{css,fonts,img}
    cp Custom/var/httpd/htdocs/js/*.js var/httpd/htdocs/js/ 2>/dev/null || true
    cp Custom/var/httpd/htdocs/skins/Agent/default/css/*.css var/httpd/htdocs/skins/Agent/default/css/ 2>/dev/null || true
    cp Custom/var/httpd/htdocs/skins/Agent/motorola/css/*.css var/httpd/htdocs/skins/Agent/motorola/css/ 2>/dev/null || true
    cp Custom/var/httpd/htdocs/skins/Agent/motorola/fonts/*.css var/httpd/htdocs/skins/Agent/motorola/fonts/ 2>/dev/null || true
    cp Custom/var/httpd/htdocs/skins/Agent/motorola/img/*.png var/httpd/htdocs/skins/Agent/motorola/img/ 2>/dev/null || true
    cp Custom/var/httpd/htdocs/skins/Agent/motorola/img/*.ico var/httpd/htdocs/skins/Agent/motorola/img/ 2>/dev/null || true
fi

# Copy settings files for UI/UX
echo "Copying var/settings files..."
if [ -d "Custom/var/settings" ]; then
    mkdir -p var/settings
    cp Custom/var/settings/*.yaml var/settings/ 2>/dev/null || true
fi

# Copy scripts/database files (for triggers, etc.)
echo "Copying scripts/database files..."
if [ -d "Custom/scripts/database" ]; then
    mkdir -p scripts/database
    cp Custom/scripts/database/*.sql scripts/database/ 2>/dev/null || true
fi

# Copy bin files
echo "Copying bin files..."
if [ -d "Custom/bin" ]; then
    mkdir -p bin
    cp Custom/bin/*.pl bin/ 2>/dev/null || true
    cp Custom/bin/*.sh bin/ 2>/dev/null || true
    cp Custom/bin/*.sql bin/ 2>/dev/null || true
    chmod 755 bin/*.pl 2>/dev/null || true
    chmod 755 bin/*.sh 2>/dev/null || true
    chmod 644 bin/*.sql 2>/dev/null || true
fi

echo "Files prepared for building"

# Fix permissions on copied files
chmod -R 644 Kernel/ 2>/dev/null || true
find Kernel/ -type d -exec chmod 755 {} \; 2>/dev/null || true

# Verify all files listed in SOPM exist
echo ""
echo "Verifying SOPM file list..."
MISSING_FILES=()
while IFS= read -r line; do
    if [[ $line =~ Location=\"([^\"]+)\" ]]; then
        FILE_PATH="${BASH_REMATCH[1]}"
        # Check if file exists in current directory
        if [ ! -f "$FILE_PATH" ]; then
            # Check if it's a Custom file that needs to be in Kernel
            if [[ $FILE_PATH =~ ^Kernel/ ]]; then
                CUSTOM_PATH="Custom/$FILE_PATH"
                if [ ! -f "$CUSTOM_PATH" ]; then
                    MISSING_FILES+=("$FILE_PATH (also checked $CUSTOM_PATH)")
                fi
            else
                MISSING_FILES+=("$FILE_PATH")
            fi
        fi
    fi
done < <(grep '<File' MSSTLite.sopm)

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo "✗ ERROR: The following files listed in SOPM are missing:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""
    echo "Build aborted!"
    exit 1
else
    echo "✓ All files in SOPM verified"
fi

# Check for files in Custom that are NOT in SOPM
echo "Checking for unlisted files..."
UNLISTED_FILES=()

# Get all files from SOPM (remove 'Custom/' prefix for comparison)
SOPM_FILES=()
while IFS= read -r line; do
    if [[ $line =~ Location=\"([^\"]+)\" ]]; then
        FILE_PATH="${BASH_REMATCH[1]}"
        SOPM_FILES+=("$FILE_PATH")
        # Also add Custom/ version
        SOPM_FILES+=("Custom/$FILE_PATH")
    fi
done < <(grep '<File' MSSTLite.sopm)

# Check all .pm, .tt, .xml, .yml files in Custom
while IFS= read -r file; do
    # Remove leading ./ if present
    file="${file#./}"
    
    # Check if this file is in SOPM
    found=0
    for sopm_file in "${SOPM_FILES[@]}"; do
        if [ "$file" = "$sopm_file" ] || [ "$file" = "${sopm_file#Custom/}" ] || [ "Custom/$file" = "$sopm_file" ]; then
            found=1
            break
        fi
    done
    
    if [ $found -eq 0 ]; then
        # Skip certain files that shouldn't be in package
        if [[ ! "$file" =~ (\.git|\.docs|test/|\.swp$|~$|\.bak$) ]]; then
            UNLISTED_FILES+=("$file")
        fi
    fi
done < <(find Custom/Kernel -type f \( -name "*.pm" -o -name "*.tt" -o -name "*.xml" -o -name "*.yml" \) 2>/dev/null)

# Also check var directory
while IFS= read -r file; do
    file="${file#./}"
    found=0
    for sopm_file in "${SOPM_FILES[@]}"; do
        if [ "$file" = "$sopm_file" ] || [ "$file" = "${sopm_file#Custom/}" ]; then
            found=1
            break
        fi
    done
    
    if [ $found -eq 0 ]; then
        UNLISTED_FILES+=("$file")
    fi
done < <(find Custom/var -type f \( -name "*.yml" -o -name "*.pm" \) 2>/dev/null)

if [ ${#UNLISTED_FILES[@]} -gt 0 ]; then
    echo "⚠ WARNING: The following files exist but are NOT listed in SOPM:"
    for file in "${UNLISTED_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""
    read -p "Continue with build anyway? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Build aborted!"
        exit 1
    fi
else
    echo "✓ All Custom files are listed in SOPM"
fi

# Detect Znuny installation directory
ZNUNY_HOME=""
if [ -d "/opt/znuny-6.5.15" ]; then
    ZNUNY_HOME="/opt/znuny-6.5.15"
elif [ -d "/opt/znuny" ]; then
    ZNUNY_HOME="/opt/znuny"
elif [ -d "/opt/otrs" ]; then
    ZNUNY_HOME="/opt/otrs"
else
    echo "✗ ERROR: Could not find Znuny installation directory!"
    exit 1
fi

echo "Detected Znuny installation: $ZNUNY_HOME"
# Detect the Znuny user
ZNUNY_USER="otrs"
if ! id "$ZNUNY_USER" &>/dev/null; then
    ZNUNY_USER="znuny"
    if ! id "$ZNUNY_USER" &>/dev/null; then
        ZNUNY_USER=$(stat -c '%U' "$ZNUNY_PATH/bin/otrs.Console.pl" 2>/dev/null || echo "")
    fi
fi

# Copy all files to Znuny installation directory
echo ""
echo "Copying files to Znuny installation..."
su $ZNUNY_USER -c "cp -rp Kernel/* $ZNUNY_HOME/Kernel/"
if [ -d "var" ]; then
    su $ZNUNY_USER -c "cp -rp var/* $ZNUNY_HOME/var/"
fi
if [ -d "scripts" ]; then
    su $ZNUNY_USER -c "mkdir -p $ZNUNY_HOME/scripts && cp -rp scripts/* $ZNUNY_HOME/scripts/"
fi

# Get version from SOPM file
CURRENT_VERSION=$(grep '<Version>' MSSTLite.sopm | sed 's/.*<Version>\(.*\)<\/Version>.*/\1/')

# Parse version components - expecting format like 1.0.9 or 1.0.20
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"

# Handle 3-part version (1.0.9)
if [ ${#VERSION_PARTS[@]} -eq 3 ]; then
    MAJOR="${VERSION_PARTS[0]}"
    MINOR="${VERSION_PARTS[1]}"
    BUILD="${VERSION_PARTS[2]}"
else
    echo "ERROR: Unexpected version format: $CURRENT_VERSION"
    echo "Expected format: MAJOR.MINOR.BUILD (e.g., 1.0.9)"
    exit 1
fi

# Version handling depends on CI mode
if [ "$SKIP_VERSION_INCREMENT" = "false" ]; then
    # Local build mode - always increment version
    BUILD=$((BUILD + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${BUILD}"

    echo "Updating version from $CURRENT_VERSION to $NEW_VERSION..."
    sed -i "s|<Version>$CURRENT_VERSION</Version>|<Version>$NEW_VERSION</Version>|" MSSTLite.sopm

    VERSION=$NEW_VERSION
else
    # CI mode: Version was already injected by gocd-build-application.sh
    echo "Using version: $CURRENT_VERSION (CI mode - version was injected)"
    VERSION=$CURRENT_VERSION
fi

echo ""
echo "Building MSSTLite version $VERSION..."

# Build the package
# Create temporary symlinks for files that need to be in Znuny's directory
for file in Kernel/Config/Files/*.pm; do
    if [ -f "$file" ]; then
        su $ZNUNY_USER -c "ln -sf $PWD/$file $ZNUNY_HOME/$file 2>/dev/null || true"
    fi
done
for file in Kernel/Config/Files/XML/*.xml; do
    if [ -f "$file" ]; then
	su $ZNUNY_USER -c "ln -sf $PWD/$file $ZNUNY_HOME/$file 2>/dev/null || true"
    fi
done

su $ZNUNY_USER -c "$ZNUNY_HOME/bin/otrs.Console.pl Dev::Package::Build --module-directory $PWD $PWD/MSSTLite.sopm $PWD"

# Clean up symlinks
find $ZNUNY_HOME/Kernel -type l -delete 2>/dev/null || true

if [ -f "MSSTLite-${VERSION}.opm" ]; then
    echo ""
    echo "✓ Package built successfully: MSSTLite-${VERSION}.opm"

    # Clean up temporary build directories
    echo "Cleaning up temporary files..."
    rm -rf Kernel/ var/ bin/
    echo "✓ Cleanup complete"

    # ===========================================================================
    # LOCAL INSTALL MODE (default)
    # Requires: root privileges, su access to znuny user
    # ===========================================================================
    if [ "$AUTO_INSTALL" = true ]; then

        # Fix file ownership and permissions for Znuny web server
        # - Sets correct owner (znuny/otrs user)
        # - Sets correct group (www-data for Apache)
        # Requires: root privileges
        echo "Fixing Znuny permissions..."
        $ZNUNY_HOME/bin/otrs.SetPermissions.pl --otrs-user=$ZNUNY_USER --web-group=www-data
        echo "✓ Permissions fixed"

        echo ""

        # Remove existing MSSTLite package from Znuny
        # - Uses Admin::Package::Uninstall console command
        # - Errors ignored (|| true) because package may not be installed
        # - stderr suppressed (2>/dev/null) for cleaner output
        # Requires: su access to znuny user
        echo "Removing existing package (if any)..."
        su $ZNUNY_USER -c "cd $ZNUNY_HOME/bin && ./otrs.Console.pl Admin::Package::Uninstall MSSTLite" 2>/dev/null || true
        echo ""

        # Install the newly built OPM package
        # - Uses Admin::Package::Install (fresh install after uninstall)
        # - Reads package from current working directory
        # Requires: su access to znuny user
        echo "Installing package..."
        su $ZNUNY_USER -c "cd $ZNUNY_HOME/bin && ./otrs.Console.pl Admin::Package::Install $PWD/MSSTLite-${VERSION}.opm"

        if [ $? -eq 0 ]; then
            echo ""
            echo "✓ Package installed successfully!"
        else
            echo ""
            echo "✗ Package installation failed!"
            echo "You can manually install with:"
            echo "su $ZNUNY_USER -c \"cd $ZNUNY_HOME/bin && ./otrs.Console.pl Admin::Package::Install $PWD/MSSTLite-${VERSION}.opm\""
            exit 1
        fi

    # ===========================================================================
    # CI/BUILD-ONLY MODE (--no-install flag)
    # No root or su required - just builds the .opm file
    # ===========================================================================
    else
        echo ""
        echo "Package built but not installed (--no-install flag was used)"

        # Determine correct install command for manual installation hint
        # - Admin::Package::Install  = package not currently installed
        # - Admin::Package::Upgrade  = package already installed
        # Note: This check may fail in CI (no su access), defaults to Install
        INSTALL_CMD="Admin::Package::Install"
        if PACKAGE_STATUS=$(su $ZNUNY_USER -c "cd $ZNUNY_HOME/bin && ./otrs.Console.pl Admin::Package::List" 2>/dev/null | grep -c "MSSTLite"); then
            if [ "$PACKAGE_STATUS" -gt 0 ]; then
                INSTALL_CMD="Admin::Package::Upgrade"
            fi
        fi

        echo "To install manually, run:"
        echo "su $ZNUNY_USER -c \"cd $ZNUNY_HOME/bin && ./otrs.Console.pl $INSTALL_CMD $PWD/MSSTLite-${VERSION}.opm\""
    fi
else
    echo ""
    echo "✗ Package build failed!"
    exit 1
fi
