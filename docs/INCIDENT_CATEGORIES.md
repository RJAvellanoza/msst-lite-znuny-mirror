# Incident Categories Documentation

## Overview

The MSSTLite incident module uses a comprehensive categorization system based on Motorola's LSMP (Lifecycle Service Management Platform) categories. This is a subset of ServiceNow's global category structure, containing 647 total category combinations across three types.

## Category Structure

### 1. Product Categories (452 entries)

**Hierarchy**: 4-tier structure
**Top Level Options**: ASTRO, DIMETRA, WAVE

```
Tier 1 → Tier 2 → Tier 3 → Tier 4
ASTRO → Cloud Based → Cirrus → ATIA Connector
```

**Database Table**: `incident_product_category`

**Key Product Lines**:
- **ASTRO** (251 entries)
  - Cloud Based solutions (Cirrus, etc.)
  - Consoles (MCC5500, MCC7500, etc.)
  - Platform Infrastructure
  - RF Subsystem components
  
- **DIMETRA** (185 entries)
  - Base Stations (MTS, EBS)
  - Network Management
  - Security components
  - System Infrastructure
  
- **WAVE** (16 entries)
  - PTT Solutions
  - Client Applications
  - Server Components

### 2. Operational Categories (100 entries)

**Hierarchy**: 3-tier structure
**Top Level Options**: 
- Technical Support (LMR)
- Technical Support (Software)
- Action Request
- Information Request
- Test

```
Tier 1 → Tier 2 → Tier 3
Technical Support (LMR) → Audio → One Way Audio
```

**Database Table**: `incident_operational_category`

**Purpose**: Classifies the type of operational issue or request

### 3. Resolution Categories (95 entries)

**Hierarchy**: 3-tier structure
**Top Level Options**:
- Technical Support (LMR)
- Technical Support (Software)
- Action Request
- Information Request

```
Tier 1 → Tier 2 → Tier 3
Technical Support (Software) → Configuration → Configuration Change
```

**Database Table**: `incident_resolution_category`

**Purpose**: Documents how issues were resolved for analytics and knowledge management

## Database Schema

### Common Structure

All category tables share these fields:

```sql
id SERIAL PRIMARY KEY           -- Auto-incrementing ID
tier1 VARCHAR(200)             -- Top level category
tier2 VARCHAR(200)             -- Second level
tier3 VARCHAR(200)             -- Third level
tier4 VARCHAR(200)             -- Fourth level (products only)
full_path VARCHAR(600-800)     -- Complete path like "ASTRO > Cloud > Cirrus"
valid_id SMALLINT DEFAULT 1    -- Active/inactive flag
create_time TIMESTAMP          -- When created
create_by INTEGER DEFAULT 1    -- User who created
change_time TIMESTAMP          -- Last modified
change_by INTEGER DEFAULT 1    -- User who modified
```

### Indexes

Each table has indexes on:
- `tier1` - For top-level filtering
- `tier2` - For second-level filtering
- `valid_id` - For active record queries

## Usage in Incident Module

### 1. Hierarchical Dropdowns

Categories will be presented as cascading dropdowns:

```javascript
// User selects ASTRO
Tier1: [ASTRO ▼] 

// Tier2 populates with ASTRO subcategories
Tier2: [Cloud Based ▼]

// Tier3 populates based on Tier2
Tier3: [Cirrus ▼]

// Tier4 populates for final selection
Tier4: [ATIA Connector ▼]
```

### 2. Field Mapping

In the incident form:
- **Product Category 1-4**: Maps to product category tiers
- **Operation Category Tier 1-3**: Maps to operational category tiers
- **Resolution Category Tier 1-3**: Maps to resolution category tiers

### 3. API Access

Use the `IncidentCategory` module to retrieve categories:

```perl
# Get all tier1 product categories
my $Categories = $CategoryObject->CategoryGet(
    Type => 'Product',
);

# Get tier2 values for ASTRO products
my $Categories = $CategoryObject->CategoryGet(
    Type => 'Product',
    Tier1 => 'ASTRO',
);
```

## Querying Categories

### List All Top-Level Categories

```sql
-- Product top levels
SELECT DISTINCT tier1, COUNT(*) 
FROM incident_product_category 
GROUP BY tier1;

-- Result:
-- ASTRO    | 251
-- DIMETRA  | 185  
-- WAVE     | 16
```

### Find Specific Categories

```sql
-- Find all console-related products
SELECT * FROM incident_product_category 
WHERE full_path LIKE '%Console%';

-- Find all audio-related operational issues
SELECT * FROM incident_operational_category
WHERE tier2 = 'Audio';
```

### Get Full Hierarchy

```sql
-- Show complete ASTRO cloud hierarchy
SELECT DISTINCT tier1, tier2, tier3, tier4 
FROM incident_product_category
WHERE tier1 = 'ASTRO' 
  AND tier2 = 'Cloud Based'
ORDER BY tier3, tier4;
```

## Category Selection Logic

### Mandatory vs Optional

Per the incident module requirements:
- **Product Category 1-2**: Mandatory
- **Product Category 3-4**: Optional
- **Operational Category 1-2**: Mandatory  
- **Operational Category 3**: Optional
- **Resolution Category 1-3**: All Optional

### Validation Rules

1. Higher tiers cannot be selected without lower tiers
2. Each tier filters the next tier's available options
3. Invalid combinations are prevented by the hierarchy

## Import Process

### Source Files

Categories are imported from three CSV files:
1. `LSMP New Categories (...) - All Prod Cats.csv`
2. `LSMP New Categories (...) - All Operational Cats.csv`
3. `LSMP New Categories (...) - All Resolution Cats.csv`

### Import Script

Location: `Custom/bin/ImportIncidentCategories.pl`

Functions:
1. Creates tables if they don't exist
2. Clears existing data
3. Imports from CSV files
4. Creates performance indexes
5. Shows import summary

### Manual Import

```bash
# Run the import script directly
perl Custom/bin/ImportIncidentCategories.pl

# Output:
Creating category tables...
Processing operational categories...
  Imported 100 operational categories.
Processing product categories...
  Imported 452 product categories.
Processing resolution categories...
  Imported 95 resolution categories.
Creating indexes...
Category import completed successfully!
```

## Maintenance

### Update Categories

1. Update the CSV files in `Custom/var/categories/`
2. Re-run the import script
3. Existing data is cleared and replaced

### Add New Categories

1. Edit the appropriate CSV file
2. Follow the existing format exactly
3. Re-import using the script

### Disable Categories

```sql
-- Disable a specific category
UPDATE incident_product_category 
SET valid_id = 2 
WHERE tier1 = 'ASTRO' 
  AND tier2 = 'Legacy Products';
```

## Integration Notes

### ServiceNow E-bonding

These categories are critical for MSI ServiceNow integration:
- Product categories determine escalation routing
- Must match ServiceNow's category structure
- Used in e-bonding API calls

### Reporting

Categories enable:
- Incident trending by product line
- Common issue identification
- Resolution effectiveness analysis
- Product-specific SLA tracking

### Future Enhancements

1. Category usage statistics
2. Dynamic category updates from ServiceNow
3. Category-based auto-assignment rules
4. Category-specific SLA definitions