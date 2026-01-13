# MSSTLite Migration System Documentation

## Overview

The MSSTLite package uses a custom migration system to handle database updates, data imports, and other one-time setup tasks that are too complex or large to include in the SOPM package file.

## Why a Separate Migration System?

1. **SOPM Size**: The main SOPM file is already 1500+ lines. Adding large data imports would make it unwieldy.
2. **Control**: Migrations can be run manually when needed, not automatically during every install/upgrade.
3. **Tracking**: The system tracks which migrations have been executed to prevent duplicate runs.
4. **Flexibility**: Easy to add new migrations without modifying the package.
5. **Data Files**: Large CSV files (like categories) don't bloat the OPM package.

## Architecture

```
msst-lite-znuny/
├── migrate.sh                 # Main migration runner script
├── migrations/               # Directory containing migration scripts
│   └── 001_import_incident_categories.sh
└── Custom/
    ├── bin/
    │   └── ImportIncidentCategories.pl  # Category import script
    └── var/
        └── categories/       # CSV data files
            ├── LSMP New Categories (...) - All Operational Cats.csv
            ├── LSMP New Categories (...) - All Prod Cats.csv
            └── LSMP New Categories (...) - All Resolution Cats.csv
```

## How It Works

### Migration Tracking

The system creates a `msst_migrations` table in PostgreSQL:

```sql
CREATE TABLE msst_migrations (
    id SERIAL PRIMARY KEY,
    migration_name VARCHAR(255) UNIQUE NOT NULL,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

This tracks which migrations have been run to prevent duplicate execution.

### Migration Execution Flow

1. `migrate.sh` scans the `migrations/` directory for `*.sh` files
2. Files are sorted alphabetically (use numbered prefixes like `001_`, `002_`)
3. For each migration:
   - Check if it's already in `msst_migrations` table
   - If not, execute the migration script
   - On success, record in `msst_migrations`
   - On failure, stop the entire process

### Running Migrations

```bash
# From the msst-lite-znuny directory
./migrate.sh

# Output:
=========================================
MSSTLite Migration Runner
=========================================
Checking migration tracking...
Running: 001_import_incident_categories.sh
  Importing incident categories...
  ...
✓ Completed: 001_import_incident_categories.sh

Successfully ran 1 migration(s)
=========================================
```

## Current Migrations

### 001_import_incident_categories.sh

**Purpose**: Imports incident category hierarchies from CSV files into database tables.

**What it does**:
1. Creates three category tables:
   - `incident_product_category` (452 entries)
   - `incident_operational_category` (100 entries)
   - `incident_resolution_category` (95 entries)
2. Imports data from CSV files in `Custom/var/categories/`
3. Creates indexes for performance
4. Total: 647 category entries

**Tables Created**:
```sql
-- Product Categories (4-tier hierarchy)
CREATE TABLE incident_product_category (
    id SERIAL PRIMARY KEY,
    tier1 VARCHAR(200),  -- ASTRO, DIMETRA, WAVE
    tier2 VARCHAR(200),  -- Sub-category
    tier3 VARCHAR(200),  -- Sub-sub-category
    tier4 VARCHAR(200),  -- Most specific
    full_path VARCHAR(800),  -- "ASTRO > Cloud Based > Cirrus > CNode"
    valid_id SMALLINT DEFAULT 1,
    create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    create_by INTEGER DEFAULT 1,
    change_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    change_by INTEGER DEFAULT 1
);

-- Similar structure for operational and resolution categories (3-tier)
```

## Adding New Migrations

### 1. Create Migration Script

Create a new file in `migrations/` with the next number:

```bash
# Example: migrations/002_add_incident_templates.sh
#!/bin/bash
# Migration: Add Incident Templates
# This migration creates default incident templates

echo "  Creating incident templates..."

# Your migration logic here
PGPASSWORD=znuny123 psql -U znuny -d znuny << EOF
CREATE TABLE incident_templates (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200),
    template_data JSONB
);
-- Insert default templates
EOF

exit $?  # Important: Return proper exit code
```

### 2. Make it Executable

```bash
chmod +x migrations/002_add_incident_templates.sh
```

### 3. Run Migrations

```bash
./migrate.sh
```

## Migration Best Practices

1. **Naming Convention**: Use `NNN_descriptive_name.sh` format
   - Numbers ensure execution order
   - Descriptive names explain purpose

2. **Idempotency**: Make migrations re-runnable without errors
   ```sql
   CREATE TABLE IF NOT EXISTS ...
   CREATE INDEX IF NOT EXISTS ...
   ```

3. **Error Handling**: Always return proper exit codes
   ```bash
   if ! command; then
       echo "Error: Failed to do something"
       exit 1
   fi
   exit 0
   ```

4. **Logging**: Use echo statements to show progress
   ```bash
   echo "  Creating tables..."
   echo "  Importing data..."
   echo "  Done!"
   ```

5. **Database Access**: Use consistent connection method
   ```bash
   PGPASSWORD=znuny123 psql -U znuny -d znuny -c "SQL HERE"
   ```

## Manual Category Import

If you need to manually re-import categories:

```bash
# Direct script execution
perl Custom/bin/ImportIncidentCategories.pl

# Or reset and re-run migration
PGPASSWORD=znuny123 psql -U znuny -d znuny -c "
  DELETE FROM msst_migrations WHERE migration_name = '001_import_incident_categories.sh';
  DELETE FROM incident_product_category;
  DELETE FROM incident_operational_category;  
  DELETE FROM incident_resolution_category;
"
./migrate.sh
```

## Troubleshooting

### Migration Won't Run
- Check if already executed: `SELECT * FROM msst_migrations;`
- Check script permissions: `ls -la migrations/`
- Check script has proper shebang: `#!/bin/bash`

### Category Import Fails
- Verify CSV files exist: `ls -la Custom/var/categories/`
- Check file permissions
- Verify PostgreSQL connection settings

### Reset Everything
```bash
# Drop all migration-related tables
PGPASSWORD=znuny123 psql -U znuny -d znuny -c "
  DROP TABLE IF EXISTS msst_migrations;
  DROP TABLE IF EXISTS incident_product_category;
  DROP TABLE IF EXISTS incident_operational_category;
  DROP TABLE IF EXISTS incident_resolution_category;
"

# Run migrations fresh
./migrate.sh
```

## Integration with Incident Module

The imported categories will be used by the upcoming incident module for:
- Product categorization (4-tier dropdown)
- Operational categorization (3-tier dropdown)
- Resolution categorization (3-tier dropdown)

These provide hierarchical selection for proper incident classification and routing.

## Future Migrations

Planned migrations for the incident module:
- `002_create_incident_tables.sh` - Main incident table structure
- `003_create_incident_views.sh` - Reporting views
- `004_import_incident_templates.sh` - Default templates
- `005_create_ebonding_tables.sh` - MSI ServiceNow integration tables