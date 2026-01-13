#!/bin/bash
# Migration: Create LSMP Users and Groups
# Creates default users and groups according to LSMP hierarchy


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Running migration: Create LSMP Users and Groups..."

# Function to create group if not exists
create_group() {
    local group_name=$1
    local comment=$2
    
    echo "    Creating group: $group_name..."
    su - znuny -c "/opt/znuny-6.5.15/bin/otrs.Console.pl Admin::Group::Add \
        --name '$group_name' \
        --comment '$comment'" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "    ✓ Created group: $group_name"
    else
        # Check if group exists
        local group_exists=$(run_psql -t -c "SELECT COUNT(*) FROM permission_groups WHERE name = '$group_name';")
        if [ $group_exists -gt 0 ]; then
            echo "    ℹ Group already exists: $group_name"
        else
            echo "    ✗ Failed to create group: $group_name"
            return 1
        fi
    fi
    return 0
}

# Function to create user
create_user() {
    local username=$1
    local firstname=$2
    local lastname=$3
    local email=$4
    local groups=$5
    local password="tmp12345"
    
    # Convert groups string to --group parameters
    local group_params=""
    IFS=';' read -ra GROUP_ARRAY <<< "$groups"
    for g in "${GROUP_ARRAY[@]}"; do
        # Extract group name (before the colon)
        local group_name="${g%:*}"
        group_params="$group_params --group '$group_name'"
    done
    
    echo "    Creating user: $username..."
    su - znuny -c "/opt/znuny-6.5.15/bin/otrs.Console.pl Admin::User::Add \
        --user-name '$username' \
        --first-name '$firstname' \
        --last-name '$lastname' \
        --email-address '$email' \
        $group_params \
        --password '$password'" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "    ✓ Created user: $username"
    else
        # Check if user exists
        local user_exists=$(run_psql -t -c "SELECT COUNT(*) FROM users WHERE login = '$username';")
        if [ $user_exists -gt 0 ]; then
            echo "    ℹ User already exists: $username"
        else
            echo "    ✗ Failed to create user: $username"
            return 1
        fi
    fi
    return 0
}

# Track errors
ERROR_COUNT=0

# Create groups
echo "  Creating LSMP Groups..."
create_group "MSIAdmin" "MSI D&Ts personnel with Super Admin/Root level access" || ((ERROR_COUNT++))
create_group "NOCAdmin" "NOC Administrators" || ((ERROR_COUNT++))
create_group "NOCUser" "NOC operational staff" || ((ERROR_COUNT++))

# Create users
echo "  Creating LSMP Users..."

# MSI Personnel
create_user "msicmso" "MSI CMSO" "Auto" "msicmso@gmail.com" "admin:rw;MSIAdmin:rw;NOCAdmin:rw;NOCUser:rw;users:rw" || ((ERROR_COUNT++))
create_user "msifield" "MSI Field" "Auto" "msifield@gmail.com" "admin:rw;MSIAdmin:rw;NOCUser:rw;users:rw" || ((ERROR_COUNT++))
create_user "lsmpappuser" "LSMP App User" "Auto" "lsmpappuser@gmail.com" "admin:rw;MSIAdmin:rw;NOCAdmin:rw;NOCUser:rw;users:rw" || ((ERROR_COUNT++))

# NOC Administrators
create_user "nocadmin1" "NOC Admin1" "Auto" "nocadmin1@gmail.com" "admin:rw;NOCAdmin:rw;NOCUser:rw;users:rw" || ((ERROR_COUNT++))
create_user "nocadmin2" "NOC Admin2" "Auto" "nocadmin2@gmail.com" "admin:rw;NOCAdmin:rw;NOCUser:rw;users:rw" || ((ERROR_COUNT++))

# NOC Users
for i in {1..8}; do
    create_user "nocuser$i" "NOC User$i" "Auto" "nocuser$i@gmail.com" "NOCUser:rw;users:rw" || ((ERROR_COUNT++))
done

# Clear cache
echo "  Clearing cache..."
su - znuny -c "/opt/znuny-6.5.15/bin/otrs.Console.pl Maint::Cache::Delete" >/dev/null 2>&1

# Summary
echo "  Migration summary:"
echo "    - Groups created: MSIAdmin, NOCAdmin, NOCUser"
echo "    - Users created: msicmso, msifield, lsmpappuser, nocadmin1-2, nocuser1-8"
echo "    - Total errors: $ERROR_COUNT"

if [ $ERROR_COUNT -eq 0 ]; then
    echo "  ✓ Migration completed successfully!"
    exit 0
else
    echo "  ⚠ Migration completed with $ERROR_COUNT errors"
    exit 1
fi
