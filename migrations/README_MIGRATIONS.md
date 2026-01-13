# Quick Migration Guide

## For Developers

### Running Migrations
```bash
cd /opt/znuny/msst-lite-znuny
./migrate.sh
```

### Rolling Back Migrations
```bash
# Show available rollback options
./migrate.sh --down

# Rollback the last migration
./migrate.sh --down last

# Rollback a specific migration
./migrate.sh --down 001_import_incident_categories.sh

# Rollback ALL migrations (careful!)
./migrate.sh --down all
```

### Adding a New Migration
```bash
# 1. Create migration file (use next available number)
vim migrations/011_your_migration_name.sh

# 2. Add your logic
#!/bin/bash
# Migration: Brief description of what this does

# Source database configuration
MIGRATION_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$MIGRATION_DIR/db_config.sh"

echo "  Running my migration..."
# Your code here
exit $?

# 3. Make executable
chmod +x migrations/011_your_migration_name.sh

# 4. Run it
./migrate.sh

# 5. (Optional) Create rollback script
vim migrations/011_your_migration_name.down.sh
chmod +x migrations/011_your_migration_name.down.sh
```

### Check Migration Status
```sql
-- See what's been run
PGPASSWORD=znuny123 psql -U znuny -d znuny -c "SELECT * FROM msst_migrations;"

-- Reset a migration
PGPASSWORD=znuny123 psql -U znuny -d znuny -c "DELETE FROM msst_migrations WHERE migration_name = '001_import_incident_categories.sh';"
```

## Current Migrations

| Migration | Purpose | Tables/Data Created |
|-----------|---------|-------------------|
| 001_import_incident_categories.sh | Import 647 incident categories | incident_product_category (452)<br>incident_operational_category (100)<br>incident_resolution_category (95) |
| 002_create_incident_infrastructure.sh | Create incident management infrastructure | ticket_prefix table<br>ticket_type_prefix table<br>Incident ticket type |
| 003_create_incident_dynamic_fields_v2.sh | Create dynamic fields for incidents | Various incident-specific dynamic fields |
| 004_cleanup_dynamic_fields.sh | Clean up duplicate dynamic fields | Removes duplicate/conflicting fields |
| 005_create_lsmp_users.sh | Create LSMP users | Creates lsmpadmin, lsmpoperator, lsmpviewer users |
| 006_create_incident_states.sh | Create incident-specific states | Adds incident workflow states |
| 007_create_incident_queue.sh | Create incident queue | Creates Incidents queue |
| 008_create_support_group_queue.sh | Create Support Group queue | Creates Support Group queue for incidents |
| 009_create_incident_tables.sh | Create incident management tables | incident_management<br>incident_work_notes tables |
| 010_create_msst_groups_sql.sh | Create MSST permission groups | MSIAdmin<br>NOCAdmin<br>NOCUser groups |

## Important Notes

1. **Migrations are NOT in the OPM package** - Run manually after installation
2. **Order matters** - Use numbered prefixes (001_, 002_, etc.)
3. **One-time only** - Each migration runs once and is tracked
4. **Safe to re-run** - `./migrate.sh` skips completed migrations
5. **Rollback support** - Create `.down.sh` files for clean rollbacks
6. **Down scripts optional** - Without them, only removes from tracking

## Quick Commands

```bash
# Import categories only
perl Custom/bin/ImportIncidentCategories.pl

# View category counts
PGPASSWORD=znuny123 psql -U znuny -d znuny -c "
SELECT 'Product' as type, COUNT(*) FROM incident_product_category 
UNION SELECT 'Operational', COUNT(*) FROM incident_operational_category 
UNION SELECT 'Resolution', COUNT(*) FROM incident_resolution_category;"

# Reset everything
PGPASSWORD=znuny123 psql -U znuny -d znuny -c "
DROP TABLE IF EXISTS msst_migrations CASCADE;
DROP TABLE IF EXISTS incident_product_category CASCADE;
DROP TABLE IF EXISTS incident_operational_category CASCADE;
DROP TABLE IF EXISTS incident_resolution_category CASCADE;"
```

## Files Structure
```
msst-lite-znuny/
├── migrate.sh                    # Main runner (with --down support)
├── migrations/                   # Migration scripts
│   ├── db_config.sh             # Database configuration for migrations
│   ├── 001_import_incident_categories.sh
│   ├── 001_import_incident_categories.down.sh  # Rollback script
│   ├── 002_create_incident_infrastructure.sh
│   ├── 003_create_incident_dynamic_fields_v2.sh
│   ├── 004_cleanup_dynamic_fields.sh
│   ├── 005_create_lsmp_users.sh
│   ├── 005_create_lsmp_users.down.sh
│   ├── 006_create_incident_states.sh
│   ├── 006_create_incident_states.down.sh
│   ├── 007_create_incident_queue.sh
│   ├── 008_create_support_group_queue.sh
│   ├── 009_create_incident_tables.sh
│   └── 010_create_msst_groups_sql.sh
├── Custom/
│   ├── bin/
│   │   └── ImportIncidentCategories.pl
│   └── var/categories/          # CSV data files
├── MIGRATIONS.md                # Full documentation
├── INCIDENT_CATEGORIES.md       # Category details
└── README_MIGRATIONS.md         # This file
```