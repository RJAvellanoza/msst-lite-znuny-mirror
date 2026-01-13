# License Check Feature (MSSTLITE-4)

## Overview

The License Check feature ensures that users cannot access the system with an expired, invalid, or missing license. It automatically redirects users to the license management page when license issues are detected.

## How It Works

### Check Frequency
- License validation occurs on every page load via PreApplication module
- Results are cached in session for 1 hour to minimize performance impact
- After cache expiration, the next page load triggers a fresh database check

### User Experience

#### When License is Invalid/Expired
- All users are automatically redirected to the license page
- Navigation menus are hidden via CSS injection
- Only the license management page is accessible
- Sidebar remains visible on license page for uploading new license

#### For Regular Users
- Can only view license status (read-only)
- See current license status and expiration date
- Must contact administrators for license renewal

#### For Administrators (admin/NOCAdmin groups)
- Full access to license management features
- Can upload new encrypted license files
- Can view all license details including MAC address validation

### License States

1. **Valid**: License is active and within date range
2. **Expired**: Current date is past the license end date
3. **Invalid**: License exists but dates or validation failed
4. **Unavailable**: No license found in the system

## Technical Implementation

### PreApplication Module
A special module that runs before every page request to check license status.

**Excluded Pages** (no license check):
- Login/Logout pages
- Public pages
- License management page itself (to prevent loops)

### Caching Mechanism
- **Cache Key**: `LicenseCheck::Status`
- **TTL**: 3600 seconds (1 hour)
- **Invalidation**: Automatic after new license upload

### Configuration

The feature is configured via XML in the SysConfig system:

**Location**: `Custom/Kernel/Config/Files/XML/LicenseCheckV2.xml`

Key settings:
- `LicenseCheck::Enabled` - Enable/disable license checking (1/0)
- `LicenseCheck::CacheTTL` - Cache time in seconds (default: 3600)
- `LicenseCheck::AdminGroups` - Groups allowed to manage licenses (admin, NOCAdmin)
- `PreApplicationModule###AgentLicenseCheck` - Registers the PreApplication module

## Troubleshooting

### Users Cannot Access System
1. Check if license exists in database
2. Verify license dates are valid
3. Clear cache: `bin/otrs.Console.pl Maint::Cache::Delete`

### Redirect Loop
1. Ensure Login page is excluded from checks
2. Verify PreApplication module returns 1
3. Check Apache error logs

### License Not Updating
1. Clear the cache after uploading new license
2. Verify file upload was successful
3. Check database for new license record

## Security Considerations

- License files are encrypted with AES-256
- Only admin users can upload new licenses
- License content is never exposed to regular users
- Cached data contains only status, not sensitive information

## License Import Protection (MSSTLITE-112)

### Overview
The system now validates licenses before importing to protect existing valid licenses from being overwritten by invalid or expired ones.

### Validation Checks
Before importing a new license, the system validates:
1. **Expiration Date**: Rejects licenses that have already expired
2. **Start Date**: Rejects licenses that are not yet valid (future-dated)
3. **Date Format**: Ensures dates are in correct YYYY-MM-DD format
4. **Required Fields**: Verifies startDate and endDate are present

### User Experience
When uploading an invalid license:
- The import is blocked
- A specific error message explains why (expired, not yet valid, invalid format, etc.)
- The existing valid license remains unchanged
- Administrators can review the error and obtain a proper license

### Enhanced Security (MSSTLITE-121)
- AES encryption key is now stored in the database instead of hardcoded in source
- Keys are automatically migrated during package installation
- Improved security through proper key management