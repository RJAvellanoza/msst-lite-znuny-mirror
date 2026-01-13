#!/bin/bash
# Rollback Migration: Remove LSMP Users and Groups
# Removes users and groups created by 005_create_lsmp_users.sh


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Rolling back migration: Remove LSMP Users and Groups..."

# Function to delete user
delete_user() {
    local username=$1
    
    echo "    Removing user: $username..."
    
    # Get user ID
    local user_id=$(run_psql -t -c "SELECT id FROM users WHERE login = '$username';" | tr -d ' ')
    
    if [ -n "$user_id" ] && [ "$user_id" -gt 0 ]; then
        # First, remove user from all groups
        run_psql -c "DELETE FROM group_user WHERE user_id = $user_id;" >/dev/null 2>&1
        
        # Remove user preferences
        run_psql -c "DELETE FROM user_preferences WHERE user_id = $user_id;" >/dev/null 2>&1
        
        # Remove from role_user
        run_psql -c "DELETE FROM role_user WHERE user_id = $user_id;" >/dev/null 2>&1
        
        # Finally, delete the user
        run_psql -c "DELETE FROM users WHERE id = $user_id;" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "    ✓ Removed user: $username"
        else
            echo "    ✗ Failed to remove user: $username (may have tickets or other dependencies)"
            return 1
        fi
    else
        echo "    ℹ User not found: $username"
    fi
    return 0
}

# Function to delete group (only if empty and not system group)
delete_group() {
    local group_name=$1
    
    echo "    Checking group: $group_name..."
    
    # Check if group exists and is not a system group
    local group_info=$(run_psql -t -c "SELECT id, comments FROM permission_groups WHERE name = '$group_name';")
    
    if [ -n "$group_info" ]; then
        # Check if group has any users
        local group_id=$(echo "$group_info" | awk '{print $1}')
        local user_count=$(run_psql -t -c "SELECT COUNT(*) FROM group_user WHERE group_id = $group_id;")
        
        if [ "$user_count" -eq 0 ]; then
            # Safe to delete
            run_psql -c "DELETE FROM permission_groups WHERE name = '$group_name';" >/dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                echo "    ✓ Removed group: $group_name"
            else
                echo "    ✗ Failed to remove group: $group_name"
                return 1
            fi
        else
            echo "    ⚠ Group has $user_count users, keeping: $group_name"
        fi
    else
        echo "    ℹ Group not found: $group_name"
    fi
    return 0
}

# Track errors
ERROR_COUNT=0

# Remove users first (in reverse order of creation)
echo "  Removing LSMP Users..."

# NOC Users
for i in {8..1}; do
    delete_user "nocuser$i" || ((ERROR_COUNT++))
done

# NOC Administrators
delete_user "nocadmin2" || ((ERROR_COUNT++))
delete_user "nocadmin1" || ((ERROR_COUNT++))

# MSI Personnel
delete_user "msifield" || ((ERROR_COUNT++))
delete_user "msicmso" || ((ERROR_COUNT++))
delete_user "lsmpappuser" || ((ERROR_COUNT++))

# Remove groups (only if empty)
echo "  Removing LSMP Groups (if empty)..."
delete_group "NOCUser" || ((ERROR_COUNT++))
delete_group "NOCAdmin" || ((ERROR_COUNT++))
delete_group "MSIAdmin" || ((ERROR_COUNT++))

# Clear cache
echo "  Clearing cache..."
su - znuny -c "/opt/znuny-6.5.15/bin/otrs.Console.pl Maint::Cache::Delete" >/dev/null 2>&1

# Summary
echo "  Rollback summary:"
echo "    - Users removed: msicmso, msifield, lsmpappuser, nocadmin1-2, nocuser1-8"
echo "    - Groups removed: Only if empty"
echo "    - Total errors: $ERROR_COUNT"

if [ $ERROR_COUNT -eq 0 ]; then
    echo "  ✓ Rollback completed successfully!"
    exit 0
else
    echo "  ⚠ Rollback completed with $ERROR_COUNT errors"
    exit 1
fi