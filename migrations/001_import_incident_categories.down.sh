#!/bin/bash
# Rollback: Import Incident Categories
# This removes category data and tables


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Rolling back incident categories..."

# Drop all category tables
run_psql << EOF
DROP TABLE IF EXISTS incident_product_category CASCADE;
DROP TABLE IF EXISTS incident_operational_category CASCADE;
DROP TABLE IF EXISTS incident_resolution_category CASCADE;
EOF

if [ $? -eq 0 ]; then
    echo "  ✓ Category tables dropped successfully"
    exit 0
else
    echo "  ✗ Failed to drop category tables"
    exit 1
fi