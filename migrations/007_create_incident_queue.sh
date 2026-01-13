#!/bin/bash
# Migration: Create Incident Queue
# This migration creates the main Incident queue for incident management

# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Creating Incident queue..."

# Get users group ID (should be 1, but let's be safe)
USERS_GROUP_ID=$(run_psql -t -c "SELECT id FROM groups WHERE name = 'users' LIMIT 1;" 2>/dev/null | tr -d ' ')

if [ -z "$USERS_GROUP_ID" ]; then
    echo "Warning: Could not find 'users' group, using group ID 1"
    USERS_GROUP_ID=1
fi

echo "  Using group ID: $USERS_GROUP_ID"

# Create Incident queue
run_psql << EOF
-- Create Incident queue
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM queue WHERE name = 'Incident') THEN
        INSERT INTO queue (
            name, group_id, unlock_timeout, first_response_time, update_time, 
            solution_time, follow_up_id, follow_up_lock, system_address_id, 
            salutation_id, signature_id, comments, valid_id, create_time, 
            create_by, change_time, change_by
        ) VALUES (
            'Incident', $USERS_GROUP_ID, 0, 240, 480, 
            1440, 1, 0, 1, 
            1, 1, 'Main queue for incident management', 1, CURRENT_TIMESTAMP,
            1, CURRENT_TIMESTAMP, 1
        );
        RAISE NOTICE 'Created Incident queue';
    ELSE
        RAISE NOTICE 'Incident queue already exists';
    END IF;
END
\$\$;
EOF

if [ $? -ne 0 ]; then
    echo "Error: Failed to create Incident queue"
    exit 1
fi

echo "  Done! Created Incident queue."

exit 0