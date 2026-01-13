#!/bin/bash
# Test script for SMTP Notification feature

echo "SMTP Notification Test Script"
echo "============================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Detect Znuny installation directory
ZNUNY_DIR="/opt/znuny"
if [ -d "${ZNUNY_ROOT:-/path/to/znuny}" ]; then
    ZNUNY_DIR="${ZNUNY_ROOT:-/path/to/znuny}"
elif [ -d "/opt/znuny-6.5.14" ]; then
    ZNUNY_DIR="/opt/znuny-6.5.14"
fi

echo "Using Znuny directory: $ZNUNY_DIR"
echo ""

# Step 1: Check Perl modules
echo "1. Checking required Perl modules..."
su - znuny -c "perl -e 'use Net::SMTP; print \"Net::SMTP: OK\n\"'" 2>/dev/null || echo "Net::SMTP: MISSING"
su - znuny -c "perl -e 'use Net::SMTP::SSL; print \"Net::SMTP::SSL: OK\n\"'" 2>/dev/null || echo "Net::SMTP::SSL: MISSING"
echo ""

# Step 2: Check module syntax
echo "2. Checking module syntax..."
for module in Custom/Kernel/Modules/AdminSMTPNotification.pm \
              Custom/Kernel/System/Ticket/Event/SMTPNotification.pm; do
    if [ -f "$module" ]; then
        perl -c "$module" 2>&1 | grep -E "(syntax OK|error)"
    fi
done
echo ""

# Step 3: Check configuration files
echo "3. Checking configuration files..."
if [ -f "Custom/Kernel/Config/Files/XML/SMTPNotification.xml" ]; then
    echo "SMTPNotification.xml: Found"
    xmllint --noout Custom/Kernel/Config/Files/XML/SMTPNotification.xml 2>&1 && echo "XML Syntax: OK" || echo "XML Syntax: ERROR"
else
    echo "SMTPNotification.xml: NOT FOUND"
fi
echo ""

# Step 4: Check template file
echo "4. Checking template file..."
if [ -f "Custom/Kernel/Output/HTML/Templates/Standard/AdminSMTPNotification.tt" ]; then
    echo "AdminSMTPNotification.tt: Found"
else
    echo "AdminSMTPNotification.tt: NOT FOUND"
fi
echo ""

# Step 5: Apply configuration if in dev mode
if [ -L "$ZNUNY_DIR/Custom" ]; then
    echo "5. Development mode detected. Rebuilding configuration..."
    su - znuny -c "$ZNUNY_DIR/bin/otrs.Console.pl Maint::Config::Rebuild"
    su - znuny -c "$ZNUNY_DIR/bin/otrs.Console.pl Maint::Cache::Delete"
    echo ""
fi

# Step 6: Test URLs
echo "6. Testing module access..."
echo "Admin module URL: http://localhost/otrs/index.pl?Action=AdminSMTPNotification"
echo ""

# Step 7: Configuration check
echo "7. Checking SMTP configuration in database..."
su - znuny -c "$ZNUNY_DIR/bin/otrs.Console.pl Admin::Config::Read --setting-name SMTPNotification::Enabled" 2>/dev/null || echo "Setting not found (this is normal before first save)"
echo ""

echo "Test complete!"
echo ""
echo "Next steps:"
echo "1. Access the Admin interface"
echo "2. Navigate to Admin -> System -> SMTP Notification"
echo "3. Configure SMTP settings"
echo "4. Create a test ticket to verify notifications"