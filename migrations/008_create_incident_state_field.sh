#!/bin/bash
# Migration: Create MsstIncidentState Dynamic Field
# Creates the incident state dynamic field that maps to Znuny ticket states

# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Creating MsstIncidentState dynamic field..."

# Get next field order
FIELD_ORDER=$(run_psql -t -c "SELECT COALESCE(MAX(field_order), 0) + 1 FROM dynamic_field;" | tr -d ' ')

# Create the MsstIncidentState dynamic field
run_psql << EOF
INSERT INTO dynamic_field (
    internal_field, name, label, field_order, field_type, object_type, 
    config, valid_id, create_time, create_by, change_time, change_by
) VALUES (
    0, 'MsstIncidentState', 'Incident State', $FIELD_ORDER, 'Dropdown', 'Ticket',
    '{
        "DefaultValue": "new",
        "PossibleValues": {
            "new": "New",
            "assigned": "Assigned", 
            "in progress": "In Progress",
            "pending reminder": "Pending",
            "resolved": "Resolved",
            "closed successful": "Closed",
            "cancelled": "Cancelled"
        },
        "Link": "",
        "PossibleNone": 0,
        "TranslatableValues": 0,
        "TreeView": 0
    }', 
    1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1
)
ON CONFLICT (name) DO NOTHING;
EOF

if [ $? -eq 0 ]; then
    echo "  ✓ MsstIncidentState dynamic field created successfully"
else
    echo "  ✗ Failed to create MsstIncidentState dynamic field"
    exit 1
fi

exit 0