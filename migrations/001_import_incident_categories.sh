#!/bin/bash
# Migration: Import Incident Categories
# This migration imports category data from CSV files


# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Importing incident categories..."

# Get script directory
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$MIGRATION_DIR")"

# Run the import script
if [ -f "$BASE_DIR/Custom/bin/ImportIncidentCategories.pl" ]; then
    perl "$BASE_DIR/Custom/bin/ImportIncidentCategories.pl"
    exit $?
else
    echo "  ERROR: ImportIncidentCategories.pl not found!"
    exit 1
fi