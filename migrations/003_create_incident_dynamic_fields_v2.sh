#!/bin/bash
# Migration: Create Incident Dynamic Fields (Based on Design Spec)
# Creates all dynamic fields required for the incident module per documentation


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Creating incident dynamic fields per design specification..."

# Function to create a dynamic field
create_dynamic_field() {
    local FIELD_NAME="$1"
    local FIELD_LABEL="$2"
    local FIELD_TYPE="$3"
    local FIELD_CONFIG="$4"
    
    # Check if field already exists
    FIELD_EXISTS=$(run_psql -t -c "SELECT COUNT(*) FROM dynamic_field WHERE name = '$FIELD_NAME';" | tr -d ' ')
    
    if [ "$FIELD_EXISTS" -gt 0 ]; then
        echo "    Field '$FIELD_NAME' already exists - skipping"
        return 0
    fi
    
    # Get next field order
    FIELD_ORDER=$(run_psql -t -c "SELECT COALESCE(MAX(field_order), 0) + 1 FROM dynamic_field;" | tr -d ' ')
    
    # Create the dynamic field
    echo "    Creating field: $FIELD_NAME ($FIELD_TYPE)"
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
        echo "    ✓ Created field: $FIELD_NAME"
        return 0
    else
        echo "    ✗ ERROR: Failed to create field: $FIELD_NAME"
        return 1
    fi
}

# Note: Process Management and Ticket Calendar fields from the image are not used in our incident module code

# Core Incident fields
create_dynamic_field "CI" "CI" "Text" '{"DefaultValue":"","Link":""}'

# Event/Monitoring fields - these need "Incident" prefix based on code
create_dynamic_field "IncidentAlarmID" "Alarm ID" "Text" '{"DefaultValue":"","Link":""}'
create_dynamic_field "IncidentEventBeginTime" "Event Begin Time" "DateTime" '{"DefaultValue":"","Link":"","DateRestriction":"","YearsPeriod":"0"}'
create_dynamic_field "IncidentEventDetectTime" "Event Detect Time" "DateTime" '{"DefaultValue":"","Link":"","DateRestriction":"","YearsPeriod":"0"}'
create_dynamic_field "IncidentEventID" "Event ID" "Text" '{"DefaultValue":"","Link":""}'
create_dynamic_field "IncidentEventMessage" "Event Message" "TextArea" '{"DefaultValue":"","Rows":"7","Cols":"42"}'
create_dynamic_field "IncidentEventSite" "Event Site" "Text" '{"DefaultValue":"","Link":""}'
create_dynamic_field "IncidentSourceDevice" "Source Device" "Text" '{"DefaultValue":"","Link":""}'

# MSI E-bonding fields - these need "Incident" prefix based on code
create_dynamic_field "IncidentMSITicketNumber" "MSI Ticket Number" "Text" '{"DefaultValue":"","Link":""}'
create_dynamic_field "IncidentMSICustomer" "MSI Customer" "Text" '{"DefaultValue":"","Link":""}'
create_dynamic_field "IncidentMSITicketSite" "MSI Ticket Site" "Text" '{"DefaultValue":"","Link":""}'
create_dynamic_field "IncidentMSITicketAssignee" "MSI Ticket Assignee" "Text" '{"DefaultValue":"","Link":""}'

# Additional fields we need that aren't shown in the image but are used in code
# IncidentNumber removed - we use Znuny's native ticket number
create_dynamic_field "IncidentSource" "Incident Source" "Dropdown" '{"DefaultValue":"Direct Input","PossibleValues":{"Direct Input":"Direct Input","Event Monitoring":"Event Monitoring"},"Link":"","PossibleNone":0,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "IncidentPriority" "Incident Priority" "Dropdown" '{"DefaultValue":"P3","PossibleValues":{"P1":"P1 - Critical","P2":"P2 - High","P3":"P3 - Medium","P4":"P4 - Low"},"Link":"","PossibleNone":0,"TranslatableValues":0,"TreeView":0}'

# Product Categories
create_dynamic_field "ProductCat1" "Product Category 1" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "ProductCat2" "Product Category 2" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "ProductCat3" "Product Category 3" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "ProductCat4" "Product Category 4" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'

# Operational Categories
create_dynamic_field "OperationalCat1" "Operational Category 1" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "OperationalCat2" "Operational Category 2" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "OperationalCat3" "Operational Category 3" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'

# Resolution fields
create_dynamic_field "ResolutionCat1" "Resolution Category 1" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "ResolutionCat2" "Resolution Category 2" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "ResolutionCat3" "Resolution Category 3" "Dropdown" '{"DefaultValue":"","PossibleValues":{},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "ResolutionCode" "Resolution Code" "Dropdown" '{"DefaultValue":"","PossibleValues":{"RES001":"RES001 - Issue Resolved","RES002":"RES002 - Workaround Applied","RES003":"RES003 - No Action Required","RES004":"RES004 - Duplicate"},"Link":"","PossibleNone":1,"TranslatableValues":0,"TreeView":0}'
create_dynamic_field "ResolutionNotes" "Resolution Notes" "TextArea" '{"DefaultValue":"","Rows":"7","Cols":"42"}'

# Work Notes
create_dynamic_field "WorkNotes" "Work Notes" "TextArea" '{"DefaultValue":"","Rows":"7","Cols":"42"}'

# Description field
create_dynamic_field "Description" "Description" "TextArea" '{"DefaultValue":"","Rows":"7","Cols":"42"}'

# Incident specific time tracking
create_dynamic_field "IncidentResponseTime" "Incident Response Time" "DateTime" '{"DefaultValue":"","Link":"","DateRestriction":"","YearsPeriod":"0"}'
create_dynamic_field "IncidentResolvedTime" "Incident Resolved Time" "DateTime" '{"DefaultValue":"","Link":"","DateRestriction":"","YearsPeriod":"0"}'

echo "  Incident dynamic fields migration completed!"
exit 0