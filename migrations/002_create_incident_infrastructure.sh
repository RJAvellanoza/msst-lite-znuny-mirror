#!/bin/bash
# Migration: Create Incident Infrastructure
# This migration creates the incident ticket type and MSI/NOC queues


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Creating incident ticket type..."

# Create Incident ticket type if it doesn't exist
run_psql << EOF
-- Check if Incident type exists, if not create it
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ticket_type WHERE name = 'Incident') THEN
        INSERT INTO ticket_type (name, valid_id, create_time, create_by, change_time, change_by)
        VALUES ('Incident', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1);
        RAISE NOTICE 'Created Incident ticket type';
    ELSE
        RAISE NOTICE 'Incident ticket type already exists';
    END IF;
END
\$\$;
EOF

if [ $? -ne 0 ]; then
    echo "Error: Failed to create incident ticket type"
    exit 1
fi

echo "  Skipping MSI/NOC queue creation (now using Support Group queue instead)..."

# Note: MSI/NOC queues are no longer needed - all incidents use Support Group queue
# The code below is commented out but kept for reference

: <<'COMMENTED_OUT'
# Get users group ID (should be 1, but let's be safe)
USERS_GROUP_ID=$(run_psql -t -c "SELECT id FROM groups WHERE name = 'users' LIMIT 1;" | tr -d ' ')

if [ -z "$USERS_GROUP_ID" ]; then
    echo "Warning: Could not find 'users' group, using group ID 1"
    USERS_GROUP_ID=1
fi

echo "  Using group ID: $USERS_GROUP_ID"

# Create MSI/NOC queues
run_psql << EOF
-- Create MSIAdmin queue
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM queue WHERE name = 'MSIAdmin') THEN
        INSERT INTO queue (
            name, group_id, unlock_timeout, first_response_time, update_time, 
            solution_time, follow_up_id, follow_up_lock, system_address_id, 
            salutation_id, signature_id, comments, valid_id, create_time, 
            create_by, change_time, change_by
        ) VALUES (
            'MSIAdmin', $USERS_GROUP_ID, 0, 240, 480, 
            1440, 1, 0, 1, 
            1, 1, 'MSI Administrator queue for incident management', 1, CURRENT_TIMESTAMP,
            1, CURRENT_TIMESTAMP, 1
        );
        RAISE NOTICE 'Created MSIAdmin queue';
    ELSE
        RAISE NOTICE 'MSIAdmin queue already exists';
    END IF;
END
\$\$;

-- Create NOCAdmin queue  
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM queue WHERE name = 'NOCAdmin') THEN
        INSERT INTO queue (
            name, group_id, unlock_timeout, first_response_time, update_time,
            solution_time, follow_up_id, follow_up_lock, system_address_id,
            salutation_id, signature_id, comments, valid_id, create_time,
            create_by, change_time, change_by
        ) VALUES (
            'NOCAdmin', $USERS_GROUP_ID, 0, 240, 480,
            1440, 1, 0, 1,
            1, 1, 'NOC Administrator queue for network operations', 1, CURRENT_TIMESTAMP,
            1, CURRENT_TIMESTAMP, 1
        );
        RAISE NOTICE 'Created NOCAdmin queue';
    ELSE
        RAISE NOTICE 'NOCAdmin queue already exists';
    END IF;
END
\$\$;

-- Create NOCUser queue
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM queue WHERE name = 'NOCUser') THEN
        INSERT INTO queue (
            name, group_id, unlock_timeout, first_response_time, update_time,
            solution_time, follow_up_id, follow_up_lock, system_address_id,
            salutation_id, signature_id, comments, valid_id, create_time,
            create_by, change_time, change_by
        ) VALUES (
            'NOCUser', $USERS_GROUP_ID, 0, 240, 480,
            1440, 1, 0, 1,
            1, 1, 'NOC User queue for network operations', 1, CURRENT_TIMESTAMP,
            1, CURRENT_TIMESTAMP, 1
        );
        RAISE NOTICE 'Created NOCUser queue';
    ELSE
        RAISE NOTICE 'NOCUser queue already exists';
    END IF;
END
\$\$;
EOF
COMMENTED_OUT

echo "  Done! Created incident infrastructure."

exit 0