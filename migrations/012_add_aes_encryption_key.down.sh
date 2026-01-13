#!/bin/bash
# Migration Rollback: Remove AES encryption key

# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Removing AES encryption key..."

# Remove the AES key
PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -c "
    DELETE FROM encryption_keys WHERE key_name = 'license_aes_key';
"

if [ $? -eq 0 ]; then
    echo "    ✓ AES encryption key removed successfully"
else
    echo "    ✗ Failed to remove AES encryption key"
    exit 1
fi

exit 0