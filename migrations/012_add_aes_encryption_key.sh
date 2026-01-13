#!/bin/bash
# Migration: Add AES encryption key for license decryption

# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Adding AES encryption key for license decryption..."

# Check if the key already exists
KEY_EXISTS=$(PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM encryption_keys WHERE key_name = 'license_aes_key';" 2>/dev/null | xargs)

if [ "$KEY_EXISTS" = "0" ]; then
    # Insert the AES key (base64 encoded binary key from original working implementation)
    # This is the same key that was used in commit b22eef99
    AES_KEY_B64="/Px3bgjiiLk8yy4UPqxIO3/B6NTiZYcwymkWDhIrCdA="
    
    PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -c "
        INSERT INTO encryption_keys (key_name, key_value, created_time, created_by) 
        VALUES ('license_aes_key', '$AES_KEY_B64', current_timestamp, 1);
    "
    
    if [ $? -eq 0 ]; then
        echo "    ✓ AES encryption key added successfully"
    else
        echo "    ✗ Failed to add AES encryption key"
        exit 1
    fi
else
    echo "    ✓ AES encryption key already exists, skipping"
fi

exit 0