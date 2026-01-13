#!/bin/bash
# --
# install-dependencies.sh - Install required Perl modules for MSSTLite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "MSSTLite Dependency Installer"
echo "============================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   echo "Please run: sudo $0"
   exit 1
fi

# Required Perl modules from SOPM
REQUIRED_MODULES=(
    "Crypt::CBC"
    "Crypt::Rijndael"
    "Net::SMTP"
    "Net::SMTP::SSL"
    "XML::LibXSLT"
)

# Additional system packages that might be needed
SYSTEM_PACKAGES=(
    "libxml2-dev"
    "libxslt1-dev"
    "libssl-dev"
    "cpanminus"
)

echo "Installing system dependencies..."
echo "---------------------------------"

# Detect package manager
if command -v apt-get &> /dev/null; then
    echo "Detected Debian/Ubuntu system"
    apt-get update
    for pkg in "${SYSTEM_PACKAGES[@]}"; do
        echo -n "Installing $pkg... "
        if apt-get install -y "$pkg" &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}⚠ (may already be installed)${NC}"
        fi
    done
elif command -v yum &> /dev/null; then
    echo "Detected RedHat/CentOS system"
    for pkg in "${SYSTEM_PACKAGES[@]}"; do
        # Translate package names for RedHat
        case $pkg in
            "libxml2-dev") rpm_pkg="libxml2-devel" ;;
            "libxslt1-dev") rpm_pkg="libxslt-devel" ;;
            "libssl-dev") rpm_pkg="openssl-devel" ;;
            *) rpm_pkg=$pkg ;;
        esac
        echo -n "Installing $rpm_pkg... "
        if yum install -y "$rpm_pkg" &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}⚠ (may already be installed)${NC}"
        fi
    done
else
    echo -e "${YELLOW}Warning: Could not detect package manager${NC}"
    echo "Please ensure libxml2, libxslt, and openssl development packages are installed"
fi

echo ""
echo "Installing Perl modules..."
echo "--------------------------"

# Check if cpanm is available
if ! command -v cpanm &> /dev/null; then
    echo "Installing cpanminus..."
    curl -L https://cpanmin.us | perl - --sudo App::cpanminus
fi

# Install Perl modules
for module in "${REQUIRED_MODULES[@]}"; do
    echo -n "Installing $module... "
    
    # Check if module is already installed
    if perl -M"$module" -e '' 2>/dev/null; then
        echo -e "${GREEN}✓ (already installed)${NC}"
    else
        # Try to install the module
        if cpanm --quiet --notest "$module" &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            echo -e "${RED}  Failed to install $module${NC}"
            echo "  Try running: cpanm --force $module"
        fi
    fi
done

echo ""
echo "Verifying installations..."
echo "--------------------------"

# Verify all modules
all_good=true
for module in "${REQUIRED_MODULES[@]}"; do
    echo -n "Checking $module... "
    if perl -M"$module" -e '' 2>/dev/null; then
        version=$(perl -M"$module" -e "print \$${module}::VERSION" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ (version: $version)${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        all_good=false
    fi
done

echo ""
if $all_good; then
    echo -e "${GREEN}✓ All dependencies installed successfully!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some dependencies failed to install${NC}"
    echo "Please check the errors above and install missing modules manually"
    exit 1
fi