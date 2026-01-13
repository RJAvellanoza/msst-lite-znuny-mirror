#!/bin/bash

set -e  # Exit on any error

echo "=== MSSTLite Ticket Prefix Fix Script ==="
echo "========================================="

# Find Znuny installation directory
ZNUNY_DIR=""
ZNUNY_USER=""

# Check common locations
for dir in /opt/znuny-* /opt/otrs-* /opt/znuny /opt/otrs; do
    if [ -d "$dir" ] && [ -f "$dir/bin/otrs.Console.pl" ]; then
        ZNUNY_DIR="$dir"
        break
    fi
done

if [ -z "$ZNUNY_DIR" ]; then
    echo "ERROR: Could not find Znuny installation directory!"
    echo "Searched in: /opt/znuny-*, /opt/otrs-*, /opt/znuny, /opt/otrs"
    exit 1
fi

echo "Found Znuny installation at: $ZNUNY_DIR"

# Detect Znuny user
if id "znuny" &>/dev/null; then
    ZNUNY_USER="znuny"
elif id "otrs" &>/dev/null; then
    ZNUNY_USER="otrs"
else
    echo "ERROR: Could not find znuny or otrs user!"
    exit 1
fi

echo "Using Znuny user: $ZNUNY_USER"

# Verify console command exists
if [ ! -f "$ZNUNY_DIR/bin/otrs.Console.pl" ]; then
    echo "ERROR: Console command not found at $ZNUNY_DIR/bin/otrs.Console.pl"
    exit 1
fi

echo ""
echo "Starting configuration fix..."
echo "-----------------------------"

# Function to run command as znuny user
run_as_znuny() {
    local cmd="$1"
    local desc="$2"
    
    echo ""
    echo ">> $desc"
    
    if ! su - "$ZNUNY_USER" -c "$cmd" 2>&1; then
        echo "WARNING: Command failed, but continuing..."
    fi
}

# 1. Update the ticket number generator setting
run_as_znuny \
    "$ZNUNY_DIR/bin/otrs.Console.pl Admin::Config::Update --setting-name 'Ticket::NumberGenerator' --value 'Kernel::System::Ticket::Number::AutoIncrementWithPrefix'" \
    "Setting ticket number generator to AutoIncrementWithPrefix"

# 2. Rebuild the configuration
run_as_znuny \
    "$ZNUNY_DIR/bin/otrs.Console.pl Maint::Config::Rebuild" \
    "Rebuilding system configuration"

# 3. Clear all caches
run_as_znuny \
    "$ZNUNY_DIR/bin/otrs.Console.pl Maint::Cache::Delete" \
    "Clearing all system caches"

# 3a. Create INC prefix for Incident type if it doesn't exist
echo ""
echo ">> Checking/Creating INC prefix for Incident tickets..."

# First check if Incident type exists and get its ID
TYPE_CHECK=$(PGPASSWORD=znuny123 psql -U znuny -d znuny -t -c "SELECT id FROM ticket_type WHERE name = 'Incident';" 2>/dev/null | tr -d ' ')

if [ -z "$TYPE_CHECK" ]; then
    echo "WARNING: Incident ticket type does not exist. It should be created by the package."
else
    echo "Found Incident type with ID: $TYPE_CHECK"
    
    # Check if prefix already exists
    PREFIX_EXISTS=$(PGPASSWORD=znuny123 psql -U znuny -d znuny -t -c "SELECT COUNT(*) FROM ticket_prefix WHERE type = $TYPE_CHECK;" 2>/dev/null | tr -d ' ')
    
    if [ "$PREFIX_EXISTS" = "0" ] || [ -z "$PREFIX_EXISTS" ]; then
        echo "Creating INC prefix for Incident type..."
        PGPASSWORD=znuny123 psql -U znuny -d znuny -c "INSERT INTO ticket_prefix (type, prefix, valid_id, create_time, create_by) VALUES ($TYPE_CHECK, 'INC', 1, NOW(), 1);" 2>/dev/null || echo "WARNING: Failed to create prefix"
    else
        echo "INC prefix already exists for Incident type"
    fi
fi

# 4. Stop daemon (if running)
echo ""
echo ">> Stopping Znuny daemon (if running)..."
su - "$ZNUNY_USER" -c "$ZNUNY_DIR/bin/otrs.Daemon.pl stop" 2>/dev/null || true
sleep 2

# 5. Start daemon
echo ">> Starting Znuny daemon..."
if ! su - "$ZNUNY_USER" -c "$ZNUNY_DIR/bin/otrs.Daemon.pl start" 2>&1; then
    echo "WARNING: Failed to start daemon, but continuing..."
fi

# 6. Restart Apache
echo ""
echo ">> Restarting Apache web server..."
if command -v systemctl &> /dev/null; then
    systemctl restart apache2 || systemctl restart httpd || echo "WARNING: Failed to restart Apache"
elif command -v service &> /dev/null; then
    service apache2 restart || service httpd restart || echo "WARNING: Failed to restart Apache"
else
    echo "WARNING: Could not restart Apache - no systemctl or service command found"
fi

# 7. Verify configuration
echo ""
echo ">> Verifying configuration..."
CURRENT_SETTING=$(su - "$ZNUNY_USER" -c "$ZNUNY_DIR/bin/otrs.Console.pl Admin::Config::Read --setting-name 'Ticket::NumberGenerator'" 2>/dev/null | grep -A1 "Setting:" | tail -1 || echo "UNKNOWN")

echo ""
echo "========================================="
echo "=== Configuration Fix Complete ==="
echo "========================================="
echo ""
echo "Current Ticket::NumberGenerator setting:"
echo "  $CURRENT_SETTING"
echo ""

if [[ "$CURRENT_SETTING" == *"AutoIncrementWithPrefix"* ]]; then
    echo "✓ SUCCESS: Ticket number generator is correctly set!"
    echo ""
    echo "New tickets should now be created with prefixes:"
    echo "  - Incident tickets: INC-0000001000"
    echo "  - Other types: Based on configured prefixes"
    echo ""
    echo "To test, create a new ticket with TypeID=2 (Incident)"
else
    echo "✗ WARNING: Configuration may not have been applied correctly"
    echo "  Please check the logs and try running the script again"
fi

echo ""
echo "Script completed at: $(date)"