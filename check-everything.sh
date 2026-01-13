#!/bin/bash
# MSSTLite Complete System Check Script
# This script checks EVERYTHING - tables, data, dynamic fields, configuration

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "MSSTLite COMPLETE SYSTEM CHECK"
echo "========================================="
echo ""

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source database configuration
if [ -f "$SCRIPT_DIR/migrations/db_config.sh" ]; then
    source "$SCRIPT_DIR/migrations/db_config.sh"
else
    echo -e "${RED}Error: Could not find db_config.sh${NC}"
    echo "Expected location: $SCRIPT_DIR/migrations/db_config.sh"
    exit 1
fi

# Validate database credentials were loaded
if [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_NAME" ]; then
    echo -e "${RED}Error: Failed to load database credentials${NC}"
    echo "Please check your Znuny Config.pm file"
    exit 1
fi

echo -e "${BLUE}Database connection: ${NC}$DB_USER@$DB_HOST/$DB_NAME"
echo ""

# Function to run psql commands
run_sql() {
    PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -h $DB_HOST -t -c "$1" 2>/dev/null | tr -d ' '
}

# Function to check table and count
check_table() {
    local table=$1
    local count=$(run_sql "SELECT COUNT(*) FROM $table" 2>/dev/null || echo "MISSING")
    if [ "$count" = "MISSING" ]; then
        echo -e "${RED}✗ Table $table: DOES NOT EXIST${NC}"
    elif [ "$count" = "0" ]; then
        echo -e "${YELLOW}⚠ Table $table: EXISTS but EMPTY (0 rows)${NC}"
    else
        echo -e "${GREEN}✓ Table $table: $count rows${NC}"
    fi
}

echo -e "${BLUE}=== CHECKING MSSTLITE TABLES ===${NC}"
echo ""

# Check all MSSTLite tables
TABLES=(
    "license"
    "encryption_keys"
    "sms_config"
    "ticket_prefix"
    "ticket_initial_counter"
    "msst_migrations"
    "incident_management"
    "incident_work_notes"
    "incident_resolution_notes"
    "incident_product_category"
    "incident_operational_category"
    "incident_resolution_category"
)

for table in "${TABLES[@]}"; do
    check_table "$table"
done

echo ""
echo -e "${BLUE}=== CHECKING DYNAMIC FIELDS ===${NC}"
echo ""

# List of expected dynamic fields
DYNAMIC_FIELDS=(
    "IncidentNumber"
    "IncidentSource"
    "IncidentPriority"
    "IncidentState"
    "IncidentCI"
    "IncidentAssignmentGroup"
    "IncidentAssignedTo"
    "IncidentShortDescription"
    "IncidentDescription"
    "ProductCat1"
    "ProductCat2"
    "ProductCat3"
    "ProductCat4"
    "OperationCat1"
    "OperationCat2"
    "OperationCat3"
    "WorkNotes"
    "ResolutionCat1"
    "ResolutionCat2"
    "ResolutionCat3"
    "ResolutionCode"
    "ResolutionNotes"
    "Opened"
    "OpenedBy"
    "Updated"
    "UpdatedBy"
    "Response"
    "Resolved"
    "AlarmID"
    "EventID"
    "EventSite"
    "SourceDevice"
    "EventMessage"
    "EventBeginTime"
    "EventDetectTime"
    "MSITicketNumber"
    "Customer"
    "MSITicketSite"
    "MSITicketState"
    "MSITicketStateReason"
    "MSITicketPriority"
    "MSITicketAssignee"
    "MSITicketShortDescription"
    "MSITicketResolutionNote"
    "MSITicketCreatedTime"
    "MSITicketLastUpdateTime"
    "MSITicketEbondLastUpdateTime"
    "MSITicketResolvedTime"
    "MSIEbondAPIResponse"
    "MSITicketComment"
)

# Check dynamic fields
total_df=0
missing_df=0
for field in "${DYNAMIC_FIELDS[@]}"; do
    exists=$(run_sql "SELECT COUNT(*) FROM dynamic_field WHERE name = '$field'")
    if [ "$exists" = "0" ] || [ -z "$exists" ]; then
        echo -e "${RED}✗ Dynamic Field: $field MISSING${NC}"
        ((missing_df++))
    else
        echo -e "${GREEN}✓ Dynamic Field: $field EXISTS${NC}"
        ((total_df++))
    fi
done

echo ""
echo -e "${BLUE}Dynamic Fields Summary: ${GREEN}$total_df found${NC}, ${RED}$missing_df missing${NC}"

echo ""
echo -e "${BLUE}=== CHECKING CRITICAL DATA ===${NC}"
echo ""

# Check AES encryption key
aes_count=$(run_sql "SELECT COUNT(*) FROM encryption_keys WHERE key_name = 'license_aes_key'")
if [ -n "$aes_count" ] && [ "$aes_count" = "1" ]; then
    echo -e "${GREEN}✓ AES Encryption Key: EXISTS${NC}"
else
    echo -e "${RED}✗ AES Encryption Key: MISSING${NC}"
fi

# Check default customer
default_customer=$(run_sql "SELECT COUNT(*) FROM customer_user WHERE login = 'default'")
if [ -n "$default_customer" ] && [ "$default_customer" = "1" ]; then
    echo -e "${GREEN}✓ Default Customer: EXISTS${NC}"
else
    echo -e "${RED}✗ Default Customer: MISSING${NC}"
fi

# Check ticket prefixes
prefix_count=$(run_sql "SELECT COUNT(*) FROM ticket_prefix")
if [ -n "$prefix_count" ] && [ "$prefix_count" -gt "0" ]; then
    echo -e "${GREEN}✓ Ticket Prefixes: $prefix_count configured${NC}"
    run_sql "SELECT type, prefix FROM ticket_prefix" | while read -r line; do
        echo "  - $line"
    done
else
    echo -e "${YELLOW}⚠ Ticket Prefixes: NONE configured${NC}"
fi

echo ""
echo -e "${BLUE}=== CHECKING PACKAGE STATUS ===${NC}"
echo ""

# Check if MSSTLite package is installed
su znuny -c "cd /opt/znuny-6.5.15/bin && ./otrs.Console.pl Admin::Package::List" 2>/dev/null | grep -A2 "MSSTLite" || echo -e "${RED}✗ MSSTLite Package: NOT FOUND${NC}"

echo ""
echo -e "${BLUE}=== CHECKING CONFIGURATION ===${NC}"
echo ""

# Check ticket number generator
TICKET_GEN=$(su znuny -c "cd /opt/znuny-6.5.15/bin && ./otrs.Console.pl Admin::Config::Read --setting-name Ticket::NumberGenerator" 2>/dev/null | grep "Effective value" | awk -F': ' '{print $2}')
if [[ "$TICKET_GEN" == *"AutoIncrementWithPrefix"* ]]; then
    echo -e "${GREEN}✓ Ticket Number Generator: Using AutoIncrementWithPrefix${NC}"
else
    echo -e "${YELLOW}⚠ Ticket Number Generator: $TICKET_GEN${NC}"
fi

echo ""
echo -e "${BLUE}=== SUMMARY ===${NC}"
echo ""

# Count issues
issues=0

# Check tables
for table in "${TABLES[@]}"; do
    count=$(run_sql "SELECT COUNT(*) FROM $table" 2>/dev/null || echo "MISSING")
    if [ "$count" = "MISSING" ] || [ "$count" = "0" ]; then
        ((issues++))
    fi
done

# Add missing dynamic fields to issues
issues=$((issues + missing_df))

# Check critical items
if [ -z "$aes_count" ] || [ "$aes_count" != "1" ]; then ((issues++)); fi
if [ -z "$default_customer" ] || [ "$default_customer" != "1" ]; then ((issues++)); fi

if [ $issues -eq 0 ]; then
    echo -e "${GREEN}✓ ALL SYSTEMS GO! No issues found.${NC}"
else
    echo -e "${RED}✗ FOUND $issues ISSUES that need attention!${NC}"
    echo ""
    echo "To fix missing data, you may need to:"
    echo "1. Run: ./migrate.sh"
    echo "2. Rebuild config: su znuny -c 'cd /opt/znuny-6.5.15/bin && ./otrs.Console.pl Maint::Config::Rebuild'"
    echo "3. Check package installation logs"
fi

echo ""
echo "========================================="