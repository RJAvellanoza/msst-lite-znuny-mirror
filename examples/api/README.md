# API Examples

This directory contains example configurations for setting up REST API access in Znuny.

## Files

### TicketAPI_WebService.yml

A complete web service configuration that provides REST API endpoints for ticket operations.

**Features:**
- Session management (login/logout)
- Ticket CRUD operations
- Ticket search
- Ticket history

**How to use:**
1. Login to Znuny Admin Panel
2. Navigate to Admin → Web Service Management
3. Click "Add Web Service" → "Import web service"
4. Select this file and import
5. The API will be available at: `http://YOUR_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI`

### Znuny_TicketAPI_Postman_Collection.json

A Postman collection with pre-configured requests for all API endpoints.

**Features:**
- Pre-configured environment variables
- Auto-session management
- Example requests for all operations
- Test scripts for response validation

**How to use:**
1. Import into Postman
2. Update the environment variables:
   - `base_url`: Your Znuny server URL
   - `username`: Your Znuny username
   - `password`: Your Znuny password
3. Run requests starting with "Create Session"

## Important Notes

1. These are **example** configurations - review and adjust security settings for production use
2. The web service must be imported and set to "Valid" in Znuny
3. Ensure your MSSTLite license is valid for API access to work
4. API access is subject to the same permissions as the authenticated user