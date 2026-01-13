#!/bin/bash

# Flexible password change script for Znuny and Zabbix systems
# Automatically detects available databases and updates user passwords
# This script runs on Proxmox host and uses pct to execute commands in containers
# Usage: ./change_system_passwords.sh [--users="user1,user2"] [--systems="znuny,zabbix"] [--dry-run]

# Proxmox Container Configuration
OTRS_CT_ID="104"    # OTRS/Znuny container ID
ZABBIX_CT_ID="103"  # Zabbix container ID

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse command line arguments
DRY_RUN=false
TARGET_USERS=""
TARGET_SYSTEMS="znuny,zabbix"
CUSTOM_PASSWORD=""
DEBUG_MODE=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --users=*)
            TARGET_USERS="${arg#*=}"
            shift
            ;;
        --systems=*)
            TARGET_SYSTEMS="${arg#*=}"
            shift
            ;;
        --password=*)
            CUSTOM_PASSWORD="${arg#*=}"
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --users=user1,user2    Only change passwords for specified users"
            echo "  --systems=znuny,zabbix Only process specified systems"
            echo "  --password=PASSWORD    Set custom password for all users (instead of random)"
            echo "  --dry-run              Show what would be done without making changes"
            echo "  --debug                Enable debug output for troubleshooting"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Change all user passwords (random)"
            echo "  $0 --users=msicmso,msifield          # Change specific users only"
            echo "  $0 --password=tmp12345               # Set same password for all users"
            echo "  $0 --systems=zabbix --dry-run        # Preview Zabbix changes only"
            echo "  $0 --debug                           # Run with debug output"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# DATABASE CONFIGURATION - EDIT THESE SETTINGS AS NEEDED
# =============================================================================

# Function to parse OTRS Config.pm file from container 104
parse_otrs_config() {
    local config_file="/opt/otrs/Kernel/Config.pm"
    local key="$1"
    
    # Check if file exists in container
    if ! pct exec "$OTRS_CT_ID" -- test -f "$config_file" 2>/dev/null; then
        echo ""
        return 1
    fi
    
    # Parse Perl configuration from inside container
    # Extract value between quotes or after = sign, stop at semicolon or quote
    pct exec "$OTRS_CT_ID" -- grep -E "\{['\"]?$key['\"]?\}" "$config_file" 2>/dev/null | grep -oP "= ['\"]?\K[^'\";\s]+" | head -n1
}

# Znuny/OTRS Database Settings - Read from credential file, fallback to Config.pm
OTRS_CONFIG_FILE="/opt/otrs/Kernel/Config.pm"
OTRS_CREDENTIAL_FILE="/etc/lsmp/credentials/otrsdbuser.pwd"

if [ -f "$OTRS_CREDENTIAL_FILE" ] && [ -s "$OTRS_CREDENTIAL_FILE" ]; then
    # Primary: Use credential file from host
    ZNUNY_DB_NAME="otrsdb"
    ZNUNY_DB_USER="otrsdbuser"
    ZNUNY_DB_PASS=$(cat "$OTRS_CREDENTIAL_FILE" 2>/dev/null | tr -d '\n\r')
    ZNUNY_DB_HOST="172.16.18.20"  # Database on separate server
    ZNUNY_DB_PORT="5432"
elif pct exec "$OTRS_CT_ID" -- test -f "$OTRS_CONFIG_FILE" 2>/dev/null; then
    # Fallback: Read from Config.pm in container 104 if credential file not found
    ZNUNY_DB_NAME=$(parse_otrs_config "Database")
    ZNUNY_DB_USER=$(parse_otrs_config "DatabaseUser")
    ZNUNY_DB_PASS=$(parse_otrs_config "DatabasePw")
    ZNUNY_DB_HOST="172.16.18.20"
    ZNUNY_DB_PORT="5432"  # Default PostgreSQL port
else
    # Last resort: Use default values
    ZNUNY_DB_NAME="otrsdb"
    ZNUNY_DB_USER="otrsdbuser"
    ZNUNY_DB_PASS=""
    ZNUNY_DB_HOST="172.16.18.20"
    ZNUNY_DB_PORT="5432"
fi

# Zabbix Database Settings - Multiple connection methods
ZABBIX_DB_NAME="zabbix"
# Try these methods in order:
# 1. Direct connection with zabbix user
ZABBIX_DB_USER="zabbixdbuser"
ZABBIX_DB_PASS=$(cat /etc/lsmp/credentials/zabbixdbuser.pwd 2>/dev/null | tr -d '\n\r')
# 2. Connection via postgres user with password
ZABBIX_POSTGRES_PASS=""  # Fill this if postgres user has a password
# 3. Use local socket connection (su - postgres)
ZABBIX_USE_SU_POSTGRES=false  # Set to false if postgres system user doesn't exist
ZABBIX_DB_HOST="172.16.18.20"
ZABBIX_DB_PORT="5432"

# =============================================================================

# Validate credentials for both systems
OTRS_CREDENTIALS_OK=false
ZABBIX_CREDENTIALS_OK=false
OTRS_CREDENTIALS_SOURCE="unknown"

echo -e "${CYAN}=== Credential Validation ===${NC}"
echo ""

# Check OTRS/Znuny credentials - validate actual values, not file existence
if [ -z "$ZNUNY_DB_PASS" ]; then
    echo -e "${RED}✗ OTRS credentials: MISSING${NC}"
    if [ ! -f "$OTRS_CREDENTIAL_FILE" ] && [ ! -f "$OTRS_CONFIG_FILE" ]; then
        echo -e "${YELLOW}  Reason: Credential file not found AND Config.pm not found${NC}"
    else
        echo -e "${YELLOW}  Reason: Password not set${NC}"
    fi
elif [ -z "$ZNUNY_DB_HOST" ] || [ -z "$ZNUNY_DB_NAME" ] || [ -z "$ZNUNY_DB_USER" ]; then
    echo -e "${RED}✗ OTRS credentials: INCOMPLETE${NC}"
    echo -e "${YELLOW}  Reason: Missing Host, Database name, or Username${NC}"
else
    # Credentials are valid - determine source
    OTRS_CREDENTIALS_OK=true
    if [ -f "$OTRS_CREDENTIAL_FILE" ] && [ -s "$OTRS_CREDENTIAL_FILE" ]; then
        OTRS_CREDENTIALS_SOURCE="$OTRS_CREDENTIAL_FILE"
    elif [ -f "$OTRS_CONFIG_FILE" ]; then
        OTRS_CREDENTIALS_SOURCE="$OTRS_CONFIG_FILE"
    else
        OTRS_CREDENTIALS_SOURCE="default values"
    fi
    echo -e "${GREEN}✓ OTRS credentials: OK${NC}"
    echo -e "${GREEN}  Source: ${OTRS_CREDENTIALS_SOURCE}${NC}"
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}  [DEBUG] Database: $ZNUNY_DB_NAME${NC}"
        echo -e "${CYAN}  [DEBUG] User: $ZNUNY_DB_USER${NC}"
        echo -e "${CYAN}  [DEBUG] Host: $ZNUNY_DB_HOST${NC}"
        echo -e "${CYAN}  [DEBUG] Port: $ZNUNY_DB_PORT${NC}"
        echo -e "${CYAN}  [DEBUG] Password: [SET]${NC}"
    fi
fi

# Check Zabbix credentials
if [ -z "$ZABBIX_DB_PASS" ]; then
    echo -e "${YELLOW}⚠ Zabbix credentials: MISSING${NC}"
    if [ ! -f "/etc/lsmp/credentials/zabbixdbuser.pwd" ]; then
        echo -e "${YELLOW}  Reason: Credential file not found${NC}"
    else
        echo -e "${YELLOW}  Reason: Credential file is empty${NC}"
    fi
    echo -e "${YELLOW}  Note: Script will attempt alternative authentication methods${NC}"
else
    ZABBIX_CREDENTIALS_OK=true
    echo -e "${GREEN}✓ Zabbix credentials: OK${NC}"
    echo -e "${GREEN}  Source: /etc/lsmp/credentials/zabbixdbuser.pwd${NC}"
fi

echo ""

# Check if at least one database has valid credentials
if [ "$OTRS_CREDENTIALS_OK" = false ] && [ "$ZABBIX_CREDENTIALS_OK" = false ]; then
    echo -e "${RED}ERROR: No valid credentials found for either OTRS or Zabbix${NC}"
    echo -e "${YELLOW}Please ensure credentials for at least one system:${NC}"
    echo -e "${YELLOW}  OTRS:   $OTRS_CREDENTIAL_FILE OR $OTRS_CONFIG_FILE${NC}"
    echo -e "${YELLOW}  Zabbix: /etc/lsmp/credentials/zabbixdbuser.pwd${NC}"
    exit 1
fi

# Prompt for confirmation if one database is missing credentials (unless dry-run)
if [ "$OTRS_CREDENTIALS_OK" = false ] || [ "$ZABBIX_CREDENTIALS_OK" = false ]; then
    echo -e "${YELLOW}WARNING: Some database credentials are missing${NC}"
    if [ "$OTRS_CREDENTIALS_OK" = false ]; then
        echo -e "${YELLOW}  - OTRS/Znuny: Will be SKIPPED${NC}"
    fi
    if [ "$ZABBIX_CREDENTIALS_OK" = false ]; then
        echo -e "${YELLOW}  - Zabbix: Will be SKIPPED (unless alternative auth succeeds)${NC}"
    fi
    echo ""
    
    # Skip confirmation in dry-run mode
    if [ "$DRY_RUN" = false ]; then
        read -p "Continue with available credentials? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Operation cancelled by user${NC}"
            exit 0
        fi
    else
        echo -e "${CYAN}[DRY RUN MODE] Skipping confirmation prompt${NC}"
    fi
    echo ""
fi

echo -e "${GREEN}✓ Credential validation completed${NC}"
echo ""

echo -e "${CYAN}=== Flexible System Password Change Script ===${NC}"
echo "This script will detect and change passwords for Znuny and Zabbix users"
echo ""
echo -e "${BLUE}Database Configuration:${NC}"
echo "  Znuny:  $ZNUNY_DB_USER@$ZNUNY_DB_HOST:$ZNUNY_DB_PORT/$ZNUNY_DB_NAME"
echo "  Zabbix: $ZABBIX_DB_HOST:$ZABBIX_DB_PORT/$ZABBIX_DB_NAME"
echo ""
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN MODE] - No actual changes will be made${NC}"
fi
if [ "$DEBUG_MODE" = true ]; then
    echo -e "${YELLOW}[DEBUG MODE] - Verbose output enabled${NC}"
fi
if [ -n "$CUSTOM_PASSWORD" ]; then
    echo -e "${YELLOW}[CUSTOM PASSWORD MODE] - Using provided password for all users${NC}"
fi
if [ "$DRY_RUN" = true ] || [ -n "$CUSTOM_PASSWORD" ] || [ "$DEBUG_MODE" = true ]; then
    echo ""
fi

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="/root"

LOG_FILE="${OUTPUT_DIR}/password_change_${TIMESTAMP}.log"
OUTPUT_FILE="${OUTPUT_DIR}/system_passwords_${TIMESTAMP}.txt"

# Function to log messages
log_message() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Function to debug log
debug_log() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}[DEBUG] $1${NC}" | tee -a "$LOG_FILE" >&2
    fi
}

# Function to generate or use custom password
generate_password() {
    if [ -n "$CUSTOM_PASSWORD" ]; then
        echo "$CUSTOM_PASSWORD"
    else
        # Generate a 16-character password with mixed case, numbers, and special characters
        local base_password=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-12)
        local suffix=$(date +%s | tail -c 4)
        local special_chars=("@" "#" "!" "&")
        local special_char=${special_chars[$((RANDOM % ${#special_chars[@]}))]}
        echo "${base_password}${special_char}${suffix}"
    fi
}

# Generate password hash for Zabbix (tries Python crypt, passlib, htpasswd, PHP)
generate_bcrypt_hash() {
    local password="$1"
    local hash=""
    
    if [ -z "$password" ]; then
        echo "BCRYPT_ERROR"
        return 1
    fi
    
    # Use base64 encoding to safely pass password through shell layers
    local encoded_password=$(printf '%s' "$password" | base64 -w 0)

    # Method 1: Try Python with passlib (most reliable for bcrypt)
    if pct exec "$ZABBIX_CT_ID" -- python3 -c "import passlib.hash" 2>/dev/null; then
        hash=$(pct exec "$ZABBIX_CT_ID" -- bash -c "python3 -c \"import passlib.hash, base64; pwd=base64.b64decode('$encoded_password').decode(); print(passlib.hash.bcrypt.hash(pwd))\"" 2>/dev/null)
        if [ -n "$hash" ] && [ "$hash" != "BCRYPT_ERROR" ] && [ "${#hash}" -gt 20 ]; then
            echo "$hash"
            return 0
        fi
    fi
    
    # Method 2: Try Python standard crypt with SHA512 (Zabbix supports this too)
    # encoded_password already set above
    local raw_output=$(pct exec "$ZABBIX_CT_ID" -- bash -c "python3 -W ignore -c \"import crypt, base64; pwd=base64.b64decode('$encoded_password').decode(); print(crypt.crypt(pwd, crypt.mksalt(crypt.METHOD_SHA512)))\"" 2>&1)
    
    hash=$(echo "$raw_output" | tail -1)
    hash="${hash//[$'\r\n']}"
    
    # Validate SHA512 hash format
    if [ -n "$hash" ] && [ "${hash:0:3}" = "\$6\$" ] && [ "${#hash}" -gt 50 ]; then
        echo "$hash"
        return 0
    fi
    
    # Method 3: Try htpasswd (from apache2-utils)
    if pct exec "$ZABBIX_CT_ID" -- command -v htpasswd >/dev/null 2>&1; then
        hash=$(pct exec "$ZABBIX_CT_ID" -- bash -c "echo '$encoded_password' | base64 -d | htpasswd -nbBi '' '' | cut -d: -f2" 2>/dev/null)
        if [ -n "$hash" ] && [ "$hash" != "BCRYPT_ERROR" ] && [ "${#hash}" -gt 20 ]; then
            echo "$hash"
            return 0
        fi
    fi
    
    # Method 4: Try PHP as fallback
    if pct exec "$ZABBIX_CT_ID" -- command -v php >/dev/null 2>&1; then
        hash=$(pct exec "$ZABBIX_CT_ID" -- bash -c "php -r \"echo password_hash(base64_decode('$encoded_password'), PASSWORD_BCRYPT);\"" 2>/dev/null)
        if [ -n "$hash" ] && [ "$hash" != "BCRYPT_ERROR" ] && [ "${#hash}" -gt 20 ]; then
            echo "$hash"
            return 0
        fi
    fi
    
    # All methods failed - try to get error details if debug mode
    if [ "$DEBUG_MODE" = true ]; then
        debug_log "Hash generation failed for all methods. Testing with debug output:"
        pct exec "$ZABBIX_CT_ID" -- bash -c "python3 -W ignore -c \"import crypt; print(crypt.crypt('test', crypt.mksalt(crypt.METHOD_SHA512)))\"" 2>&1 | head -5 | while IFS= read -r line; do
            debug_log "  $line"
        done
    fi
    
    echo "BCRYPT_ERROR"
    return 1
}

# Generate OTRS/Znuny password hash (SHA-256)
generate_znuny_hash() {
    local password="$1"
    printf '%s' "$password" | sha256sum | cut -d' ' -f1
}

# Check if database exists and is accessible
check_database() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    local result=1
    
    debug_log "Checking database: $db_name with user: $db_user"
    
    if [ "$db_name" = "$ZNUNY_DB_NAME" ]; then
        if [ -n "$db_pass" ]; then
            debug_log "Testing OTRS connection with password in container $OTRS_CT_ID"
            pct exec "$OTRS_CT_ID" -- bash -c "PGPASSWORD='$db_pass' psql -h '$ZNUNY_DB_HOST' -p '$ZNUNY_DB_PORT' -U '$db_user' -d '$db_name' -c 'SELECT 1;'" >/dev/null 2>&1
            result=$?
        else
            debug_log "Testing OTRS connection without password in container $OTRS_CT_ID"
            pct exec "$OTRS_CT_ID" -- psql -h "$ZNUNY_DB_HOST" -p "$ZNUNY_DB_PORT" -U "$db_user" -d "$db_name" -c "SELECT 1;" >/dev/null 2>&1
            result=$?
        fi
        
        if [ $result -ne 0 ] && [ "$DEBUG_MODE" = true ]; then
            debug_log "OTRS connection failed. Testing with verbose output:"
            pct exec "$OTRS_CT_ID" -- bash -c "PGPASSWORD='$db_pass' psql -h '$ZNUNY_DB_HOST' -p '$ZNUNY_DB_PORT' -U '$db_user' -d '$db_name' -c 'SELECT 1;'" 2>&1 | while IFS= read -r line; do
                debug_log "  $line"
            done
        fi
        
    elif [ "$db_name" = "$ZABBIX_DB_NAME" ]; then
        # Try multiple connection methods for Zabbix
        
        # Method 1: Try with zabbix user
        if [ -n "$ZABBIX_DB_USER" ] && [ "$ZABBIX_DB_USER" != "postgres" ]; then
            debug_log "Testing Zabbix connection with user: $ZABBIX_DB_USER in container $ZABBIX_CT_ID"
            if [ -n "$ZABBIX_DB_PASS" ]; then
                pct exec "$ZABBIX_CT_ID" -- bash -c "PGPASSWORD='$ZABBIX_DB_PASS' psql -h '$ZABBIX_DB_HOST' -p '$ZABBIX_DB_PORT' -U '$ZABBIX_DB_USER' -d '$db_name' -c 'SELECT 1;'" >/dev/null 2>&1
            else
                pct exec "$ZABBIX_CT_ID" -- psql -h "$ZABBIX_DB_HOST" -p "$ZABBIX_DB_PORT" -U "$ZABBIX_DB_USER" -d "$db_name" -c "SELECT 1;" >/dev/null 2>&1
            fi
            result=$?
            [ $result -eq 0 ] && debug_log "Success with zabbix user" && return 0
        fi
        
        # Method 2: Try with postgres user and password
        if [ -n "$ZABBIX_POSTGRES_PASS" ]; then
            debug_log "Testing Zabbix connection with postgres user and password in container $ZABBIX_CT_ID"
            pct exec "$ZABBIX_CT_ID" -- bash -c "PGPASSWORD='$ZABBIX_POSTGRES_PASS' psql -h '$ZABBIX_DB_HOST' -p '$ZABBIX_DB_PORT' -U 'postgres' -d '$db_name' -c 'SELECT 1;'" >/dev/null 2>&1
            result=$?
            [ $result -eq 0 ] && debug_log "Success with postgres user and password" && return 0
        fi
        
        # Method 3: Try with local postgres user (su) inside container
        if [ "$ZABBIX_USE_SU_POSTGRES" = true ]; then
            debug_log "Testing Zabbix connection with su - postgres in container $ZABBIX_CT_ID"
            pct exec "$ZABBIX_CT_ID" -- su - postgres -c "psql -d $db_name -c 'SELECT 1;'" >/dev/null 2>&1
            result=$?
            [ $result -eq 0 ] && debug_log "Success with su - postgres" && return 0
        fi
        
        # Method 4: Try peer authentication
        debug_log "Testing Zabbix connection with peer authentication in container $ZABBIX_CT_ID"
        pct exec "$ZABBIX_CT_ID" -- psql -d "$db_name" -c "SELECT 1;" >/dev/null 2>&1
        result=$?
        [ $result -eq 0 ] && debug_log "Success with peer authentication" && return 0
        
        if [ "$DEBUG_MODE" = true ] && [ $result -ne 0 ]; then
            debug_log "All Zabbix connection methods failed"
        fi
    fi
    
    return $result
}

# Function to check if user should be processed
should_process_user() {
    local username=$1
    
    # If specific users are targeted, only process those
    if [ -n "$TARGET_USERS" ]; then
        echo ",$TARGET_USERS," | grep -q ",$username,"
        return $?
    fi
    
    # Skip system users
    case "$username" in
        "guest"|"system"|"")
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# Function to check if system should be processed
should_process_system() {
    local system_name=$1
    echo ",$TARGET_SYSTEMS," | grep -qi ",$system_name,"
    return $?
}

# Excluded users (passwords will never be changed)
EXCLUDED_USERS="lsmpappuser,ticketingusr"

# Get users from database
get_database_users() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    local table_name=$4
    local username_column=$5

    # Build exclusion clause for SQL query
    local excluded_list=$(echo "$EXCLUDED_USERS" | sed "s/,/','/g")
    local query="SELECT $username_column FROM $table_name WHERE $username_column IS NOT NULL AND $username_column != '' AND $username_column NOT IN ('$excluded_list');"

    # Add user filtering to query if specific users are targeted
    if [ -n "$TARGET_USERS" ]; then
        local user_list=$(echo "$TARGET_USERS" | sed "s/,/','/g")
        query="SELECT $username_column FROM $table_name WHERE $username_column IN ('$user_list') AND $username_column IS NOT NULL AND $username_column != '' AND $username_column NOT IN ('$excluded_list');"
    fi
    
    debug_log "Executing query: $query"
    
    if [ "$db_name" = "$ZNUNY_DB_NAME" ]; then
        if [ -n "$db_pass" ]; then
            pct exec "$OTRS_CT_ID" -- bash -c "PGPASSWORD='$db_pass' psql -h '$ZNUNY_DB_HOST' -p '$ZNUNY_DB_PORT' -U '$db_user' -d '$db_name' -t -c \"$query\"" 2>/dev/null
        else
            pct exec "$OTRS_CT_ID" -- psql -h "$ZNUNY_DB_HOST" -p "$ZNUNY_DB_PORT" -U "$db_user" -d "$db_name" -t -c "$query" 2>/dev/null
        fi
    elif [ "$db_name" = "$ZABBIX_DB_NAME" ]; then
        # Use the same connection method that worked in check_database
        local output=""
        
        # Try zabbix user first
        if [ -n "$ZABBIX_DB_USER" ] && [ "$ZABBIX_DB_USER" != "postgres" ]; then
            if [ -n "$ZABBIX_DB_PASS" ]; then
                output=$(pct exec "$ZABBIX_CT_ID" -- bash -c "PGPASSWORD='$ZABBIX_DB_PASS' psql -h '$ZABBIX_DB_HOST' -p '$ZABBIX_DB_PORT' -U '$ZABBIX_DB_USER' -d '$db_name' -t -c \"$query\"" 2>/dev/null)
            else
                output=$(pct exec "$ZABBIX_CT_ID" -- psql -h "$ZABBIX_DB_HOST" -p "$ZABBIX_DB_PORT" -U "$ZABBIX_DB_USER" -d "$db_name" -t -c "$query" 2>/dev/null)
            fi
            [ -n "$output" ] && echo "$output" && return 0
        fi
        
        # Try postgres with password
        if [ -n "$ZABBIX_POSTGRES_PASS" ]; then
            output=$(pct exec "$ZABBIX_CT_ID" -- bash -c "PGPASSWORD='$ZABBIX_POSTGRES_PASS' psql -h '$ZABBIX_DB_HOST' -p '$ZABBIX_DB_PORT' -U 'postgres' -d '$db_name' -t -c \"$query\"" 2>/dev/null)
            [ -n "$output" ] && echo "$output" && return 0
        fi
        
        # Try su inside container
        if [ "$ZABBIX_USE_SU_POSTGRES" = true ]; then
            output=$(pct exec "$ZABBIX_CT_ID" -- su - postgres -c "psql -d $db_name -t -c \"$query\"" 2>/dev/null)
            [ -n "$output" ] && echo "$output" && return 0
        fi
        
        # Try peer authentication
        output=$(pct exec "$ZABBIX_CT_ID" -- psql -d "$db_name" -t -c "$query" 2>/dev/null)
        [ -n "$output" ] && echo "$output"
    fi
}

# Update password in database
update_password() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    local table_name=$4
    local username_column=$5
    local password_column=$6
    local username=$7
    local new_password_hash=$8
    
    if [ "$db_name" = "$ZNUNY_DB_NAME" ]; then
        if [ -n "$db_pass" ]; then
            pct exec "$OTRS_CT_ID" -- bash -c "PGPASSWORD='$db_pass' psql -h '$ZNUNY_DB_HOST' -p '$ZNUNY_DB_PORT' -U '$db_user' -d '$db_name' -c \"UPDATE $table_name SET $password_column = '$new_password_hash' WHERE $username_column = '$username';\"" >/dev/null 2>&1
        else
            pct exec "$OTRS_CT_ID" -- psql -h "$ZNUNY_DB_HOST" -p "$ZNUNY_DB_PORT" -U "$db_user" -d "$db_name" -c "UPDATE $table_name SET $password_column = '$new_password_hash' WHERE $username_column = '$username';" >/dev/null 2>&1
        fi
    elif [ "$db_name" = "$ZABBIX_DB_NAME" ]; then
        # Escape single quotes for SQL and dollar signs for bash
        local escaped_hash=$(echo "$new_password_hash" | sed "s/'/''/g" | sed 's/\$/\\$/g')
        local update_query="UPDATE $table_name SET $password_column = '$escaped_hash' WHERE $username_column = '$username';"
        
        if [ -n "$ZABBIX_DB_USER" ] && [ "$ZABBIX_DB_USER" != "postgres" ]; then
            if [ -n "$ZABBIX_DB_PASS" ]; then
                local result=$(pct exec "$ZABBIX_CT_ID" -- bash -c "PGPASSWORD='$ZABBIX_DB_PASS' psql -h '$ZABBIX_DB_HOST' -p '$ZABBIX_DB_PORT' -U '$ZABBIX_DB_USER' -d '$db_name' -c \"$update_query\"" 2>&1)
                local exit_code=$?
                if [ $exit_code -eq 0 ]; then
                    return 0
                else
                    debug_log "Zabbix update failed for $username: $result"
                fi
            else
                pct exec "$ZABBIX_CT_ID" -- psql -h "$ZABBIX_DB_HOST" -p "$ZABBIX_DB_PORT" -U "$ZABBIX_DB_USER" -d "$db_name" -c "$update_query" >/dev/null 2>&1 && return 0
            fi
        fi
        
        if [ -n "$ZABBIX_POSTGRES_PASS" ]; then
            pct exec "$ZABBIX_CT_ID" -- bash -c "PGPASSWORD='$ZABBIX_POSTGRES_PASS' psql -h '$ZABBIX_DB_HOST' -p '$ZABBIX_DB_PORT' -U 'postgres' -d '$db_name' -c \"$update_query\"" >/dev/null 2>&1 && return 0
        fi
        
        if [ "$ZABBIX_USE_SU_POSTGRES" = true ]; then
            pct exec "$ZABBIX_CT_ID" -- su - postgres -c "psql -d $db_name -c '$update_query'" >/dev/null 2>&1 && return 0
        fi
        
        pct exec "$ZABBIX_CT_ID" -- psql -d "$db_name" -c "$update_query" >/dev/null 2>&1
    fi
    return $?
}

# Initialize output file
cat > "$OUTPUT_FILE" << EOF
System Password Change Report - $(date)
========================================

EOF

# Check for Znuny/OTRS database
if should_process_system "znuny"; then
    if [ "$OTRS_CREDENTIALS_OK" = false ]; then
        log_message "${YELLOW}Skipping Znuny/OTRS (credentials not available)${NC}"
    else
        log_message "${YELLOW}Checking for Znuny/OTRS database...${NC}"
        if check_database "$ZNUNY_DB_NAME" "$ZNUNY_DB_USER" "$ZNUNY_DB_PASS"; then
        log_message "${GREEN}✓ Znuny/OTRS database found and accessible${NC}"
        
        # Get users from Znuny database
        ZNUNY_USERS=$(get_database_users "$ZNUNY_DB_NAME" "$ZNUNY_DB_USER" "$ZNUNY_DB_PASS" "users" "login")
    
    if [ -n "$ZNUNY_USERS" ]; then
        echo "ZNUNY/OTRS USER PASSWORDS:" >> "$OUTPUT_FILE"
        echo "=========================" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        log_message "${BLUE}Found Znuny/OTRS users. Changing passwords...${NC}"
        
        # Process each user
        echo "$ZNUNY_USERS" | while IFS= read -r username; do
            username=$(echo "$username" | xargs)  # Trim whitespace
            [ -z "$username" ] && continue
            
            # Generate and update password
            NEW_PASSWORD=$(generate_password)
            PASSWORD_HASH=$(generate_znuny_hash "$NEW_PASSWORD")
            if [ "$DRY_RUN" = true ]; then
                log_message "${CYAN}[DRY RUN] Would update password for Znuny user: $username${NC}"
                echo "Username: $username" >> "$OUTPUT_FILE"
                echo "Password: $NEW_PASSWORD (DRY RUN - NOT APPLIED)" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"
            elif update_password "$ZNUNY_DB_NAME" "$ZNUNY_DB_USER" "$ZNUNY_DB_PASS" "users" "login" "pw" "$username" "$PASSWORD_HASH"; then
                log_message "${GREEN}✓ Updated password for Znuny user: $username${NC}"
                echo "Username: $username" >> "$OUTPUT_FILE"
                echo "Password: $NEW_PASSWORD" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"
            else
                log_message "${RED}✗ Failed to update password for Znuny user: $username${NC}"
            fi
        done
        
        echo "" >> "$OUTPUT_FILE"
        else
            log_message "${YELLOW}No users found in Znuny database${NC}"
        fi
    else
        log_message "${RED}✗ Znuny/OTRS database not accessible${NC}"
    fi
    fi
else
    log_message "${YELLOW}Skipping Znuny (not in target systems)${NC}"
fi

# Check for Zabbix database
if should_process_system "zabbix"; then
    if [ "$ZABBIX_CREDENTIALS_OK" = false ]; then
        log_message "${YELLOW}Zabbix credentials not available - will attempt alternative authentication methods${NC}"
    fi
    log_message "${YELLOW}Checking for Zabbix database...${NC}"
    if check_database "$ZABBIX_DB_NAME" "$ZABBIX_DB_USER" "$ZABBIX_DB_PASS"; then
        log_message "${GREEN}✓ Zabbix database found and accessible${NC}"
        
        # Check if password hashing tools are available in container 104
        BCRYPT_AVAILABLE=false
        BCRYPT_METHOD=""
        
        if pct exec "$ZABBIX_CT_ID" -- python3 -c "import passlib.hash" 2>/dev/null; then
            BCRYPT_AVAILABLE=true
            BCRYPT_METHOD="Python3 passlib (bcrypt)"
        elif pct exec "$ZABBIX_CT_ID" -- python3 -c "import crypt" 2>/dev/null; then
            BCRYPT_AVAILABLE=true
            BCRYPT_METHOD="Python3 crypt (SHA512)"
        elif pct exec "$ZABBIX_CT_ID" -- command -v htpasswd >/dev/null 2>&1; then
            BCRYPT_AVAILABLE=true
            BCRYPT_METHOD="htpasswd (bcrypt)"
        elif pct exec "$ZABBIX_CT_ID" -- command -v php >/dev/null 2>&1; then
            BCRYPT_AVAILABLE=true
            BCRYPT_METHOD="PHP (bcrypt)"
        fi
        
        if [ "$BCRYPT_AVAILABLE" = true ]; then
            log_message "${GREEN}✓ Password hashing available using: $BCRYPT_METHOD${NC}"
            # Get users from Zabbix database
            ZABBIX_USERS=$(get_database_users "$ZABBIX_DB_NAME" "$ZABBIX_DB_USER" "$ZABBIX_DB_PASS" "users" "username")
        
        if [ -n "$ZABBIX_USERS" ]; then
            echo "ZABBIX USER PASSWORDS:" >> "$OUTPUT_FILE"
            echo "=====================" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            
            log_message "${BLUE}Found Zabbix users. Changing passwords...${NC}"
            
            # Process each user
            echo "$ZABBIX_USERS" | while IFS= read -r username; do
                username=$(echo "$username" | xargs)  # Trim whitespace
                [ -z "$username" ] && continue
                
                if ! should_process_user "$username"; then
                    continue
                fi
                
                # Generate and update password
                NEW_PASSWORD=$(generate_password)
                PASSWORD_HASH=$(generate_bcrypt_hash "$NEW_PASSWORD")
                
                if [ -n "$PASSWORD_HASH" ] && [ "$PASSWORD_HASH" != "BCRYPT_ERROR" ]; then
                    if [ "$DRY_RUN" = true ]; then
                        log_message "${CYAN}[DRY RUN] Would update password for Zabbix user: $username${NC}"
                        echo "Username: $username" >> "$OUTPUT_FILE"
                        echo "Password: $NEW_PASSWORD (DRY RUN - NOT APPLIED)" >> "$OUTPUT_FILE"
                        echo "" >> "$OUTPUT_FILE"
                    elif update_password "$ZABBIX_DB_NAME" "$ZABBIX_DB_USER" "$ZABBIX_DB_PASS" "users" "username" "passwd" "$username" "$PASSWORD_HASH"; then
                        log_message "${GREEN}✓ Updated password for Zabbix user: $username${NC}"
                        echo "Username: $username" >> "$OUTPUT_FILE"
                        echo "Password: $NEW_PASSWORD" >> "$OUTPUT_FILE"
                        echo "" >> "$OUTPUT_FILE"
                    else
                        log_message "${RED}✗ Failed to update password for Zabbix user: $username${NC}"
                    fi
                else
                    log_message "${RED}✗ Failed to generate password hash for Zabbix user: $username${NC}"
                fi
            done
            
            echo "" >> "$OUTPUT_FILE"
            else
                log_message "${YELLOW}No users found in Zabbix database${NC}"
            fi
        else
            log_message "${RED}✗ No password hashing tools available in container $ZABBIX_CT_ID${NC}"
            log_message "${YELLOW}  Python3 crypt module recommended (usually pre-installed)${NC}"
            log_message "${YELLOW}  Alternatively install: python3-passlib, apache2-utils, or php-cli${NC}"
            log_message "${YELLOW}  Example: pct exec $ZABBIX_CT_ID -- apt-get install -y python3-passlib${NC}"
        fi
    else
        log_message "${RED}✗ Zabbix database not accessible${NC}"
        if [ "$DEBUG_MODE" = true ]; then
            log_message "${YELLOW}Troubleshooting tips:${NC}"
            log_message "  1. Check if PostgreSQL is running: systemctl status postgresql"
            log_message "  2. Verify the zabbix database exists: sudo -u postgres psql -l"
            log_message "  3. Check pg_hba.conf for authentication settings"
            log_message "  4. Try setting ZABBIX_DB_USER and ZABBIX_DB_PASS in the script"
            log_message "  5. Or set ZABBIX_POSTGRES_PASS if postgres user has a password"
        fi
    fi
else
    log_message "${YELLOW}Skipping Zabbix (not in target systems)${NC}"
fi

# Add system information to output file
cat >> "$OUTPUT_FILE" << EOF
SYSTEM INFORMATION:
==================
Server: $(hostname)
Date: $(date)
Script: $0
Log: $LOG_FILE

EOF

# Set secure permissions on output file
chmod 600 "$OUTPUT_FILE"
chmod 600 "$LOG_FILE"

# Final summary
echo ""
log_message "========================================="
log_message "${YELLOW}PASSWORD CHANGE SUMMARY:${NC}"
log_message "${GREEN}Passwords saved to: $OUTPUT_FILE${NC}"
log_message "${GREEN}Logs saved to: $LOG_FILE${NC}"
echo ""

# Check if any passwords were changed
if grep -q "Username:" "$OUTPUT_FILE"; then
    log_message "${GREEN}✓ Password changes completed successfully${NC}"
    log_message "${YELLOW}IMPORTANT: Save the password file in a secure location${NC}"
    
    # Show the locations of the files
    echo ""
    log_message "${BLUE}Files created:${NC}"
    log_message "  Passwords: $OUTPUT_FILE"
    log_message "  Log:       $LOG_FILE"
else
    log_message "${YELLOW}⚠ No passwords were changed${NC}"
    log_message "This may be because no databases were accessible or no users were found"
    if [ "$DEBUG_MODE" = false ]; then
        log_message "Try running with --debug flag for more information"
    fi
fi

log_message "========================================="