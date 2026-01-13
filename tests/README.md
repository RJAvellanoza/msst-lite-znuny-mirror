# Test Scripts Directory

This directory contains all test scripts for the MSSTLite Znuny module.

## Directory Structure

```
tests/
├── api/                    # API-related tests
├── email/                  # Email and notification tests  
├── diagnostics/           # Diagnostic and debugging tools
├── licenses/              # Test license files
└── verify_install.sh      # Package installation verification
```

## API Tests (`api/`)

- **test_api_license_blocking.sh** - Verifies API returns 403 when no valid license exists
- **test_ticket_create_api.pl** - Tests ticket creation using Znuny API operations directly

## Email Tests (`email/`)

- **test_smtp_notification.sh** - Comprehensive test for SMTP Notification feature
- **test_with_existing_customer.pl** - Tests notifications with existing customer accounts

## Diagnostics (`diagnostics/`)

- **check_email_system.sh** - Comprehensive email system diagnostics
- **debug_email_issues.sh** - Debug email configuration issues

## License Tests (`licenses/`)

Contains test license files for various scenarios:
- Expired licenses
- Valid licenses with different durations
- Test licenses for development

## Package Tests

- **verify_install.sh** - Tests MSSTLite package uninstall/build/reinstall cycle

## Running Tests

Most scripts can be run directly:

```bash
cd /path/to/msst-lite-znuny/tests
./api/test_api_license_blocking.sh
./email/test_smtp_notification.sh
./diagnostics/check_email_system.sh
```

For Perl scripts:
```bash
perl ./api/test_ticket_create_api.pl
```

## Important Notes

1. Some scripts may contain hardcoded credentials - update these before using in production
2. Email test scripts may need valid SMTP configuration
3. API tests require proper web service configuration in Znuny
4. Always run tests in a non-production environment first

## Security Warning

These scripts may contain sensitive information like:
- Database credentials
- API passwords  
- Email addresses

Review and sanitize before sharing or committing to version control.