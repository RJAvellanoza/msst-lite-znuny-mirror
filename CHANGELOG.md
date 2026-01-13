# LSMP Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - feature/MSSTLITE-55-incident-display-and-update-interface

### Added
- Complete incident management module with dedicated form interface (MSSTLITE-55)
- Incident-specific ticket prefix system with TypeID-based prefixes (MSSTLITE-111)
- Support Group queue for all incident tickets
- Incident history tracking with System/Date tab
- State transition rules for incident management workflow
- Resolution category cascade with validation
- Work notes widget with rich text editor support
- Monitoring and E-bonding display widgets
- Dashboard ticket redirect to incident form (MSSTLITE-139)
- LSMP users and groups migration
- Script to clear prefix and license data
- Dual save buttons (Save and Save & Close) for incident form
- Automatic database credential extraction from Config.pm in migration scripts

### Changed
- Consolidated incident menu into Tickets menu (MSSTLITE-140)
- Replaced Tickets menu with Incidents menu
- Dashboard widgets now use incident form for ticket links
- Centralized database credentials in migration scripts
- Updated incident system to use lowercase Znuny states
- Made database credentials configurable in clear-all-tickets.sh
- Allow Assigned To field to be empty
- Hide unnecessary dashboard widgets for all users
- All incidents now use 'Support Group' queue instead of mapping groups to different queues
- Migration scripts automatically extract database credentials from Config.pm
- Improved migration script to exclude db_config.sh from migration list
- Added --status flag to migration script to show pending/executed migrations

### Fixed
- NOC admin access to Admin interface (MSSTLITE-151)
- SMS from number configuration updates (MSSTLITE-152)
- ACL array reference errors in incident state updates
- Dynamic field saving and alignment issues
- JavaScript/template function mismatches
- Category dropdown initialization and cascade behavior
- Double dash issue in ticket number generation
- Incident form compilation errors and runtime issues
- Template syntax errors in Monitoring and E-bonding widgets
- Resolution category cascade and validation issues
- State update functionality with 500 error prevention
- Assigned To field showing default user ID 1 when unassigned (MSSTLITE-147)
- Assigned To field not filtering users by Assignment Group on form refresh (MSSTLITE-148)
- User filtering completely broken - replaced permission methods with direct database queries (MSSTLITE-149)

### Removed
- Phone and email ticket menu items from Tickets menu
- Untested ZZZNOCAdminRestrictions.xml file
- Default SMS configuration
- ACL rules that caused 500 errors during state updates
- Complex queue mapping for user groups (MSI/NOC queues)

## [25.06.29.1] - 2025-06-29

### Added
- License import validation to prevent overwriting valid licenses with invalid/expired ones (MSSTLITE-112)
- Database storage for AES encryption keys (MSSTLITE-121)
- Automatic key migration during package installation
- Specific error messages for different license validation failures
- New `encryption_keys` database table for secure key storage

### Changed
- License import process now validates before deletion
- AES encryption key moved from hardcoded source to database
- Enhanced error handling in license upload interface

### Fixed
- Valid licenses no longer deleted when importing invalid/expired licenses
- Security vulnerability of hardcoded encryption keys in source code

### Security
- Encryption keys are now stored securely in the database
- Keys can be rotated without code changes
- Improved key management practices

## [25.06.28.5] - 2025-06-28

### Previous Releases
- Initial LSMP license management module
- License expiration checking and notifications
- SMTP notification system integration
- API/webhook blocking for invalid licenses