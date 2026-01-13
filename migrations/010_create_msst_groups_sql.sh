#!/bin/bash
# Migration: Create MSST Groups (SQL version)
# Creates MSIAdmin, NOCAdmin, and NOCUser groups for LSMP using direct SQL


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Creating MSST groups via SQL..."

# Function to create a group
create_group_sql() {
    local GROUP_NAME="$1"
    local GROUP_COMMENT="$2"
    
    # Check if group already exists
    GROUP_EXISTS=$(run_psql -t -c "SELECT COUNT(*) FROM permission_groups WHERE name = '$GROUP_NAME';" | tr -d ' ')
    
    if [ "$GROUP_EXISTS" -gt 0 ]; then
        echo "    Group '$GROUP_NAME' already exists - skipping"
        return 0
    fi
    
    # Create the group
    run_psql -c "
        INSERT INTO permission_groups (name, comments, valid_id, create_time, create_by, change_time, change_by)
        VALUES ('$GROUP_NAME', '$GROUP_COMMENT', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1);"
    
    if [ $? -eq 0 ]; then
        echo "    Created group '$GROUP_NAME'"
        return 0
    else
        echo "    ERROR: Failed to create group '$GROUP_NAME'"
        return 1
    fi
}

# Create the groups
create_group_sql "MSIAdmin" "MSI Administrators - Full incident management access"
create_group_sql "NOCAdmin" "NOC Administrators - Network operations center admins"
create_group_sql "NOCUser" "NOC Users - Network operations center users"

# Get group IDs
echo "  Setting up queue permissions..."

# Get the Support Group queue ID
SUPPORT_GROUP_QUEUE_ID=$(run_psql -t -c "SELECT id FROM queue WHERE name = 'Support Group';" | tr -d ' ')

if [ -z "$SUPPORT_GROUP_QUEUE_ID" ]; then
    echo "    WARNING: Support Group queue not found - permissions not set"
else
    # Get group IDs for MSST groups
    for GROUP_NAME in MSIAdmin NOCAdmin NOCUser; do
        GROUP_ID=$(run_psql -t -c "SELECT id FROM permission_groups WHERE name = '$GROUP_NAME';" | tr -d ' ')
        
        if [ -n "$GROUP_ID" ]; then
            # Check if permission already exists
            PERM_EXISTS=$(run_psql -t -c "SELECT COUNT(*) FROM group_queue WHERE group_id = $GROUP_ID AND queue_id = $SUPPORT_GROUP_QUEUE_ID;" | tr -d ' ')
            
            if [ "$PERM_EXISTS" -eq 0 ]; then
                # Insert queue-group permissions
                run_psql -c "
                    INSERT INTO group_queue (group_id, queue_id, permission_key, permission_value, create_time, create_by, change_time, change_by)
                    VALUES 
                        ($GROUP_ID, $SUPPORT_GROUP_QUEUE_ID, 'ro', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1),
                        ($GROUP_ID, $SUPPORT_GROUP_QUEUE_ID, 'move_into', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1),
                        ($GROUP_ID, $SUPPORT_GROUP_QUEUE_ID, 'create', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1),
                        ($GROUP_ID, $SUPPORT_GROUP_QUEUE_ID, 'note', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1),
                        ($GROUP_ID, $SUPPORT_GROUP_QUEUE_ID, 'owner', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1),
                        ($GROUP_ID, $SUPPORT_GROUP_QUEUE_ID, 'priority', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1),
                        ($GROUP_ID, $SUPPORT_GROUP_QUEUE_ID, 'rw', 1, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP, 1);"
                
                if [ $? -eq 0 ]; then
                    echo "    Set permissions for $GROUP_NAME on Support Group queue"
                else
                    echo "    WARNING: Failed to set some permissions for $GROUP_NAME"
                fi
            else
                echo "    Permissions for $GROUP_NAME already exist - skipping"
            fi
        fi
    done
fi

echo "  MSST groups migration completed!"
exit 0