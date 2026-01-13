#!/bin/bash
# Migration: Remove AssignmentGroup Dynamic Field
# Removes the AssignmentGroup field as all incidents now use 'Support Group' queue

# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Checking for AssignmentGroup dynamic field..."

# First check if the field exists
FIELD_EXISTS=$(run_psql -t -c "SELECT COUNT(*) FROM dynamic_field WHERE name = 'AssignmentGroup';" | tr -d ' ')

if [ "$FIELD_EXISTS" -eq 0 ]; then
    echo "  AssignmentGroup field doesn't exist - nothing to do"
    exit 0
fi

echo "  Removing AssignmentGroup dynamic field..."

# Delete the AssignmentGroup dynamic field and its values
run_psql << EOF
BEGIN;

-- Delete all values for AssignmentGroup field
DELETE FROM dynamic_field_value 
WHERE field_id = (SELECT id FROM dynamic_field WHERE name = 'AssignmentGroup');

-- Delete the dynamic field itself
DELETE FROM dynamic_field 
WHERE name = 'AssignmentGroup';

COMMIT;
EOF

if [ $? -eq 0 ]; then
    echo "  ✓ AssignmentGroup dynamic field removed successfully"
else
    echo "  ✗ Failed to remove AssignmentGroup dynamic field"
    exit 1
fi

exit 0