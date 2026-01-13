# LSMP Znuny Repository

Custom modules and extensions for LSMP Znuny/OTRS installation.

## Installation Methods

### Prerequisites

```bash
# Install all required Perl modules and system dependencies
sudo ./install-dependencies.sh
```

This script will install:
- Crypt::CBC (for encryption)
- Crypt::Rijndael (AES encryption)
- Net::SMTP (email notifications)
- Net::SMTP::SSL (secure email)
- XML::LibXSLT (SMS webservice transformations)

### Method 1: Development Setup (using setup.sh)

For development and testing environments where you need to modify code frequently:

```bash
# Clone the repository
git clone https://bitbucket.mot-solutions.com/scm/msstlite/msst-lite-znuny.git
cd msst-lite-znuny

# Install dependencies first
sudo ./install-dependencies.sh

# Run setup script (auto-detects Znuny installation)
sudo ./setup.sh

# Or specify Znuny path manually
sudo ./setup.sh /path/to/znuny

# To uninstall
sudo ./setup.sh --uninstall
```

**Note**: The setup.sh script creates symlinks from the Custom directory to the appropriate Znuny locations. This is ideal for development as changes are immediately reflected.

### Method 2: Package Installation (Production)

For production deployments or distributing to other systems:

```bash
# Build and install the package (default behavior)
./build-package.sh

# The script will:
# 1. Build the package: MSSTLite-YY.MM.DD.N.opm (e.g., MSSTLite-25.07.55.opm)
# 2. Fix Znuny permissions
# 3. Clean up temporary files
# 4. Automatically install the package using Admin::Package::Upgrade

# To build WITHOUT auto-installing:
./build-package.sh --no-install

# Manual installation options:
# Via command line (no SecureMode requirement):
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Admin::Package::Upgrade /path/to/MSSTLite-YY.MM.DD.N.opm"

# Via web interface (SecureMode must be enabled):
# 1. Ensure SecureMode is enabled in /path/to/znuny/Kernel/Config.pm
# 2. Navigate to Admin → Package Manager
# 3. Choose File → Select MSSTLite-YY.MM.DD.N.opm → Install Package

# IMPORTANT: After installation, restart Apache for API blocking to take effect:
systemctl restart apache2    # Debian/Ubuntu
# OR
systemctl restart httpd      # RedHat/CentOS
```

## Post-Installation and Uninstallation Steps

After installing the MSSTLite package using the package manager, you must run the dynamic field and search field assignment script to enable all required fields in the ticket search interface:

```bash
cd /path/to/znuny
sudo perl scripts/assign_fields_for_ticket_search.pl
```

This script will:
- Assign all required dynamic fields to the AgentTicketSearch screen
- Enable default search fields (Ticket Number, Ticket Create Time, etc.)

If you uninstall the package, you should run the unassignment script to clean up these settings:

```bash
cd /path/to/znuny
sudo perl scripts/unassign_fields_for_ticket_search.pl
```

This script will:
- Remove the dynamic fields from the AgentTicketSearch screen
- Disable the default search fields enabled by the package

**Note:** The required dynamic and default search fields should be enabled automatically after installing the package using the package manager. Running the scripts below is a workaround in case the package manager fails to enable or disable the fields as expected.

**Note:** These scripts require root or znuny user privileges to update system configuration.

## Repository Structure

```
msst-lite-znuny/
├── Custom/                          # All custom Znuny/OTRS modifications
│   ├── Kernel/                      # Core custom modules
│   │   ├── Config/                  # Configuration files
│   │   │   └── Files/
│   │   │       ├── XML/
│   │   │       │   ├── AdminAddLicense.xml    # License admin module configuration
│   │   │       │   ├── LicenseCheckV2.xml    # License enforcement settings
│   │   │       │   ├── LicenseNotification.xml # License expiration notifications
│   │   │       │   ├── MSSTLiteVersion.xml   # Version configuration (SysConfig)
│   │   │       │   ├── SMTPNotification.xml  # SMTP notification configuration
│   │   │       │   ├── TwilioSMS.xml         # SMS notification configuration
│   │   │       │   ├── Custom.xml            # Ticket initial counter configuration
│   │   │       │   └── CustomTicketPrefix.xml # Ticket prefix admin module configuration
│   │   │       ├── ZZZAdminLicense.pm        # License module configuration
│   │   │       └── ZZZLicenseNotification.pm # Notification configuration
│   │   ├── GenericInterface/        # API/Web Service modules
│   │   │   └── Provider.pm                   # API request handler with license check
│   │   ├── Modules/                 # Frontend controllers
│   │   │   ├── AdminAddLicense.pm            # License management UI
│   │   │   ├── AdminSMTPNotification.pm      # SMTP notification configuration UI
│   │   │   ├── AdminSMSNotification.pm       # SMS notification configuration UI
│   │   │   ├── AdminTicketPrefix.pm          # Ticket prefix configuration UI
│   │   │   ├── AgentTicketPhone.pm           # Modified phone ticket creation
│   │   │   ├── PreApplicationLicenseCheck.pm # License enforcement module
│   │   │   └── AgentLicenseNotificationDismiss.pm
│   │   ├── Output/HTML/             # View layer
│   │   │   ├── FilterContent/       # HTML output filters
│   │   │   │   ├── LicenseExpirationNotification.pm
│   │   │   │   └── MSSTLiteVersionFooter.pm
│   │   │   ├── Preferences/         # User preference modules
│   │   │   │   └── UserDetails.pm
│   │   │   └── Templates/Standard/  # Template files (.tt)
│   │   │       ├── AdminAddLicense.tt
│   │   │       ├── AdminSMTPNotification.tt
│   │   │       ├── AdminSMSNotification.tt
│   │   │       ├── AdminTicketPrefix.tt
│   │   │       └── LicenseExpirationNotification.tt
│   │   └── System/                  # Backend business logic
│   │       ├── AdminAddLicense.pm   # License management backend
│   │       ├── SMSConfig.pm        # SMS configuration backend
│   │       ├── InitialCounter.pm   # Ticket initial counter backend
│   │       ├── Ticket.pm            # Modified ticket system
│   │       ├── TicketPrefix.pm     # Ticket prefix management backend
│   │       ├── Ticket/
│   │       │   └── Number/
│   │       │       └── AutoIncrement.pm     # Custom auto-increment with prefix
│   │       └── Ticket/Event/
│   │           ├── SMTPNotification.pm       # SMTP notification event module
│   │           └── SMSNotification.pm        # SMS notification event module
├── adminlicense-db.xml              # Database schema definitions
├── MSSTLite.sopm                    # Package definition file
├── build-package.sh                 # Package build script
├── setup.sh                         # Development setup script
├── dev/                             # Development-only tools
│   └── tools/                       # Development utilities
│       ├── deploy_smtp.sh           # Force deploy SMTP configuration
│       └── validate-templates.sh    # Template validation script
├── docs/                            # Documentation
│   ├── API_IMPORT_GUIDE.md         # API setup guide
│   ├── API_TESTING_GUIDE.md        # API testing guide
│   ├── COMPLETE_API_SETUP.md       # Complete API setup guide
│   ├── LICENSE-CHECK.md            # License check documentation
│   ├── SETUP_REST_API_SERVICE.md   # REST API service setup
│   ├── SMTP_NOTIFICATION.md        # SMTP notification guide
│   ├── SMS_NOTIFICATION_SETUP.md   # SMS notification user guide
│   ├── SMS_NOTIFICATION_TECHNICAL.md # SMS notification technical docs
│   └── TROUBLESHOOTING_API_BLOCKING.md # API blocking troubleshooting
├── examples/                        # Example configurations
│   └── api/                         # API examples
│       ├── TicketAPI_WebService.yml # REST API web service configuration
│       └── Znuny_TicketAPI_Postman_Collection.json # Postman collection
├── scripts/                         # Utility scripts
│   ├── diagnose_api_blocking.sh    # Diagnose API blocking issues
│   ├── diagnose_api_blocking_detailed.sh # Detailed API diagnostics
│   ├── fix-msstlite-lockout.sh    # Recovery script for lockouts
│   ├── fix_smtp_module.pl          # Fix SMTP module issues
│   ├── sync_smtp_settings.pl       # Sync SMTP settings
│   └── verify_api_blocking.sh      # Verify API blocking
├── templates/                       # Email notification templates
│   └── *.yml                       # Various notification templates
├── tests/                           # Test scripts directory
│   ├── api/                         # API testing scripts
│   ├── diagnostics/                 # Diagnostic tools
│   ├── email/                       # Email notification tests
│   ├── licenses/                    # Test license files
│   └── USAGE.md                    # Test scripts usage guide
├── var/packagesetup/                # Package setup modules
│   └── MSSTLite.pm  # SMTP notification setup
├── QUICK_SETUP.md                   # Quick setup guide
└── README.md                        # This file
```

## Directory Organization

### Core Directories
- **Custom/** - All custom Znuny/OTRS modifications (package content)
- **Kernel/** - Additional module structure for package building
- **var/packagesetup/** - Package installation/uninstallation scripts

### Supporting Directories
- **docs/** - All documentation files
- **examples/** - Example configurations (API web service, Postman collection)
- **scripts/** - Utility scripts for diagnostics and fixes
- **templates/** - Email notification templates
- **tests/** - Test scripts with usage documentation
- **dev/tools/** - Development-only tools (not needed for package installation)

### Key Files
- **MSSTLite.sopm** - Package definition file
- **adminlicense-db.xml** - Database schema
- **build-package.sh** - Package build script
- **setup.sh** - Development setup script

## Current Modules

### License Management System
- **License Management**: Upload and manage license files with encryption
- **License Enforcement**: PreApplication module redirects all users to license page if no valid license exists
- **License Expiration Notifications**: Automatic warnings 2 months before expiry
- **Notification Dismissal**: Users can dismiss notifications for 24 hours
- **User Details Extension**: Additional user profile fields
- **Version Display**: Shows LSMP version (YY.MM.DD.build format) in footer and license page

### SMTP Email Notification System
- **Automated Email Notifications**: Send emails when tickets are created, resolved, or reopened
- **Priority-based Filtering**: Enable/disable notifications for each ticket priority level
- **SMTP Configuration**: Full SMTP server configuration with authentication and encryption support
- **Access Control**: Admin and NOCAdmin groups can configure; NOC users have no access
- **Fixed Email Template**: Non-customizable template with all required ticket information

### SMS Notification System
- **Twilio Integration**: Send SMS alerts for ticket events via Twilio API
- **Priority-based Control**: Enable/disable SMS notifications per priority level
- **Phone Number Management**: Uses customer phone or agent mobile as recipient
- **Event-based Triggers**: Notifications on ticket creation and state changes
- **XSLT Data Mapping**: Transforms ticket data to SMS format
- **Admin Configuration**: Web interface for Twilio credentials and settings

### API and Webhook Blocking
- **API Access Control**: Blocks all API and webhook access when no valid license exists
- **HTTP 403 Response**: Returns proper error response with JSON body for invalid licenses
- **Configuration Options**: LicenseCheck::BlockAPI and LicenseCheck::BlockWebhooks settings
- **Provider Override**: Custom Provider.pm intercepts all GenericInterface API requests
- **License Status Check**: Real-time database validation for each API request

### Ticket Numbering System
- **Custom Ticket Prefixes**: Configure different prefixes for ticket types (Incident, Problem, etc.)
- **Type-based Numbering**: Separate number sequences for each ticket type
- **Initial Counter Setting**: Set starting ticket number for new installations
- **Admin Interface**: Web-based configuration for ticket prefixes
- **Auto-increment Override**: Custom ticket number generator with prefix support

### Incident Update Interface
- **Role-based Access**: MSI D&Ts Support, MSI Field Support, NOC User, and Customer Administrator roles can update incidents
- **State-based Editability**: Incidents in closed or cancelled states cannot be edited
- **Automatic Locking**: Incidents automatically lock when moved to closed/cancelled states
- **Lock Validation**: Only unlocked incidents can be edited
- **Customer Visibility Control**: Hides "Visible to Customer" checkbox (customer interface not enabled)
- **History Tracking**: All incident updates are recorded in ticket history
- **PostgreSQL Support**: Database tables use proper PostgreSQL syntax

### Features
- Encrypted license file storage
- MAC address validation
- Contract tracking (company, end customer, contract number)
- Expiration date monitoring
- **License enforcement with automatic redirects**
- **Navigation menu hiding when license invalid**
- **API and webhook blocking when license invalid**
- **License validation**: Rejects expired licenses, invalid dates, and null/empty required fields
- **SMTP email notifications for ticket events**
- **Priority-based notification control**
- Admin-only access control
- PostgreSQL and MySQL support
- Version display in footer and license management page

### Ticket Number Prefix Feature

**Clean Implementation (v25.06.30.47+)**
- Uses custom ticket number generator (`AutoIncrementWithPrefix`)
- No core file overrides - follows Znuny extension patterns
- Configurable per ticket type via Admin interface
- Format: `[PREFIX]-[NUMBER]` (e.g., INC-00000001, SR-00000002)

**Configuration**:
1. Navigate to Admin → MSSTLite section → Ticket Number Prefix
2. Add prefixes for each ticket type (enter just "INC", not "INC-")
3. System automatically uses prefixes for new tickets

**Important**: Enter prefixes WITHOUT trailing dashes (e.g., "INC", not "INC-"). The system automatically adds the dash separator.

**Technical Details**:
- Custom number generator: `Kernel::System::Ticket::Number::AutoIncrementWithPrefix`
- Minimal override module: `Kernel::System::TicketCreateOverride`
- Loader: `Kernel::Config::Files::ZZZTicketPrefixOverride`
- Configuration: `Ticket::NumberGenerator` system config setting
- Admin groups: admin, NOCAdmin

## Development Workflow

### When to Use Each Installation Method

**Use setup.sh when:**
- Actively developing new features
- Debugging or testing changes
- Need immediate feedback on code changes
- Working in a development environment

**Use package (.opm) when:**
- Deploying to production
- Installing on multiple servers
- Distributing to other teams/customers
- Need clean install/uninstall process
- Want version management

### Making Changes

1. **During Development**:
   ```bash
   # Edit files in Custom/
   vim Custom/Kernel/Modules/AdminAddLicense.pm
   
   # Changes are immediately active (if using setup.sh)
   # Just rebuild config and clear cache:
   su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Maint::Config::Rebuild"
   su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Maint::Cache::Delete"
   ```

2. **For Release**:
   ```bash
   # Update version in MSSTLite.sopm and MSSTLiteVersion.xml
   vim MSSTLite.sopm
   vim Custom/Kernel/Config/Files/XML/MSSTLiteVersion.xml
   
   # Build new package
   ./build-package.sh
   
   # Test package installation on a clean system
   ```

## Package Management

### Building a New Version

1. Update version number in `MSSTLite.sopm`
2. Update LSMP version in `Custom/Kernel/Config/Files/XML/MSSTLiteVersion.xml` (YY.MM.DD.build format)
3. Add any new files to the `<Filelist>` section
4. Update database schema if needed
5. Build and install:
   ```bash
   # Build and auto-install (default)
   ./build-package.sh
   
   # Or build only (no install)
   ./build-package.sh --no-install
   ```
6. The output file will be `MSSTLite-YY.MM.DD.N.opm` (version number from .sopm)

### Important Build Notes

**Package Path Consistency**: All files in the SOPM must use `Kernel/` paths (not `Custom/Kernel/`). The build script handles copying from Custom/ to Kernel/ and stages files to the Znuny installation directory.

### Package Contents

The MSSTLite.sopm file defines:
- All module files and their locations
- Database schema (table creation/deletion)
- Required Perl modules (Crypt::CBC, Crypt::Rijndael)
- Installation/upgrade/uninstall procedures
- Post-install scripts for config rebuild and cache clearing
- **Critical**: Uses ConfigurationXML2DB() before ConfigurationDeploy() for proper config deployment

### Package Installation Requirements

- **For Web Interface**: SecureMode must be enabled (set to 1) in Config.pm
- **For Command Line**: No special requirements
- **Perl Modules**: Crypt::CBC and Crypt::Rijndael must be installed
- **Database**: PostgreSQL or MySQL with appropriate permissions

## Testing

### Automated Installation Test
```bash
# Run complete build/install/verify cycle
./tests/verify_install.sh
```

### Manual Testing
```bash
# Check Perl syntax
find Custom -name "*.pm" -exec perl -c {} \;

# Rebuild config
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Maint::Config::Rebuild"

# Clear cache
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Maint::Cache::Delete"

# Check if module is accessible
curl http://localhost/otrs/index.pl?Action=AdminAddLicense
```

### System Health Check
```bash
# Run comprehensive system check
./check-everything.sh
```

The `check-everything.sh` script performs a complete MSSTLite system health check including:
- Database connection verification (automatically retrieves credentials from Config.pm)
- MSSTLite table existence and row counts
- Dynamic field configuration status
- AES encryption key presence
- Default customer account
- Ticket prefix configuration
- Package installation status
- Ticket number generator configuration

The script provides color-coded output:
- ✓ Green: Component is properly configured
- ⚠ Yellow: Warning, may need attention
- ✗ Red: Missing or misconfigured component

## Important Documentation

- **Package Building**: Always use `build-package.sh` to build packages - it handles all preparation automatically
- **Build Process**: The script copies from Custom/ to Kernel/ locally, then stages to `/opt/znuny-6.5.15/Kernel/` before building
- **Version History**: See ZNUNY_AI_DOCS/ for detailed documentation on fixes and implementations

## Troubleshooting

### License Enforcement Not Working

1. Check if PreApplication module is registered:
   ```bash
   grep "PreApplicationModule.*LicenseCheck" /path/to/znuny/Kernel/Config/Files/ZZZAAuto.pm
   ```

2. Verify license enforcement is enabled:
   ```bash
   grep "LicenseCheck::Enabled" /path/to/znuny/Kernel/Config/Files/ZZZAAuto.pm
   ```

3. Check license status in database:
   ```bash
   su - postgres -c "psql -d znuny -c 'SELECT * FROM license;'"
   ```

### Module Not Appearing in Admin Interface

1. Check symlinks (if using setup.sh):
   ```bash
   ls -la /path/to/znuny/Kernel/Config/Files/ZZZ*.pm
   ls -la /path/to/znuny/Kernel/Output/HTML/Templates/Standard/AdminAddLicense.tt
   ```

2. Verify configuration is loaded:
   ```bash
   su - znuny
   perl -I/path/to/znuny -I/path/to/znuny/Kernel/cpan-lib -MKernel::Config \
     -e 'my $c=Kernel::Config->new(); print $c->{"Frontend::Module"}->{AdminAddLicense} ? "OK\n" : "Missing\n"'
   ```

3. Check database table:
   ```bash
   su - znuny -c "psql -d znuny -c '\d license'"
   ```

### API Blocking Not Working

1. **Most Common Issue - Apache Not Restarted**:
   ```bash
   # API blocking requires Apache restart after package installation
   systemctl restart apache2    # Debian/Ubuntu
   systemctl restart httpd      # RedHat/CentOS
   ```

2. Verify Provider.pm is installed:
   ```bash
   ls -la /path/to/znuny/Custom/Kernel/GenericInterface/Provider.pm
   ```

3. Check configuration:
   ```bash
   su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Admin::Config::Read --setting-name LicenseCheck::BlockAPI"
   # Should return: 1
   ```

4. Test API blocking:
   ```bash
   curl -v http://localhost/otrs/nph-genericinterface.pl/Webservice/Test
   # Should return: HTTP 403 Forbidden (if no valid license)
   ```

### Package Installation Issues

1. Check package list:
   ```bash
   su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Admin::Package::List"
   ```

2. Verify package XML structure:
   ```bash
   # OPM files are XML, not tar
   head -20 MSSTLite-YY.MM.DD.N.opm
   ```

3. Check SecureMode for Package Manager access:
   ```bash
   grep SecureMode /path/to/znuny/Kernel/Config.pm
   # Should show: $Self->{SecureMode} = 1;
   ```

### Locked Out After MSSTLite Installation

If you're unable to access Znuny after installing MSSTLite (e.g., license enforcement redirects prevent access), use the recovery script:

```bash
# Run the recovery script (auto-detects Znuny path)
sudo ./scripts/fix-msstlite-lockout.sh

# Or specify Znuny path manually
sudo ./scripts/fix-msstlite-lockout.sh /path/to/znuny
```

The recovery script will:
- Stop Znuny services
- Remove MSSTLite package completely
- Clean all related configuration
- Rebuild Znuny configuration
- Restart services

**Warning**: This will completely remove MSSTLite. Use only when locked out.

## Git Workflow

```bash
# Feature branch
git checkout -b feature/MSSTLITE-XX-description

# Commit with JIRA ID
git commit -m "MSSTLITE-XX: Brief description

- Detail 1
- Detail 2"

# Push to origin
git push origin feature/MSSTLITE-XX-description
```

## Notes

- All custom code stays under Custom/ directory for easy version control
- Never modify core Znuny files directly
- The setup.sh script is for development only
- Use the package system for production deployments
- Test thoroughly before committing
- Required Perl modules: Crypt::CBC, Crypt::Rijndael