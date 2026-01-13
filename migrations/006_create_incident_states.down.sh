#!/bin/bash
#
# Rollback: Remove custom incident states from Znuny
# 
# This removes the custom states created for incident management
# Note: This will fail if any tickets are using these states
#


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Rolling back custom incident states..."

run_psql <<EOF
-- Start transaction
BEGIN;

-- First check if any tickets are using these states
SELECT COUNT(*) as ticket_count, s.name as state_name
FROM ticket t
JOIN ticket_state s ON t.ticket_state_id = s.id
WHERE s.name IN ('assigned', 'in progress', 'resolved', 'cancelled')
GROUP BY s.name;

-- Remove the custom states (will fail if tickets exist with these states)
DELETE FROM ticket_state WHERE name = 'assigned';
DELETE FROM ticket_state WHERE name = 'in progress';
DELETE FROM ticket_state WHERE name = 'resolved';
DELETE FROM ticket_state WHERE name = 'cancelled';

COMMIT;
EOF

if [ $? -eq 0 ]; then
    echo "  ✓ Custom incident states removed successfully"
else
    echo "  ✗ Failed to remove custom incident states"
    echo "  Note: States cannot be removed if tickets are using them"
    exit 1
fi

exit 0