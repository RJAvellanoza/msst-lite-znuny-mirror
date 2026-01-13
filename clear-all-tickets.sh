#!/bin/bash
# Script to clear all tickets from Znuny system
# This script uses the official Znuny console commands

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to find Znuny installation directory
find_znuny_home() {
    # Check common locations
    local search_paths=(
        "/opt/znuny-"*
        "/opt/otrs-"*
        "/opt/znuny"
        "/opt/otrs"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/Kernel/Config.pm" ]; then
            echo "$path"
            return 0
        fi
    done
    
    # If not found, return empty
    echo ""
    return 1
}

# Function to extract database config from Config.pm
extract_db_config() {
    local config_file="$1"
    local key="$2"
    
    # Use grep and sed for more robust extraction
    case "$key" in
        "DSN")
            grep "DatabaseDSN" "$config_file" | head -1 | sed "s/.*=[[:space:]]*[\"']\\([^\"']*\\)[\"'].*/\\1/"
            ;;
        "User")
            grep "DatabaseUser" "$config_file" | head -1 | sed "s/.*=[[:space:]]*[\"']\\([^\"']*\\)[\"'].*/\\1/"
            ;;
        "Pass")
            grep "DatabasePw" "$config_file" | head -1 | sed "s/.*=[[:space:]]*[\"']\\([^\"']*\\)[\"'].*/\\1/"
            ;;
        "Name")
            grep "Database[\"']" "$config_file" | grep -v "DatabaseHost\|DatabaseUser\|DatabasePw\|DatabaseDSN" | head -1 | sed "s/.*=[[:space:]]*[\"']\\([^\"']*\\)[\"'].*/\\1/"
            ;;
        "Host")
            grep "DatabaseHost" "$config_file" | head -1 | sed "s/.*=[[:space:]]*[\"']\\([^\"']*\\)[\"'].*/\\1/"
            ;;
    esac
}

# Find Znuny installation
echo "Searching for Znuny installation..."
ZNUNY_HOME=$(find_znuny_home)

if [ -z "$ZNUNY_HOME" ]; then
    echo -e "${RED}Error: Could not find Znuny installation directory!${NC}"
    echo "Please ensure Znuny is installed and Kernel/Config.pm exists."
    exit 1
fi

echo -e "${GREEN}Found Znuny installation at: $ZNUNY_HOME${NC}"

# Extract database configuration
CONFIG_FILE="$ZNUNY_HOME/Kernel/Config.pm"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Config.pm not found at $CONFIG_FILE${NC}"
    exit 1
fi

# Extract database credentials
DB_USER=$(extract_db_config "$CONFIG_FILE" "User")
DB_PASS=$(extract_db_config "$CONFIG_FILE" "Pass")
DB_NAME=$(extract_db_config "$CONFIG_FILE" "Name")
DB_HOST=$(extract_db_config "$CONFIG_FILE" "Host")
DB_DSN=$(extract_db_config "$CONFIG_FILE" "DSN")

# If we couldn't get all values, try to parse from DSN
if [ -z "$DB_NAME" ] || [ -z "$DB_HOST" ]; then
    # Parse database name and host from DSN
    # Format: DBI:Pg:dbname=znuny;host=localhost or DBI:mysql:database=otrs;host=localhost
    if [[ "$DB_DSN" =~ dbname=([^;]+) ]]; then
        DB_NAME="${BASH_REMATCH[1]}"
    elif [[ "$DB_DSN" =~ database=([^;]+) ]]; then
        DB_NAME="${BASH_REMATCH[1]}"
    fi
    
    # Extract host
    if [[ "$DB_DSN" =~ host=([^;]+) ]]; then
        DB_HOST="${BASH_REMATCH[1]}"
    else
        DB_HOST="localhost"  # Default to localhost if not specified
    fi
fi

# Validate we have all required values
if [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_NAME" ]; then
    echo -e "${RED}Error: Could not extract database configuration from Config.pm${NC}"
    echo "Found: User=$DB_USER, Name=$DB_NAME, Host=$DB_HOST"
    exit 1
fi

# Set default host if not found
[ -z "$DB_HOST" ] && DB_HOST="localhost"

# Determine database type from DSN
if [[ "$DB_DSN" =~ ^DBI:Pg: ]]; then
    DB_TYPE="postgresql"
elif [[ "$DB_DSN" =~ ^DBI:mysql: ]]; then
    DB_TYPE="mysql"
else
    echo -e "${RED}Error: Unknown database type in DSN: $DB_DSN${NC}"
    exit 1
fi

# Show extracted configuration
echo "Database configuration:"
echo "  Type: $DB_TYPE"
echo "  Host: $DB_HOST"
echo "  Name: $DB_NAME"
echo "  User: $DB_USER"
echo ""

# Znuny user (usually same as DB user, but can be different)
ZNUNY_USER="znuny"

# Function to run commands as znuny user
run_as_znuny() {
    if [ "$(whoami)" = "$ZNUNY_USER" ]; then
        eval "$1"
    else
        # Export variables for the subshell
        export DB_PASS DB_USER DB_NAME DB_HOST
        su - $ZNUNY_USER -c "$1"
    fi
}

# Check if running with --force flag
FORCE_MODE=false
if [ "$1" = "--force" ]; then
    FORCE_MODE=true
fi

# Warning and confirmation
if [ "$FORCE_MODE" = false ]; then
    echo -e "${YELLOW}WARNING: This script will DELETE ALL TICKETS from your Znuny system!${NC}"
    echo -e "${YELLOW}This action is IRREVERSIBLE!${NC}"
    echo ""
    read -p "Are you absolutely sure you want to delete ALL tickets? Type 'YES' to confirm: " CONFIRM

    if [ "$CONFIRM" != "YES" ]; then
        echo -e "${RED}Aborted. No tickets were deleted.${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Starting ticket deletion process...${NC}"

# Function to run database queries
run_db_query() {
    local query="$1"
    if [ "$DB_TYPE" = "postgresql" ]; then
        if [ "$(whoami)" = "$ZNUNY_USER" ]; then
            PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -t -c "$query" 2>/dev/null
        else
            su - $ZNUNY_USER -c "PGPASSWORD='$DB_PASS' psql -U '$DB_USER' -d '$DB_NAME' -h '$DB_HOST' -t -c \"$query\" 2>/dev/null"
        fi
    else
        if [ "$(whoami)" = "$ZNUNY_USER" ]; then
            mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" -sN -e "$query" 2>/dev/null
        else
            su - $ZNUNY_USER -c "mysql -u'$DB_USER' -p'$DB_PASS' -h'$DB_HOST' '$DB_NAME' -sN -e \"$query\" 2>/dev/null"
        fi
    fi
}

# Get list of all ticket IDs
echo "Fetching all ticket IDs..."
TICKET_IDS=$(run_db_query "SELECT id FROM ticket ORDER BY id;")

if [ -z "$TICKET_IDS" ]; then
    echo -e "${YELLOW}No tickets found in the system.${NC}"
    exit 0
fi

# Count total tickets
TOTAL=$(echo "$TICKET_IDS" | wc -w)
echo -e "${YELLOW}Found $TOTAL tickets to delete${NC}"

# Delete tickets using proper Znuny console command
COUNTER=0
FAILED=0

# Delete each ticket using proper Znuny console command
echo "Deleting tickets using Znuny console command..."
for TICKET_ID in $TICKET_IDS; do
    COUNTER=$((COUNTER + 1))
    
    # Progress indicator every 10 tickets
    if [ $((COUNTER % 10)) -eq 0 ]; then
        echo -ne "\rProgress: $COUNTER/$TOTAL tickets processed..."
    fi
    
    # Use proper Znuny console command to delete ticket
    run_as_znuny "$ZNUNY_HOME/bin/otrs.Console.pl Maint::Ticket::Delete --ticket-id $TICKET_ID" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo ""
echo -e "${GREEN}Ticket deletion complete!${NC}"
echo "Total processed: $TOTAL"
echo "Successfully deleted: $((COUNTER - FAILED))"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
fi

# Clean up cache
echo ""
echo "Cleaning up cache..."
run_as_znuny "$ZNUNY_HOME/bin/otrs.Console.pl Maint::Cache::Delete"

# Optional: Reset ticket counter
if [ "$FORCE_MODE" = false ]; then
    echo ""
    read -p "Do you want to reset the ticket counter to start from 1? (y/N): " RESET_COUNTER
else
    RESET_COUNTER="N"
fi

if [ "$RESET_COUNTER" = "y" ] || [ "$RESET_COUNTER" = "Y" ]; then
    echo "Resetting ticket counter..."
    
    # Reset the ticket_number_counter
    run_db_query "DELETE FROM ticket_number_counter;"
    
    # For systems using prefix-based counters
    run_db_query "UPDATE ticket_number_counter_prefix SET counter = 0;"
    
    # Also delete from our custom tables
    run_db_query "DELETE FROM incident_management;"
    run_db_query "DELETE FROM incident_work_notes;"
    run_db_query "DELETE FROM incident_resolution_notes;"
    
    echo -e "${GREEN}Ticket counter reset complete!${NC}"
fi

echo ""
echo -e "${GREEN}All done!${NC}"

# Show usage hint
if [ "$FORCE_MODE" = false ]; then
    echo ""
    echo "Tip: Use '$0 --force' to skip confirmation prompts"
fi
