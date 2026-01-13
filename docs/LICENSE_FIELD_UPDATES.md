# License Field Updates - Contract Number to MCN Migration

## Summary
This document describes the changes made to rename the "contractNumber" field to "mcn" while maintaining backward compatibility, and the addition of two new fields: "systemTechnology" and "lsmpSiteID".

## Database Changes

### Migration Script
- **File**: `/opt/znuny/msst-lite-znuny/scripts/database/update/add_license_fields.sql`
- **Changes**:
  - Added `mcn` column (VARCHAR 250)
  - Added `systemTechnology` column (VARCHAR 250) 
  - Added `lsmpSiteID` column (VARCHAR 250)
  - Kept `contractNumber` column for backward compatibility
  - Copies existing `contractNumber` data to `mcn` column

### To Apply Migration:
```sql
mysql -u root -p znuny < /opt/znuny/msst-lite-znuny/scripts/database/update/add_license_fields.sql
```

## Backend Changes

### 1. AdminAddLicense System Module
- **File**: `/opt/znuny/msst-lite-znuny/Custom/Kernel/System/AdminAddLicense.pm`
- **Changes**:
  - `AdminAddLicenseAdd()`: Now saves both `contractNumber` and `mcn` with the same value for compatibility
  - `AdminAddLicenseList()`: Uses `COALESCE(mcn, contractNumber)` to return mcn field, falling back to contractNumber
  - Added handling for new fields in INSERT and SELECT queries

### 2. AdminAddLicense Web Module  
- **File**: `/opt/znuny/msst-lite-znuny/Custom/Kernel/Modules/AdminAddLicense.pm`
- **Changes**:
  - License parsing accepts both "contractNumber" and "mcn" in JSON
  - If only one is provided, it copies the value to the other field
  - Required field validation accepts either contractNumber or mcn
  - Added validation for new fields (systemTechnology, lsmpSiteID)

### 3. CustomerLicenseView Module
- **File**: `/opt/znuny/msst-lite-znuny/Custom/Kernel/Modules/CustomerLicenseView.pm`
- **Changes**:
  - Added new fields to the data structure passed to templates
  - Maintains backward compatibility by keeping contractNumber field

## Frontend Changes

### 1. Admin License Management View
- **File**: `/opt/znuny/msst-lite-znuny/Custom/Kernel/Output/HTML/Templates/Standard/AdminAddLicense.tt`
- **Changes**:
  - Changed "Contract Number" column header to "MCN"
  - Added "System Technology" column
  - Added "LSMP Site ID" column
  - Updated column spans from 7 to 10 to accommodate new fields

### 2. Customer License View
- **File**: `/opt/znuny/msst-lite-znuny/Custom/Kernel/Output/HTML/Templates/Standard/CustomerLicenseView.tt`
- **Changes**:
  - Changed "Contract Number" label to "MCN"
  - Added display for "System Technology" field
  - Added display for "LSMP Site ID" field

## License Generation Scripts

### 1. Perl License Creator
- **File**: `/opt/znuny/msst-lite-znuny/create_license_for_clone.pl`
- **Changes**:
  - Uses "mcn" instead of "contractNumber" in license JSON
  - Added "systemTechnology" field with value "Test System"
  - Added "lsmpSiteID" field with value "CLONE-SITE-001"
  - Updated print statements to display MCN and new fields

### 2. Python License Encryptor
- **File**: `/opt/znuny/msst-lite-znuny/aes_encrypt3.py`
- **Changes**:
  - Updated example JSON to use "mcn" instead of "contractNumber"
  - Added example values for new fields

## Backward Compatibility

The system maintains full backward compatibility:
1. **Database**: The `contractNumber` column is retained
2. **License Import**: Accepts licenses with either "contractNumber" or "mcn" fields
3. **Data Display**: The system internally handles both field names
4. **API**: Existing integrations using contractNumber will continue to work

## Testing Recommendations

1. Test importing old licenses with "contractNumber" field
2. Test importing new licenses with "mcn" field
3. Verify both old and new licenses display correctly
4. Test creating new licenses with the updated scripts
5. Verify new fields (systemTechnology, lsmpSiteID) are properly saved and displayed

## Notes
- The field is displayed as "MCN" in the UI but the system accepts both field names
- New licenses should use "mcn" going forward
- The new fields (systemTechnology, lsmpSiteID) are optional and can be blank