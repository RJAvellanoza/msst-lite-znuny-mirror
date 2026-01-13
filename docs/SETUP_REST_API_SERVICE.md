# Setting Up REST API Web Service in Znuny

Since you have a valid license, the API blocking is disabled. However, to test APIs in Postman, you need to configure a REST web service with Provider operations.

## Current Status
- ✅ Valid license installed (expires 2025-12-31)
- ✅ API access is NOT blocked (license check passed)
- ⚠️ Only TwilioSMS service exists (outbound only, no API endpoints)
- ❌ No REST API service configured for testing

## To Create a REST API Service

1. **Login to Znuny Admin Interface**
   - URL: http://YOUR_ZNUNY_SERVER/otrs/index.pl
   - Username: YOUR_USERNAME
   - Password: YOUR_PASSWORD

2. **Navigate to Web Service Management**
   - Admin → Web Service Management
   - Click "Add Web Service"

3. **Configure the Web Service**
   ```
   Name: GenericTicketConnectorREST
   Description: REST API for ticket operations
   Provider Transport: HTTP::REST
   ```

4. **Add Provider Operations**
   Common operations to add:
   - SessionCreate
   - SessionGet
   - SessionRemove
   - TicketCreate
   - TicketGet
   - TicketSearch
   - TicketUpdate

## Quick Test URLs

Once configured, you can test these endpoints:

```bash
# Create Session
POST http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/GenericTicketConnectorREST/SessionCreate
Content-Type: application/json
{
  "UserLogin": "YOUR_USERNAME",
  "Password": "YOUR_PASSWORD"
}

# Get Ticket (requires SessionID)
POST http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/GenericTicketConnectorREST/TicketGet
Content-Type: application/json
{
  "SessionID": "your-session-id-here",
  "TicketID": 1
}
```

## Import Pre-configured Web Service

Alternatively, you can import a pre-configured web service YAML file through the Admin interface.

## Current Working Endpoints

With your current setup, these work:
- ✅ http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TwilioSMS (returns empty - no provider operations)
- ✅ http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/WebserviceID/1 (same as above)

## Authentication Methods

Znuny supports:
1. **Session-based** (default) - Create session first, then use SessionID
2. **HTTP Basic Auth** - Can be enabled in web service configuration
3. **Customer/Agent Auth** - Specific to user type

## Why Basic Auth Failed

Your Postman request used Basic Auth, but:
1. The TwilioSMS service doesn't have Provider transport configured
2. Basic Auth needs to be explicitly enabled in the web service
3. Even if enabled, there are no operations to call

## Next Steps

1. Create a proper REST web service in Admin interface
2. Configure Provider transport as HTTP::REST
3. Add operations you want to test
4. Test with Postman using session-based auth