#!/bin/bash
# Build Package Script for MSSTLite
# Version: 3.0 (2025-11-24)
#
# This script:
# 1. Copies files from Custom/ to proper Kernel/ structure
# 2. Builds the package using Znuny's Dev::Package::Build
# 3. Automatically installs the package (unless --no-install is specified)
#
# Usage: ./build-package.sh [OPTIONS]
#   --no-install    Build only, don't install
#   -y, --yes       Non-interactive mode (auto-confirm prompts)
#   -h, --help      Show this help

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Global for error handling
BUILD_OUTPUT_FILE=""

# Cleanup function for errors
cleanup_on_error() {
    local exit_code=$?
    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}Build FAILED (exit code: $exit_code)${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"

    # Show build output if available
    if [ -n "$BUILD_OUTPUT_FILE" ] && [ -f "$BUILD_OUTPUT_FILE" ]; then
        echo ""
        echo -e "${YELLOW}Build output (last 50 lines):${NC}"
        echo "---------------------------------------------------------------"
        tail -50 "$BUILD_OUTPUT_FILE" 2>/dev/null || true
        echo "---------------------------------------------------------------"
        rm -f "$BUILD_OUTPUT_FILE" 2>/dev/null || true
    fi

    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    rm -rf Kernel/ var/ bin/ 2>/dev/null || true
    # Clean up any symlinks we created
    if [ -n "$ZNUNY_HOME" ]; then
        find "$ZNUNY_HOME/Kernel" -type l -delete 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Parse command line arguments
AUTO_INSTALL=true
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-install)
            AUTO_INSTALL=false
            shift
            ;;
        -y|--yes)
            NON_INTERACTIVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-install    Build only, don't install"
            echo "  -y, --yes       Non-interactive mode (auto-confirm prompts)"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

echo "Running pre-flight checks..."

# Check if we can write to Znuny directories (checked later after ZNUNY_HOME is set)

# Check working directory - must contain MSSTLite.sopm and Custom/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "MSSTLite.sopm" ]; then
    echo -e "${RED}ERROR: MSSTLite.sopm not found in $SCRIPT_DIR${NC}"
    echo "This script must be run from the msst-lite-znuny repository root"
    exit 1
fi
echo -e "${GREEN}✓${NC} Found MSSTLite.sopm"

if [ ! -d "Custom" ]; then
    echo -e "${RED}ERROR: Custom/ directory not found${NC}"
    echo "This script must be run from the msst-lite-znuny repository root"
    exit 1
fi
echo -e "${GREEN}✓${NC} Found Custom/ directory"

# Detect Znuny installation directory
ZNUNY_HOME=""
for dir in "/opt/znuny-6.5.15" "/opt/znuny" "/opt/otrs"; do
    if [ -d "$dir" ] && [ -f "$dir/bin/otrs.Console.pl" ]; then
        ZNUNY_HOME="$dir"
        break
    fi
done

if [ -z "$ZNUNY_HOME" ]; then
    echo -e "${RED}ERROR: Could not find Znuny installation directory${NC}"
    echo "Checked: /opt/znuny-6.5.15, /opt/znuny, /opt/otrs"
    exit 1
fi
echo -e "${GREEN}✓${NC} Found Znuny installation: $ZNUNY_HOME"

# Detect the Znuny user - check multiple methods
ZNUNY_USER=""

# Method 1: Check for common user names
for user in "otrs" "znuny"; do
    if id "$user" &>/dev/null; then
        ZNUNY_USER="$user"
        break
    fi
done

# Method 2: Get owner of otrs.Console.pl
if [ -z "$ZNUNY_USER" ]; then
    ZNUNY_USER=$(stat -c '%U' "$ZNUNY_HOME/bin/otrs.Console.pl" 2>/dev/null || echo "")
fi

# Method 3: Get owner of Kernel directory
if [ -z "$ZNUNY_USER" ] || ! id "$ZNUNY_USER" &>/dev/null; then
    ZNUNY_USER=$(stat -c '%U' "$ZNUNY_HOME/Kernel" 2>/dev/null || echo "")
fi

# Validate we found a valid user
if [ -z "$ZNUNY_USER" ]; then
    echo -e "${RED}ERROR: Could not detect Znuny user${NC}"
    echo "Neither 'otrs' nor 'znuny' user exists, and could not determine owner"
    exit 1
fi

if ! id "$ZNUNY_USER" &>/dev/null; then
    echo -e "${RED}ERROR: Detected user '$ZNUNY_USER' does not exist${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Detected Znuny user: $ZNUNY_USER"

# Determine how to run commands as ZNUNY_USER
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" = "$ZNUNY_USER" ]; then
    # Already running as znuny user
    RUN_AS_ZNUNY=""
    echo -e "${GREEN}✓${NC} Running as $ZNUNY_USER user"
elif [ "$EUID" -eq 0 ]; then
    # Running as root, use runuser
    RUN_AS_ZNUNY="runuser -u $ZNUNY_USER --"
    echo -e "${GREEN}✓${NC} Running as root (will use runuser for $ZNUNY_USER)"
else
    # Running as different user, check if we can sudo
    if sudo -n -u "$ZNUNY_USER" true 2>/dev/null; then
        RUN_AS_ZNUNY="sudo -u $ZNUNY_USER"
        echo -e "${GREEN}✓${NC} Running as $CURRENT_USER (will use sudo for $ZNUNY_USER)"
    else
        echo -e "${RED}ERROR: Cannot run commands as $ZNUNY_USER${NC}"
        echo "Please run this script as:"
        echo "  1. The $ZNUNY_USER user: su - $ZNUNY_USER -c '$0'"
        echo "  2. Root: sudo $0"
        echo "  3. A user with passwordless sudo to $ZNUNY_USER"
        exit 1
    fi
fi

# Check write permissions to Znuny directory
if [ -n "$RUN_AS_ZNUNY" ]; then
    if ! $RUN_AS_ZNUNY test -w "$ZNUNY_HOME/Kernel"; then
        echo -e "${RED}ERROR: Cannot write to $ZNUNY_HOME/Kernel${NC}"
        exit 1
    fi
else
    if [ ! -w "$ZNUNY_HOME/Kernel" ]; then
        echo -e "${RED}ERROR: Cannot write to $ZNUNY_HOME/Kernel${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓${NC} Write access to $ZNUNY_HOME verified"

# Detect web group
WEB_GROUP="www-data"
if ! getent group "$WEB_GROUP" &>/dev/null; then
    WEB_GROUP="apache"
    if ! getent group "$WEB_GROUP" &>/dev/null; then
        WEB_GROUP=$(stat -c '%G' "$ZNUNY_HOME/var/httpd" 2>/dev/null || echo "www-data")
    fi
fi
echo -e "${GREEN}✓${NC} Using web group: $WEB_GROUP"

echo ""

# ============================================================================
# TEMPLATE VALIDATION
# ============================================================================

if [ -f "./dev/tools/validate-templates.sh" ]; then
    echo "Running template validation..."
    if ./dev/tools/validate-templates.sh; then
        echo -e "${GREEN}✓${NC} Template validation passed"
    else
        echo -e "${RED}Template validation failed - aborting build${NC}"
        exit 1
    fi
    echo ""
fi

# ============================================================================
# PREPARE BUILD FILES
# ============================================================================

echo "Preparing files for package build..."

# Clean old build files to prevent stale file issues
echo "Cleaning old build files..."
rm -rf Kernel/ var/ bin/

# Create directory structure
mkdir -p Kernel/Config/Files/XML
mkdir -p Kernel/Language
mkdir -p Kernel/Modules
mkdir -p Kernel/System/Ticket/Event
mkdir -p Kernel/System/GenericAgent
mkdir -p Kernel/System/Console/Command
mkdir -p Kernel/GenericInterface/Invoker/TwilioSMS
mkdir -p Kernel/GenericInterface/Operation/Incident
mkdir -p Kernel/Output/HTML/FilterContent
mkdir -p Kernel/Output/HTML/Notification
mkdir -p Kernel/Output/HTML/Preferences
mkdir -p Kernel/Output/HTML/Dashboard
mkdir -p Kernel/Output/HTML/Layout
mkdir -p Kernel/Output/HTML/Templates/Standard

# Copy configuration files
echo "Copying configuration files..."
cp Custom/Kernel/Config/Files/*.pm Kernel/Config/Files/ 2>/dev/null || true
cp Custom/Kernel/Config/Files/XML/*.xml Kernel/Config/Files/XML/ 2>/dev/null || true

# Copy language files
echo "Copying language files..."
cp Custom/Kernel/Language/*.pm Kernel/Language/ 2>/dev/null || true

# Copy module files
echo "Copying module files..."
cp Custom/Kernel/Modules/*.pm Kernel/Modules/ 2>/dev/null || true

# Copy system files
echo "Copying system files..."
cp Custom/Kernel/System/*.pm Kernel/System/ 2>/dev/null || true
cp -r Custom/Kernel/System/Ticket/* Kernel/System/Ticket/ 2>/dev/null || true
cp Custom/Kernel/System/GenericAgent/*.pm Kernel/System/GenericAgent/ 2>/dev/null || true
cp Custom/Kernel/System/Console/Command/*.pm Kernel/System/Console/Command/ 2>/dev/null || true

# Copy GenericInterface files
echo "Copying GenericInterface modules..."
cp Custom/Kernel/GenericInterface/*.pm Kernel/GenericInterface/ 2>/dev/null || true
cp Custom/Kernel/GenericInterface/Invoker/TwilioSMS/*.pm Kernel/GenericInterface/Invoker/TwilioSMS/ 2>/dev/null || true
cp Custom/Kernel/GenericInterface/Operation/Incident/*.pm Kernel/GenericInterface/Operation/Incident/ 2>/dev/null || true

# Copy output modules
echo "Copying output modules..."
cp Custom/Kernel/Output/HTML/FilterContent/*.pm Kernel/Output/HTML/FilterContent/ 2>/dev/null || true
cp Custom/Kernel/Output/HTML/Notification/*.pm Kernel/Output/HTML/Notification/ 2>/dev/null || true
cp Custom/Kernel/Output/HTML/Preferences/*.pm Kernel/Output/HTML/Preferences/ 2>/dev/null || true
cp Custom/Kernel/Output/HTML/Dashboard/*.pm Kernel/Output/HTML/Dashboard/ 2>/dev/null || true
cp Custom/Kernel/Output/HTML/Layout/*.pm Kernel/Output/HTML/Layout/ 2>/dev/null || true

# Copy templates
echo "Copying template files..."
cp Custom/Kernel/Output/HTML/Templates/Standard/*.tt Kernel/Output/HTML/Templates/Standard/ 2>/dev/null || true

# Copy var files
echo "Copying var files..."
if [ -d "Custom/var/packagesetup" ]; then
    mkdir -p var/packagesetup
    cp -r Custom/var/packagesetup/* var/packagesetup/ 2>/dev/null || true
fi

if [ -d "Custom/var/webservices" ]; then
    mkdir -p var/webservices
    cp -r Custom/var/webservices/* var/webservices/ 2>/dev/null || true
fi

if [ -d "Custom/var/categories" ]; then
    mkdir -p var/categories
    cp Custom/var/categories/*.csv var/categories/ 2>/dev/null || true
fi

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

if [ -d "Custom/var/settings" ]; then
    mkdir -p var/settings
    cp Custom/var/settings/*.yaml var/settings/ 2>/dev/null || true
fi


# Copy bin files
if [ -d "Custom/bin" ]; then
    echo "Copying bin files..."
    mkdir -p bin
    cp Custom/bin/*.pl bin/ 2>/dev/null || true
    cp Custom/bin/*.sh bin/ 2>/dev/null || true
    cp Custom/bin/*.sql bin/ 2>/dev/null || true
    chmod 755 bin/*.pl 2>/dev/null || true
    chmod 755 bin/*.sh 2>/dev/null || true
    chmod 644 bin/*.sql 2>/dev/null || true
fi

echo -e "${GREEN}✓${NC} Files prepared for building"

# Fix permissions on copied files
chmod -R 644 Kernel/ 2>/dev/null || true
find Kernel/ -type d -exec chmod 755 {} \; 2>/dev/null || true

# ============================================================================
# VERIFY SOPM FILE LIST
# ============================================================================

echo ""
echo "Verifying SOPM file list..."
MISSING_FILES=()
while IFS= read -r line; do
    if [[ $line =~ Location=\"([^\"]+)\" ]]; then
        FILE_PATH="${BASH_REMATCH[1]}"
        if [ ! -f "$FILE_PATH" ]; then
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
    echo -e "${RED}ERROR: The following files listed in SOPM are missing:${NC}"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""
    echo "Build aborted!"
    exit 1
fi
echo -e "${GREEN}✓${NC} All files in SOPM verified"

# ============================================================================
# CHECK FOR UNLISTED FILES
# ============================================================================

echo "Checking for unlisted files..."
UNLISTED_FILES=()

# Get all files from SOPM
SOPM_FILES=()
while IFS= read -r line; do
    if [[ $line =~ Location=\"([^\"]+)\" ]]; then
        FILE_PATH="${BASH_REMATCH[1]}"
        SOPM_FILES+=("$FILE_PATH")
        SOPM_FILES+=("Custom/$FILE_PATH")
    fi
done < <(grep '<File' MSSTLite.sopm)

# Check Custom/Kernel files
while IFS= read -r file; do
    file="${file#./}"
    found=0
    for sopm_file in "${SOPM_FILES[@]}"; do
        if [ "$file" = "$sopm_file" ] || [ "$file" = "${sopm_file#Custom/}" ] || [ "Custom/$file" = "$sopm_file" ]; then
            found=1
            break
        fi
    done
    if [ $found -eq 0 ]; then
        if [[ ! "$file" =~ (\.git|\.docs|test/|\.swp$|~$|\.bak$) ]]; then
            UNLISTED_FILES+=("$file")
        fi
    fi
done < <(find Custom/Kernel -type f \( -name "*.pm" -o -name "*.tt" -o -name "*.xml" -o -name "*.yml" \) 2>/dev/null)

# Check Custom/var files
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
done < <(find Custom/var -type f \( -name "*.yml" -o -name "*.pm" -o -name "*.js" -o -name "*.css" \) 2>/dev/null)

if [ ${#UNLISTED_FILES[@]} -gt 0 ]; then
    echo -e "${YELLOW}WARNING: The following files exist but are NOT listed in SOPM:${NC}"
    for file in "${UNLISTED_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""

    if [ "$NON_INTERACTIVE" = true ]; then
        echo "Non-interactive mode: continuing anyway"
    else
        read -p "Continue with build anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Build aborted!"
            exit 1
        fi
    fi
else
    echo -e "${GREEN}✓${NC} All Custom files are listed in SOPM"
fi

# ============================================================================
# DEPLOY FILES TO ZNUNY
# ============================================================================

echo ""
echo "Copying files to Znuny installation..."

# Copy as the znuny user for proper ownership
if [ -n "$RUN_AS_ZNUNY" ]; then
    $RUN_AS_ZNUNY cp -rp Kernel/* "$ZNUNY_HOME/Kernel/"
    if [ -d "var" ]; then
        $RUN_AS_ZNUNY cp -rp var/* "$ZNUNY_HOME/var/"
    fi
else
    cp -rp Kernel/* "$ZNUNY_HOME/Kernel/"
    if [ -d "var" ]; then
        cp -rp var/* "$ZNUNY_HOME/var/"
    fi
fi

echo -e "${GREEN}✓${NC} Files copied to $ZNUNY_HOME"

# ============================================================================
# BUILD PACKAGE
# ============================================================================

# Get version from SOPM file
CURRENT_VERSION=$(grep '<Version>' MSSTLite.sopm | sed 's/.*<Version>\(.*\)<\/Version>.*/\1/')

# Parse version components
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"

if [ ${#VERSION_PARTS[@]} -eq 3 ]; then
    MAJOR="${VERSION_PARTS[0]}"
    MINOR="${VERSION_PARTS[1]}"
    BUILD="${VERSION_PARTS[2]}"
    BUILD=$((BUILD + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${BUILD}"
else
    echo -e "${RED}ERROR: Unexpected version format: $CURRENT_VERSION${NC}"
    echo "Expected format: MAJOR.MINOR.BUILD (e.g., 1.0.9)"
    exit 1
fi

# Build with current version first
VERSION=$CURRENT_VERSION

echo ""
echo "Building MSSTLite version $VERSION..."

# Create temporary symlinks (as znuny user for proper ownership)
for file in Kernel/Config/Files/*.pm; do
    if [ -f "$file" ]; then
        if [ -n "$RUN_AS_ZNUNY" ]; then
            $RUN_AS_ZNUNY ln -sf "$PWD/$file" "$ZNUNY_HOME/$file" 2>/dev/null || true
        else
            ln -sf "$PWD/$file" "$ZNUNY_HOME/$file" 2>/dev/null || true
        fi
    fi
done
for file in Kernel/Config/Files/XML/*.xml; do
    if [ -f "$file" ]; then
        if [ -n "$RUN_AS_ZNUNY" ]; then
            $RUN_AS_ZNUNY ln -sf "$PWD/$file" "$ZNUNY_HOME/$file" 2>/dev/null || true
        else
            ln -sf "$PWD/$file" "$ZNUNY_HOME/$file" 2>/dev/null || true
        fi
    fi
done

# Run the build - capture output to show errors clearly
BUILD_OUTPUT_FILE=$(mktemp)
set +e  # Temporarily disable exit on error to handle build failure gracefully
if [ -n "$RUN_AS_ZNUNY" ]; then
    $RUN_AS_ZNUNY "$ZNUNY_HOME/bin/otrs.Console.pl" Dev::Package::Build --module-directory "$PWD" "$PWD/MSSTLite.sopm" "$PWD" 2>&1 | tee "$BUILD_OUTPUT_FILE"
else
    "$ZNUNY_HOME/bin/otrs.Console.pl" Dev::Package::Build --module-directory "$PWD" "$PWD/MSSTLite.sopm" "$PWD" 2>&1 | tee "$BUILD_OUTPUT_FILE"
fi
BUILD_RESULT=${PIPESTATUS[0]}
set -e

# Clean up symlinks
find "$ZNUNY_HOME/Kernel" -type l -delete 2>/dev/null || true

# ============================================================================
# POST-BUILD
# ============================================================================

if [ $BUILD_RESULT -eq 0 ] && [ -f "MSSTLite-${VERSION}.opm" ]; then
    rm -f "$BUILD_OUTPUT_FILE" 2>/dev/null || true
    echo ""
    echo -e "${GREEN}✓ Package built successfully: MSSTLite-${VERSION}.opm${NC}"

    # Increment version in SOPM now that build succeeded
    echo "Updating SOPM version from $CURRENT_VERSION to $NEW_VERSION..."
    sed -i "s|<Version>$CURRENT_VERSION</Version>|<Version>$NEW_VERSION</Version>|" MSSTLite.sopm

    # Fix permissions (requires root)
    if [ "$EUID" -eq 0 ]; then
        echo "Fixing Znuny permissions..."
        "$ZNUNY_HOME/bin/otrs.SetPermissions.pl" --otrs-user="$ZNUNY_USER" --web-group="$WEB_GROUP"
        echo -e "${GREEN}✓${NC} Permissions fixed"
    else
        echo -e "${YELLOW}Skipping permission fix (requires root)${NC}"
    fi

    # Clean up temporary build directories
    echo "Cleaning up temporary files..."
    rm -rf Kernel/ var/ bin/
    echo -e "${GREEN}✓${NC} Cleanup complete"

    # Auto-install if enabled
    if [ "$AUTO_INSTALL" = true ]; then
        echo ""

        # Check if package is already installed
        if [ -n "$RUN_AS_ZNUNY" ]; then
            PACKAGE_STATUS=$($RUN_AS_ZNUNY "$ZNUNY_HOME/bin/otrs.Console.pl" Admin::Package::List 2>/dev/null | grep -c "MSSTLite" || true)
        else
            PACKAGE_STATUS=$("$ZNUNY_HOME/bin/otrs.Console.pl" Admin::Package::List 2>/dev/null | grep -c "MSSTLite" || true)
        fi

        if [ "$PACKAGE_STATUS" -gt 0 ]; then
            echo "Uninstalling existing package..."
            if [ -n "$RUN_AS_ZNUNY" ]; then
                UNINSTALL_RESULT=$($RUN_AS_ZNUNY "$ZNUNY_HOME/bin/otrs.Console.pl" Admin::Package::Uninstall MSSTLite 2>&1) && UNINSTALL_OK=true || UNINSTALL_OK=false
            else
                UNINSTALL_RESULT=$("$ZNUNY_HOME/bin/otrs.Console.pl" Admin::Package::Uninstall MSSTLite 2>&1) && UNINSTALL_OK=true || UNINSTALL_OK=false
            fi
            if [ "$UNINSTALL_OK" = true ]; then
                echo -e "${GREEN}✓${NC} Existing package uninstalled"
            else
                echo -e "${YELLOW}Warning: Failed to uninstall existing package, continuing anyway...${NC}"
            fi
            echo ""
        fi

        echo "Installing package..."
        if [ -n "$RUN_AS_ZNUNY" ]; then
            INSTALL_OK=$($RUN_AS_ZNUNY "$ZNUNY_HOME/bin/otrs.Console.pl" Admin::Package::Install "$PWD/MSSTLite-${VERSION}.opm" 2>&1) && INSTALL_SUCCESS=true || INSTALL_SUCCESS=false
        else
            INSTALL_OK=$("$ZNUNY_HOME/bin/otrs.Console.pl" Admin::Package::Install "$PWD/MSSTLite-${VERSION}.opm" 2>&1) && INSTALL_SUCCESS=true || INSTALL_SUCCESS=false
        fi
        if [ "$INSTALL_SUCCESS" = true ]; then
            echo ""
            echo -e "${GREEN}✓ Package installed successfully!${NC}"
        else
            echo ""
            echo -e "${RED}Package installation failed!${NC}"
            echo "You can manually install with:"
            echo "  su $ZNUNY_USER -c \"$ZNUNY_HOME/bin/otrs.Console.pl Admin::Package::Install $PWD/MSSTLite-${VERSION}.opm\""
            exit 1
        fi
    else
        echo ""
        echo "Package built but not installed (--no-install flag was used)"

        if [ -n "$RUN_AS_ZNUNY" ]; then
            PACKAGE_STATUS=$($RUN_AS_ZNUNY "$ZNUNY_HOME/bin/otrs.Console.pl" Admin::Package::List 2>/dev/null | grep -c "MSSTLite" || true)
        else
            PACKAGE_STATUS=$("$ZNUNY_HOME/bin/otrs.Console.pl" Admin::Package::List 2>/dev/null | grep -c "MSSTLite" || true)
        fi

        if [ "$PACKAGE_STATUS" -gt 0 ]; then
            INSTALL_CMD="Admin::Package::Upgrade"
        else
            INSTALL_CMD="Admin::Package::Install"
        fi

        echo "To install manually, run:"
        echo "  su $ZNUNY_USER -c \"$ZNUNY_HOME/bin/otrs.Console.pl $INSTALL_CMD $PWD/MSSTLite-${VERSION}.opm\""
    fi
else
    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}Package build FAILED!${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Build output (last 50 lines):${NC}"
    echo "---------------------------------------------------------------"
    tail -50 "$BUILD_OUTPUT_FILE" 2>/dev/null || echo "(no output captured)"
    echo "---------------------------------------------------------------"
    rm -f "$BUILD_OUTPUT_FILE" 2>/dev/null || true
    # Cleanup is handled by trap
    exit 1
fi
