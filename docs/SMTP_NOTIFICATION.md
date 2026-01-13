# SMTP Email Notification Feature

## Overview

The SMTP Email Notification feature (MSSTLITE-80) provides automated email notifications when tickets are created, resolved, or reopened in Znuny. The system integrates with customer SMTP email services and allows priority-based notification filtering.

## Features

- **Automated Email Notifications** for:
  - Ticket creation (new tickets)
  - Ticket resolution (closed tickets)
  - Ticket reopening (from closed to open state)

- **Priority-based Filtering**: Enable/disable notifications for each ticket priority level (1-5)

- **SMTP Server Configuration**: Full SMTP server configuration including:
  - Host and port settings
  - Authentication (username/password)
  - Encryption (None, SSL/TLS, STARTTLS)
  - Custom from address

- **Access Control**:
  - Admin and NOCAdmin groups: Full configuration access
  - NOC Users: No access to configuration

- **Email Content** includes:
  - Ticket number and title
  - Priority and state
  - Queue information
  - Site (if available via dynamic field)
  - Impacted CI (if available via dynamic field)
  - Requestor details (name, email, customer ID)
  - Direct link to ticket

## Installation

1. The feature is included in the MSSTLite package
2. Install/update the package:
   ```bash
   sudo ./setup.sh  # For development
   # OR
   sudo -u znuny /path/to/znuny/bin/otrs.Console.pl Admin::Package::Install /path/to/MSSTLite-25.06.25.1.opm
   ```

## Configuration

### Access the Configuration Interface

1. Log in to Znuny as an administrator
2. Navigate to: **Admin → System → SMTP Notification**

### Configure SMTP Server

1. **Enable SMTP Notifications**: Check the box to enable the system
2. **SMTP Host**: Enter your SMTP server hostname or IP address
3. **SMTP Port**: Common ports:
   - 25: Standard SMTP (unencrypted)
   - 465: SMTP over SSL/TLS
   - 587: SMTP with STARTTLS
4. **Encryption**: Select the appropriate encryption method
5. **Authentication**: Enter username and password if required
6. **From Address**: Set the sender email address
7. **Default Recipients**: Comma-separated list of email addresses

### Configure Priority Notifications

Enable or disable notifications for each priority level:
- Priority 1 (very low)
- Priority 2 (low)
- Priority 3 (normal)
- Priority 4 (high)
- Priority 5 (very high)

### Test Connection

Click the "Test Connection" button to verify SMTP server connectivity.

## Email Template

The email template is fixed and includes:

**Subject Format**: `[STATUS] Ticket#<TicketNumber>: <Title>`

**Body includes**:
- Status (NEW/RESOLVED/REOPENED)
- Ticket details (number, title, priority, state, queue)
- Site information (if available)
- Impacted CI (if available)
- Requestor details
- Direct link to ticket

## Troubleshooting

### Check Module Installation
```bash
sudo ./test_smtp_notification.sh
```

### Verify Event Module Registration
```bash
sudo -u znuny /path/to/znuny/bin/otrs.Console.pl Admin::Config::Read --setting-name Ticket::EventModulePost###SMTPNotification
```

### Check Logs
```bash
tail -f /path/to/znuny/var/log/otrs.log | grep SMTPNotification
```

### Common Issues

1. **"Test Connection" fails**:
   - Verify SMTP server is accessible from Znuny server
   - Check firewall rules for SMTP port
   - Verify authentication credentials

2. **Notifications not sending**:
   - Check if SMTP Notifications are enabled
   - Verify priority is enabled for notification
   - Check recipient email addresses are valid
   - Review Znuny logs for errors

3. **Missing Perl modules**:
   ```bash
   sudo cpanm Net::SMTP::SSL
   ```

## Security Considerations

- SMTP passwords are stored in Znuny's configuration system
- Use SSL/TLS encryption when possible
- Restrict access to admin/NOCAdmin groups only
- Consider using application-specific passwords for SMTP authentication

## Technical Details

### Components

1. **Admin Module**: `Kernel::Modules::AdminSMTPNotification`
   - Provides web interface for configuration
   - Handles SMTP connection testing

2. **Event Module**: `Kernel::System::Ticket::Event::SMTPNotification`
   - Listens for TicketCreate and TicketStateUpdate events
   - Sends emails based on configuration

3. **Configuration**: `Kernel::Config::Files::XML::SMTPNotification.xml`
   - Defines all configuration options
   - Registers modules in Znuny

4. **Template**: `Kernel::Output::HTML::Templates/Standard/AdminSMTPNotification.tt`
   - Admin interface template

### Event Flow

1. Ticket event occurs (create/state update)
2. SMTPNotification event module triggered
3. Module checks if notifications are enabled
4. Checks if priority is enabled for notifications
5. Builds email from template
6. Sends to configured recipients

## Support

For issues or questions, please contact the LSMP support team.