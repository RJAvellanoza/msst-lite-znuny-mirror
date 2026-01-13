#!/bin/bash
set -e

# Define variables
# Set these variables according to your environment
ZNUNY_ROOT="${ZNUNY_ROOT:-/path/to/znuny}"
PROJECT_ROOT="${PROJECT_ROOT:-/path/to/msst-lite-znuny}"
ZNUNY_USER="znuny"
LOG_FILE="/tmp/msst_install_test_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="/tmp/msst_install_errors_$(date +%Y%m%d_%H%M%S).log"

echo "=== MSSTLite Package Installation Test ==="
echo "Log file: $LOG_FILE"
echo "Error log: $ERROR_LOG"
echo ""

# Function to run commands as znuny user
run_as_znuny() {
    su -c "$1" -s /bin/bash $ZNUNY_USER
}

# Step 1: Cleanup - Uninstall existing package
echo "Step 1: Cleaning up existing installation..."
run_as_znuny "$ZNUNY_ROOT/bin/otrs.Console.pl Admin::Package::Uninstall MSSTLite" &>> $LOG_FILE || true
echo "   Done."

# Clear any manual configurations from ZZZAAuto.pm
sed -i '/MSSTLite License Check/,+2d' $ZNUNY_ROOT/Kernel/Config/Files/ZZZAAuto.pm 2>/dev/null || true

# Step 2: Build package
echo "Step 2: Building package..."
cd $PROJECT_ROOT
# Prepare files for building
./prepare_build.sh
# Build using Znuny's package builder with our module directory
run_as_znuny "$ZNUNY_ROOT/bin/otrs.Console.pl Dev::Package::Build --module-directory=$PROJECT_ROOT $PROJECT_ROOT/MSSTLite.sopm $PROJECT_ROOT" &>> $LOG_FILE
if [ $? -ne 0 ]; then
    echo "FAILURE: Package build failed"
    cat $LOG_FILE
    exit 1
fi
echo "   Done."

# Find the latest .opm file
LATEST_OPM=$(ls -t MSSTLite-*.opm 2>/dev/null | head -1)
if [ -z "$LATEST_OPM" ]; then
    echo "FAILURE: No .opm file found after build"
    exit 1
fi
echo "   Built: $LATEST_OPM"

# Step 3: Install package
echo "Step 3: Installing package..."
run_as_znuny "$ZNUNY_ROOT/bin/otrs.Console.pl Admin::Package::Install $PROJECT_ROOT/$LATEST_OPM" &>> $LOG_FILE 2>&1
INSTALL_EXIT_CODE=$?
echo "   Install exit code: $INSTALL_EXIT_CODE"

# Capture the timestamp for log checking
INSTALL_TIMESTAMP=$(date +"%Y-%m-%d %H:%M")

# Step 4: Verification
echo ""
echo "Step 4: Verifying installation..."

# Check 1: Configuration deployment
echo -n "   Checking configuration deployment... "
if grep -q "PreApplicationModule.*Kernel::Modules::PreApplicationLicenseCheck" $ZNUNY_ROOT/Kernel/Config/Files/ZZZAAuto.pm; then
    echo "FOUND"
    CONFIG_CHECK="PASS"
    # Show the actual configuration line
    grep "PreApplicationModule.*Kernel::Modules::PreApplicationLicenseCheck" $ZNUNY_ROOT/Kernel/Config/Files/ZZZAAuto.pm | head -1
else
    echo "NOT FOUND"
    CONFIG_CHECK="FAIL"
fi

# Check 2: License check enabled
echo -n "   Checking LicenseCheck::Enabled... "
if grep -q "LicenseCheck::Enabled.*=.*'1'" $ZNUNY_ROOT/Kernel/Config/Files/ZZZAAuto.pm; then
    echo "FOUND"
    LICENSE_ENABLED_CHECK="PASS"
else
    echo "NOT FOUND"
    LICENSE_ENABLED_CHECK="FAIL"
fi

# Check 3: Installation errors
echo -n "   Checking for installation errors... "
# Extract errors from the installation log
grep -i "error" $LOG_FILE | grep -v "ErrorScreen" > $ERROR_LOG 2>/dev/null || true
if [ -s $ERROR_LOG ]; then
    echo "ERRORS FOUND:"
    cat $ERROR_LOG
    ERROR_CHECK="FAIL"
else
    echo "NONE"
    ERROR_CHECK="PASS"
fi

# Check 4: Module file exists
echo -n "   Checking PreApplication module file... "
if [ -f "$ZNUNY_ROOT/Kernel/Modules/PreApplicationLicenseCheck.pm" ]; then
    echo "EXISTS"
    MODULE_FILE_CHECK="PASS"
else
    echo "MISSING"
    MODULE_FILE_CHECK="FAIL"
fi

# Step 5: Report results
echo ""
echo "=== TEST RESULTS ==="
echo "Configuration deployed: $CONFIG_CHECK"
echo "License check enabled: $LICENSE_ENABLED_CHECK"
echo "No installation errors: $ERROR_CHECK"
echo "Module file exists: $MODULE_FILE_CHECK"
echo ""

# Overall result
if [ "$CONFIG_CHECK" = "PASS" ] && [ "$LICENSE_ENABLED_CHECK" = "PASS" ] && [ "$ERROR_CHECK" = "PASS" ] && [ "$MODULE_FILE_CHECK" = "PASS" ]; then
    echo "SUCCESS: Configuration deployed correctly."
    echo ""
    echo "Testing actual functionality..."
    # Restart Apache to ensure new config is loaded
    systemctl restart apache2
    sleep 2
    
    # Check if debug log is created (indicates module is running)
    if [ -f "/tmp/preapp_debug.log" ]; then
        echo "PreApplication module debug log found - module is executing"
        tail -5 /tmp/preapp_debug.log
    else
        echo "Warning: PreApplication module debug log not found - module may not be executing"
    fi
    exit 0
else
    echo "FAILURE: Configuration not deployed or errors found."
    echo ""
    echo "=== INSTALLATION LOG (last 50 lines) ==="
    tail -50 $LOG_FILE
    echo ""
    
    # Check for specific known issues
    if grep -q "null value in column 'effective_value'" $LOG_FILE; then
        echo "=== KNOWN ISSUE DETECTED: XML configuration has invalid value ==="
        echo "One or more settings in the XML files have no default value."
    fi
    
    if grep -q "Module.*not registered" $LOG_FILE; then
        echo "=== KNOWN ISSUE DETECTED: Module registration failure ==="
        echo "The PreApplication module is causing framework initialization issues."
    fi
    
    exit 1
fi