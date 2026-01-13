#!/bin/bash
# Database configuration for migration scripts
# This file is sourced by all migration scripts

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
ZNUNY_HOME=$(find_znuny_home)

if [ -z "$ZNUNY_HOME" ]; then
    echo "Error: Could not find Znuny installation directory!"
    echo "Please ensure Znuny is installed and Kernel/Config.pm exists."
    return 1 2>/dev/null || exit 1
fi

# Extract database configuration
CONFIG_FILE="$ZNUNY_HOME/Kernel/Config.pm"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config.pm not found at $CONFIG_FILE"
    return 1 2>/dev/null || exit 1
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
    echo "Error: Could not extract database configuration from Config.pm"
    echo "Found: User=$DB_USER, Name=$DB_NAME, Host=$DB_HOST"
    return 1 2>/dev/null || exit 1
fi

# Set default host if not found
[ -z "$DB_HOST" ] && DB_HOST="localhost"

# Export for use in migration scripts
export DB_USER
export DB_PASS
export DB_NAME
export DB_HOST

# Helper function for database commands
run_psql() {
    PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -h $DB_HOST "$@"
}