#!/bin/bash
#
# Migration: Create custom incident states in Znuny
# 
# This migration creates the custom states needed for the incident management system:
# - Assigned
# - In Progress
# - Resolved (maps to existing 'closed successful')
# - Cancelled (maps to existing 'closed unsuccessful')
# - Pending (maps to existing 'pending reminder')
#


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Creating custom incident states..."

# Check if states already exist before creating
run_psql <<EOF
-- Start transaction
BEGIN;

-- Create state_type entries if they don't exist
INSERT INTO ticket_state_type (name, comments, create_by, create_time, change_by, change_time)
SELECT 'open', 'Open state type', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM ticket_state_type WHERE name = 'open');

INSERT INTO ticket_state_type (name, comments, create_by, create_time, change_by, change_time)
SELECT 'closed', 'Closed state type', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM ticket_state_type WHERE name = 'closed');

INSERT INTO ticket_state_type (name, comments, create_by, create_time, change_by, change_time)
SELECT 'pending reminder', 'Pending reminder state type', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM ticket_state_type WHERE name = 'pending reminder');

-- Create Assigned state (open type)
INSERT INTO ticket_state (name, comments, type_id, valid_id, create_by, create_time, change_by, change_time)
SELECT 'assigned', 'Ticket has been assigned to a group/agent', 
       (SELECT id FROM ticket_state_type WHERE name = 'open'),
       1, 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM ticket_state WHERE name = 'assigned');

-- Create In Progress state (open type)
INSERT INTO ticket_state (name, comments, type_id, valid_id, create_by, create_time, change_by, change_time)
SELECT 'in progress', 'Ticket is being actively worked on',
       (SELECT id FROM ticket_state_type WHERE name = 'open'),
       1, 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM ticket_state WHERE name = 'in progress');

-- Create Resolved state (closed type) - different from 'closed successful'
INSERT INTO ticket_state (name, comments, type_id, valid_id, create_by, create_time, change_by, change_time)
SELECT 'resolved', 'Issue has been resolved but not yet confirmed by customer',
       (SELECT id FROM ticket_state_type WHERE name = 'closed'),
       1, 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM ticket_state WHERE name = 'resolved');

-- Create Cancelled state (closed type) - different from 'closed unsuccessful'
INSERT INTO ticket_state (name, comments, type_id, valid_id, create_by, create_time, change_by, change_time)
SELECT 'cancelled', 'Ticket was cancelled',
       (SELECT id FROM ticket_state_type WHERE name = 'closed'),
       1, 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM ticket_state WHERE name = 'cancelled');

-- Show the states we created/have
SELECT id, name, comments FROM ticket_state 
WHERE name IN ('new', 'assigned', 'open', 'in progress', 'pending reminder', 'resolved', 'closed successful', 'cancelled')
ORDER BY id;

COMMIT;
EOF

if [ $? -eq 0 ]; then
    echo "  ✓ Custom incident states created successfully"
    
    # Show state mapping
    echo ""
    echo "  State Mapping:"
    echo "  -------------"
    echo "  Incident State    -> Znuny State"
    echo "  New               -> new"
    echo "  Assigned          -> assigned"
    echo "  In Progress       -> in progress"
    echo "  Pending           -> pending reminder"
    echo "  Resolved          -> resolved"
    echo "  Closed            -> closed successful"
    echo "  Cancelled         -> cancelled"
    echo ""
else
    echo "  ✗ Failed to create custom incident states"
    exit 1
fi

exit 0