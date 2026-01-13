#!/bin/bash
# Script to clear ticket prefix configuration and license data from Znuny system
# This script removes all entries from ticket_prefix and license tables

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

# Check if running with --force flag
FORCE_MODE=false
if [ "$1" = "--force" ]; then
    FORCE_MODE=true
fi

# Warning and confirmation
if [ "$FORCE_MODE" = false ]; then
    echo -e "${YELLOW}WARNING: This script will DELETE ALL PREFIX and LICENSE data from your Znuny system!${NC}"
    echo -e "${YELLOW}This includes:${NC}"
    echo "  - All ticket prefix configurations"
    echo "  - All license data"
    echo -e "${YELLOW}This action is IRREVERSIBLE!${NC}"
    echo ""
    read -p "Are you absolutely sure you want to delete ALL prefix and license data? Type 'YES' to confirm: " CONFIRM

    if [ "$CONFIRM" != "YES" ]; then
        echo -e "${RED}Aborted. No data was deleted.${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Starting prefix and license data deletion process...${NC}"

# Get current count of records
echo "Checking current data..."
PREFIX_COUNT=$(run_db_query "SELECT COUNT(*) FROM ticket_prefix;" | tr -d ' ')
LICENSE_COUNT=$(run_db_query "SELECT COUNT(*) FROM license;" | tr -d ' ')

echo -e "${YELLOW}Found $PREFIX_COUNT ticket prefix entries${NC}"
echo -e "${YELLOW}Found $LICENSE_COUNT license entries${NC}"

if [ "$PREFIX_COUNT" = "0" ] && [ "$LICENSE_COUNT" = "0" ]; then
    echo -e "${GREEN}No data to delete. Tables are already empty.${NC}"
    exit 0
fi

# Clear ticket_prefix table
if [ "$PREFIX_COUNT" != "0" ]; then
    echo "Clearing ticket prefix data..."
    run_db_query "DELETE FROM ticket_prefix;"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Ticket prefix data cleared successfully${NC}"
    else
        echo -e "${RED}✗ Failed to clear ticket prefix data${NC}"
    fi
fi

# Clear license table
if [ "$LICENSE_COUNT" != "0" ]; then
    echo "Clearing license data..."
    run_db_query "DELETE FROM license;"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ License data cleared successfully${NC}"
    else
        echo -e "${RED}✗ Failed to clear license data${NC}"
    fi
fi

# Final verification
echo ""
echo "Verifying deletion..."
FINAL_PREFIX_COUNT=$(run_db_query "SELECT COUNT(*) FROM ticket_prefix;" | tr -d ' ')
FINAL_LICENSE_COUNT=$(run_db_query "SELECT COUNT(*) FROM license;" | tr -d ' ')

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo "Ticket prefix entries: $PREFIX_COUNT → $FINAL_PREFIX_COUNT"
echo "License entries: $LICENSE_COUNT → $FINAL_LICENSE_COUNT"

if [ "$FINAL_PREFIX_COUNT" = "0" ] && [ "$FINAL_LICENSE_COUNT" = "0" ]; then
    echo -e "${GREEN}✓ All prefix and license data successfully cleared!${NC}"
    echo ""
    echo "System has been reset to default state:"
    echo "  - No ticket prefixes configured"
    echo "  - No license data"
    echo "  - Ticket numbering reset to AutoIncrement"
else
    echo -e "${YELLOW}⚠ Some data may not have been cleared completely${NC}"
fi

echo ""
echo -e "${GREEN}All done!${NC}"