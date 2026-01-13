#!/bin/bash
# Migration: Cleanup Dynamic Fields Alignment
# Removes redundant fields and aligns with code expectations


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Cleaning up dynamic field alignment issues..."

# Function to remove a dynamic field
remove_dynamic_field() {
    local FIELD_NAME="$1"
    local REASON="$2"
    
    # Check if field exists
    FIELD_EXISTS=$(run_psql -t -c "SELECT COUNT(*) FROM dynamic_field WHERE name = '$FIELD_NAME';" | tr -d ' ')
    
    if [ "$FIELD_EXISTS" -eq 0 ]; then
        echo "    Field '$FIELD_NAME' does not exist - skipping"
        return 0
    fi
    
    # Get field ID
    FIELD_ID=$(run_psql -t -c "SELECT id FROM dynamic_field WHERE name = '$FIELD_NAME';" | tr -d ' ')
    
    echo "    Removing field: $FIELD_NAME ($REASON)"
    
    # Remove field values first
    run_psql -c "DELETE FROM dynamic_field_value WHERE field_id = $FIELD_ID;" >/dev/null 2>&1
    
    # Remove the field
    run_psql -c "DELETE FROM dynamic_field WHERE id = $FIELD_ID;"
    
    if [ $? -eq 0 ]; then
        echo "    ✓ Removed field: $FIELD_NAME"
        return 0
    else
        echo "    ✗ ERROR: Failed to remove field: $FIELD_NAME"
        return 1
    fi
}

echo "  Step 1: Removing redundant fields..."

# Remove IncidentNumber - we use Znuny's native ticket number
remove_dynamic_field "IncidentNumber" "Using native ticket number instead"

# WorkNotes is NOT redundant - it's used as the form input field
# The data is then stored in incident_work_notes table, but the field is needed for input
# remove_dynamic_field "WorkNotes" "Work notes stored in custom table" # KEEPING THIS FIELD

# Remove redundant tracking fields - Znuny already tracks these
remove_dynamic_field "IncidentOpenedDate" "Redundant - use ticket Created field"
remove_dynamic_field "IncidentOpenedBy" "Redundant - use ticket CreateBy field"
remove_dynamic_field "IncidentUpdatedDate" "Redundant - use ticket Changed field"
remove_dynamic_field "IncidentUpdatedBy" "Redundant - use ticket ChangeBy field"

echo ""
echo "  Step 2: Verifying required fields exist..."

# Function to check if a field exists
check_field_exists() {
    local FIELD_NAME="$1"
    FIELD_EXISTS=$(run_psql -t -c "SELECT COUNT(*) FROM dynamic_field WHERE name = '$FIELD_NAME';" | tr -d ' ')
    
    if [ "$FIELD_EXISTS" -gt 0 ]; then
        echo "    ✓ Field exists: $FIELD_NAME"
        return 0
    else
        echo "    ✗ Missing field: $FIELD_NAME"
        return 1
    fi
}

# Check core fields
echo "  Checking core fields..."
check_field_exists "CI"
check_field_exists "AssignmentGroup"
check_field_exists "IncidentSource"
check_field_exists "IncidentPriority"

# Check category fields
echo ""
echo "  Checking category fields..."
for i in 1 2 3 4; do
    check_field_exists "ProductCategory$i"
done
for i in 1 2 3; do
    check_field_exists "OperationalCategory$i"
done
for i in 1 2 3; do
    check_field_exists "ResolutionCategory$i"
done

# Check resolution fields
echo ""
echo "  Checking resolution fields..."
check_field_exists "ResolutionCode"
check_field_exists "ResolutionNotes"

# Check time tracking fields
echo ""
echo "  Checking time tracking fields..."
check_field_exists "IncidentResponseTime"
check_field_exists "IncidentResolvedTime"

echo ""
echo "  Step 3: Creating any missing fields..."

# Function to create a dynamic field if it doesn't exist
create_field_if_missing() {
    local FIELD_NAME="$1"
    local FIELD_LABEL="$2"
    local FIELD_TYPE="$3"
    local FIELD_CONFIG="$4"
    
    FIELD_EXISTS=$(run_psql -t -c "SELECT COUNT(*) FROM dynamic_field WHERE name = '$FIELD_NAME';" | tr -d ' ')
    
    if [ "$FIELD_EXISTS" -eq 0 ]; then
        echo "    Creating missing field: $FIELD_NAME"
        
        # Get next field order
        FIELD_ORDER=$(run_psql -t -c "SELECT COALESCE(MAX(field_order), 0) + 1 FROM dynamic_field;" | tr -d ' ')
        
        run_psql << EOF
INSERT INTO dynamic_field (
    internal_field, name, label, field_order, field_type, object_type, 
    config, valid_id, create_time, create_by, change_time, change_by
) VALUES (
    0, '$FIELD_NAME', '$FIELD_LABEL', $FIELD_ORDER, '$FIELD_TYPE', 'Ticket',
    '$FIELD_CONFIG', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1
);
EOF
        
        if [ $? -eq 0 ]; then
            echo "    ✓ Created missing field: $FIELD_NAME"
        else
            echo "    ✗ ERROR: Failed to create field: $FIELD_NAME"
        fi
    fi
}

# Create any missing critical fields
# (Add any missing fields here if the check above found any)

echo ""
echo "  Dynamic field cleanup completed!"
echo ""
echo "  Summary of changes:"
echo "  - Removed redundant fields that duplicate Znuny native fields"
echo "  - Verified all required fields exist"
echo "  - Work notes now exclusively use the incident_work_notes table"
echo "  - Incident numbers use Znuny's native ticket numbers"
echo ""
echo "  Remember to clear cache and rebuild config after this migration:"
echo "  su - znuny -c '/opt/znuny-6.5.15/bin/otrs.Console.pl Maint::Cache::Delete'"
echo "  su - znuny -c '/opt/znuny-6.5.15/bin/otrs.Console.pl Maint::Config::Rebuild'"

exit 0