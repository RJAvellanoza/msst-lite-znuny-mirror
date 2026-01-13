#!/bin/bash

# LSMP Znuny Setup Script
# This script creates necessary symlinks for the custom modules

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to find Znuny installation
find_znuny_path() {
    # Common Znuny/OTRS installation paths
    local common_paths=(
        "/opt/znuny"
        "/opt/otrs"
        "/usr/local/znuny"
        "/usr/local/otrs"
        "/var/lib/znuny"
        "/var/lib/otrs"
    )
    
    for path in "${common_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/bin/otrs.Console.pl" ]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Handle uninstall option
if [ "$1" == "--uninstall" ]; then
    ZNUNY_PATH=$(find_znuny_path)
    if [ -z "$ZNUNY_PATH" ]; then
        echo -e "${RED}Error: Could not find Znuny installation${NC}"
        exit 1
    fi
    
    if [ -L "$ZNUNY_PATH/Custom" ]; then
        rm "$ZNUNY_PATH/Custom"
        echo -e "${GREEN}✓ Removed symlink: $ZNUNY_PATH/Custom${NC}"
    else
        echo -e "${YELLOW}No symlink found at $ZNUNY_PATH/Custom${NC}"
    fi
    exit 0
fi

# Try to find Znuny installation automatically
ZNUNY_PATH=""

# Check if custom path is provided
if [ ! -z "$1" ]; then
    ZNUNY_PATH="$1"
else
    # Try to auto-detect
    ZNUNY_PATH=$(find_znuny_path)
    
    if [ -z "$ZNUNY_PATH" ]; then
        echo -e "${YELLOW}Could not auto-detect Znuny installation path.${NC}"
        echo "Please enter the full path to your Znuny installation:"
        read -r ZNUNY_PATH
    else
        echo -e "${GREEN}Auto-detected Znuny installation at: $ZNUNY_PATH${NC}"
        echo "Press Enter to continue or type a different path:"
        read -r custom_path
        if [ ! -z "$custom_path" ]; then
            ZNUNY_PATH="$custom_path"
        fi
    fi
fi

echo "Setting up LSMP custom modules..."
echo "Znuny installation path: $ZNUNY_PATH"

echo ""
echo "Checking required Perl modules..."

# Check and install required Perl modules
MISSING_MODULES=""
for module in "Crypt::CBC" "Crypt::Rijndael" "Net::SMTP" "Net::SMTP::SSL"; do
    if ! perl -e "use $module" 2>/dev/null; then
        MISSING_MODULES="$MISSING_MODULES $module"
        echo -e "${YELLOW}Missing Perl module: $module${NC}"
    else
        echo -e "${GREEN}✓ Found Perl module: $module${NC}"
    fi
done

if [ ! -z "$MISSING_MODULES" ]; then
    echo ""
    echo "Installing missing Perl modules..."
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        # Running as root, no need for sudo
        if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            apt-get update -qq
            apt-get install -y libcrypt-cbc-perl libcrypt-rijndael-perl libnet-smtp-ssl-perl
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Perl modules installed successfully${NC}"
            else
                echo -e "${RED}Error: Failed to install Perl modules${NC}"
                echo "Please install manually: libcrypt-cbc-perl libcrypt-rijndael-perl libnet-smtp-ssl-perl"
                exit 1
            fi
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS
            yum install -y perl-Crypt-CBC perl-Crypt-Rijndael perl-Net-SMTP-SSL
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Perl modules installed successfully${NC}"
            else
                echo -e "${RED}Error: Failed to install Perl modules${NC}"
                echo "Please install manually: perl-Crypt-CBC perl-Crypt-Rijndael perl-Net-SMTP-SSL"
                exit 1
            fi
        else
            echo -e "${RED}Error: Could not detect package manager${NC}"
            echo "Please install the following Perl modules manually:"
            echo "  - Crypt::CBC"
            echo "  - Crypt::Rijndael"
            echo "  - Net::SMTP"
            echo "  - Net::SMTP::SSL"
            exit 1
        fi
    else
        # Not running as root, use sudo
        if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            sudo apt-get update -qq
            sudo apt-get install -y libcrypt-cbc-perl libcrypt-rijndael-perl libnet-smtp-ssl-perl
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Perl modules installed successfully${NC}"
            else
                echo -e "${RED}Error: Failed to install Perl modules${NC}"
                echo "Please install manually: libcrypt-cbc-perl libcrypt-rijndael-perl libnet-smtp-ssl-perl"
                exit 1
            fi
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS
            sudo yum install -y perl-Crypt-CBC perl-Crypt-Rijndael perl-Net-SMTP-SSL
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Perl modules installed successfully${NC}"
            else
                echo -e "${RED}Error: Failed to install Perl modules${NC}"
                echo "Please install manually: perl-Crypt-CBC perl-Crypt-Rijndael perl-Net-SMTP-SSL"
                exit 1
            fi
        else
            echo -e "${RED}Error: Could not detect package manager${NC}"
            echo "Please install the following Perl modules manually:"
            echo "  - Crypt::CBC"
            echo "  - Crypt::Rijndael"
            echo "  - Net::SMTP"
            echo "  - Net::SMTP::SSL"
            exit 1
        fi
    fi
fi

# Check if Znuny installation exists
if [ ! -d "$ZNUNY_PATH" ] || [ ! -f "$ZNUNY_PATH/bin/otrs.Console.pl" ]; then
    echo -e "${RED}Error: Valid Znuny installation not found at $ZNUNY_PATH${NC}"
    echo "Please make sure the path contains bin/otrs.Console.pl"
    exit 1
fi

# Get the repository path (where this script is located)
REPO_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "Repository path: $REPO_PATH"

# Function to create symlink
create_symlink() {
    local source="$1"
    local target="$2"
    
    # Remove existing symlink or file
    if [ -L "$target" ] || [ -e "$target" ]; then
        echo -e "${YELLOW}Removing existing: $target${NC}"
        rm -rf "$target"
    fi
    
    # Create directory if needed
    local target_dir=$(dirname "$target")
    if [ ! -d "$target_dir" ]; then
        echo "Creating directory: $target_dir"
        mkdir -p "$target_dir"
    fi
    
    # Create symlink
    ln -s "$source" "$target"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Linked: $source -> $target${NC}"
    else
        echo -e "${RED}✗ Failed to link: $source -> $target${NC}"
        exit 1
    fi
}

echo ""
echo "Creating symlinks for Custom modules..."

# Symlink the entire Custom directory
create_symlink "$REPO_PATH/Custom" "$ZNUNY_PATH/Custom"

echo ""
echo "Checking Znuny version compatibility..."

# Check if this is Znuny 6.5.x which needs Perl config files
if [ -f "$ZNUNY_PATH/RELEASE" ] && grep -q "VERSION = 6\.5" "$ZNUNY_PATH/RELEASE"; then
    echo "Detected Znuny 6.5.x - Creating compatibility configuration..."
    
    # Create the Perl config file if it doesn't exist
    if [ ! -f "$REPO_PATH/Custom/Kernel/Config/Files/ZZZAdminLicense.pm" ]; then
        cat > "$REPO_PATH/Custom/Kernel/Config/Files/ZZZAdminLicense.pm" <<'EOF'
# --
# Custom configuration for Admin License Module
# --

package Kernel::Config::Files::ZZZAdminLicense;

use strict;
use warnings;
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # Register MSSTLite block for admin overview
    $Self->{'Frontend::AdminModuleGroups'}->{'001-Framework'}->{'MSSTLite'} = {
        'Title' => 'LSMP Configuration',
        'Order' => 50,  # Low number = appears at top
    };

    # Admin License Navigation Module
    $Self->{'Frontend::NavigationModule'}->{'AdminAddLicense'} = {
        'Group' => [
            'admin',
            'NOCAdmin'
        ],
        'GroupRo' => [],
        'Module' => 'Kernel::Output::HTML::NavBar::ModuleAdmin',
        'Name' => 'Add License',
        'Block' => 'MSSTLite',
        'Description' => 'Add License',
        'IconBig' => 'fa-id-card-o',
        'IconSmall' => 'fa-building-o',
        'Prio' => '10',
    };

    # Admin License Frontend Module
    $Self->{'Frontend::Module'}->{'AdminAddLicense'} = {
        'GroupRo' => [],
        'Group' => [
            'admin',
            'NOCAdmin'
        ],
        'Description' => 'Add License.',
        'Title' => 'Add License',
        'NavBarName' => 'Admin',
    };

    # User Details Preferences
    $Self->{'PreferencesGroups'}->{'UserDetails'} = {
        'Module' => 'Kernel::Output::HTML::Preferences::UserDetails',
        'PreferenceGroup' => 'UserProfile',
        'Label' => 'User Details',
        'Key' => 'User Details',
        'Desc' => 'Change your details.',
        'Block' => 'User Details',
        'Prio' => '1001',
        'Active' => '1',
    };

    return 1;
}

1;
EOF
        echo -e "${GREEN}✓ Created compatibility configuration for Znuny 6.5.x${NC}"
    fi
fi

echo ""
echo "Rebuilding configuration..."

# Detect the Znuny user
ZNUNY_USER="otrs"
if ! id "$ZNUNY_USER" &>/dev/null; then
    ZNUNY_USER="znuny"
    if ! id "$ZNUNY_USER" &>/dev/null; then
        ZNUNY_USER=$(stat -c '%U' "$ZNUNY_PATH/bin/otrs.Console.pl" 2>/dev/null || echo "")
    fi
fi

if [ ! -z "$ZNUNY_USER" ] && id "$ZNUNY_USER" &>/dev/null; then
    su - "$ZNUNY_USER" -c "cd $ZNUNY_PATH && $ZNUNY_PATH/bin/otrs.Console.pl Maint::Config::Rebuild"
    echo -e "${GREEN}✓ Configuration rebuilt${NC}"
    
    echo ""
    echo "Clearing cache..."
    su - "$ZNUNY_USER" -c "cd $ZNUNY_PATH && $ZNUNY_PATH/bin/otrs.Console.pl Maint::Cache::Delete"
    echo -e "${GREEN}✓ Cache cleared${NC}"
    
    echo ""
    echo "Restarting Apache..."
    if systemctl restart apache2 2>/dev/null; then
        echo -e "${GREEN}✓ Apache restarted${NC}"
    elif systemctl restart httpd 2>/dev/null; then
        echo -e "${GREEN}✓ Apache restarted${NC}"
    else
        echo -e "${YELLOW}Warning: Could not restart Apache automatically${NC}"
        echo "Please restart your web server manually"
    fi
else
    echo -e "${YELLOW}Warning: Could not determine Znuny user${NC}"
    echo "Please run these commands manually:"
    echo "  $ZNUNY_PATH/bin/otrs.Console.pl Maint::Config::Rebuild"
    echo "  $ZNUNY_PATH/bin/otrs.Console.pl Maint::Cache::Delete"
    echo "  systemctl restart apache2"
fi

echo ""
echo -e "${GREEN}Setup completed successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Apply database changes:"
echo "   The adminlicense-db.xml file contains the database schema for the license table"
echo "   This should be applied through Znuny's package management system"
echo ""
echo "2. Access the Admin interface to configure the new modules"
echo ""
echo "To remove symlinks, run: $0 --uninstall"
