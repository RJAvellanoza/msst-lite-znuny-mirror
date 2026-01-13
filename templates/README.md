# Znuny Email Notification Templates

This directory contains YAML templates for configuring email notifications in Znuny/OTRS.

## Template Structure

Each YAML file defines a notification template with the following key components:

### Metadata Fields
- `ChangeBy`: User ID who last modified the template
- `ChangeTime`: Last modification timestamp
- `CreateBy`: User ID who created the template
- `CreateTime`: Creation timestamp
- `ID`: Unique identifier for the notification
- `Name`: Human-readable name for the notification
- `ValidID`: Status indicator (1 = active)
- `Comment`: Optional description of the notification

### Data Configuration
- `Events`: Triggers that activate the notification (e.g., `NotificationNewTicket`, `TicketStateUpdate`)
- `Recipients`: Who receives the notification (e.g., `Customer`, `AgentOwner`, `AgentMyQueues`)
- `Transports`: Delivery methods (typically `Email`)
- `LanguageID`: Supported languages for multi-language notifications
- `VisibleForAgent`: Whether agents can see/modify this notification
- `SendOnOutOfOffice`: Send notifications even when recipient is out of office

### Message Content
The `Message` section contains language-specific email templates:
- `Subject`: Email subject line with variable placeholders
- `Body`: HTML-formatted email body
- `ContentType`: Format type (usually `text/html`)

## Available Templates

1. **Notification_Ticket_create_notification.yml**
   - Triggered when new tickets are created
   - Notifies agents and customers about new support requests
   - Includes ticket details and customer information

2. **Notification_Ticket_resolved_EN.yml**
   - Triggered when tickets are resolved
   - Notifies customers that their issue has been resolved
   - English-only template

3. **Notification_Ticket_resolved_final.yml**
   - Final resolution notification template
   - Similar to resolved notification but for final closure

4. **Notification_Ticket_reopened_EN.yml**
   - Triggered when resolved tickets are reopened
   - Notifies relevant parties about ticket reactivation

5. **Notification_Ticket_activity_on_closed_EN.yml**
   - Triggered when activity occurs on closed tickets
   - Alerts agents to unexpected updates on closed issues

## Variable Placeholders

Templates use OTRS/Znuny variables enclosed in angle brackets:
- `<OTRS_TICKET_*>`: Ticket-related data (e.g., TicketNumber, Title, State)
- `<OTRS_CUSTOMER_*>`: Customer information (e.g., REALNAME, UserEmail)
- `<OTRS_CONFIG_*>`: System configuration values (e.g., FQDN, NotificationSenderName)
- `<OTRS_NOTIFICATION_RECIPIENT_*>`: Recipient-specific data
- `<OTRS_TICKET_DynamicField_*>`: Custom dynamic fields (e.g., Site, ImpactedCI)

## Importing Templates

To import these templates into your Znuny system:

1. Navigate to Admin → Ticket Notifications
2. Click "Import" or use the command line tools
3. Select the YAML file to import
4. Review and adjust settings as needed
5. Save and activate the notification

## Customization

When customizing templates:
- Maintain the YAML structure
- Use valid HTML for email bodies
- Test with different languages if multi-language support is needed
- Ensure all referenced dynamic fields exist in your system
- Update MSI-specific fields (Site, ImpactedCI) to match your configuration

## Best Practices

1. Always test notifications in a non-production environment first
2. Keep backup copies of original templates before modifications
3. Document any custom fields or variables used
4. Consider recipient preferences and email volume
5. Use clear, informative subject lines
6. Include relevant ticket links for easy access