# Test Scripts Usage Guide

## Environment Variables

The test scripts support environment variables to make them portable across different installations:

- `ZNUNY_ROOT`: Path to your Znuny installation (e.g., `/opt/znuny-6.5.15`)
- `ZNUNY_SERVER`: Your Znuny server hostname (e.g., `znuny.example.com`)
- `ZNUNY_USER`: Admin username for testing (e.g., `root@localhost`)
- `APACHE_LOG`: Path to Apache error log (e.g., `/var/log/apache2/error.log`)

## Running Tests

### Without Environment Variables
The scripts will try to auto-detect common Znuny installation paths:
```bash
./tests/email/test_with_existing_customer.pl
```

### With Environment Variables
For custom installations or to ensure correct paths:
```bash
export ZNUNY_ROOT=/opt/znuny-6.5.15
export ZNUNY_SERVER=my-znuny.example.com
export ZNUNY_USER=admin@example.com
export APACHE_LOG=/var/log/httpd/error_log

./tests/email/test_with_existing_customer.pl
```

### One-liner with Environment Variables
```bash
ZNUNY_ROOT=/opt/znuny-6.5.15 ./tests/api/test_ticket_create_api.pl
```

## Common Installation Paths

The scripts will automatically check these paths if `ZNUNY_ROOT` is not set:
- `/opt/znuny-6.5.15`
- `/opt/znuny`

## Troubleshooting

If you get an error like:
```
Cannot find Znuny installation. Please set ZNUNY_ROOT environment variable.
```

Set the `ZNUNY_ROOT` environment variable to your Znuny installation path:
```bash
export ZNUNY_ROOT=/path/to/your/znuny
```

## Shell Scripts

Shell scripts also support the same environment variables and will use defaults if not set:
```bash
# Uses environment variable or default
./tests/diagnostics/check_email_system.sh

# Override with environment variable
ZNUNY_ROOT=/custom/path/znuny ./tests/diagnostics/check_email_system.sh
```