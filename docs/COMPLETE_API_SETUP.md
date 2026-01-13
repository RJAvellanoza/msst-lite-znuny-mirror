# Complete Znuny API Setup Guide

## Files Available

1. **examples/api/TicketAPI_WebService.yml** - Web service configuration for Znuny
2. **examples/api/Znuny_TicketAPI_Postman_Collection.json** - Postman collection with all endpoints
3. **docs/API_IMPORT_GUIDE.md** - Detailed API documentation

## Step-by-Step Setup

### 1. Import Web Service in Znuny

1. Login to Znuny Admin Panel:
   - URL: http://YOUR_ZNUNY_SERVER/otrs/index.pl
   - Username: YOUR_ADMIN_USERNAME
   - Password: YOUR_ADMIN_PASSWORD

2. Navigate to: **Admin → Web Service Management**

3. Click **"Add Web Service"**

4. Click **"Import web service"** button

5. Select file: `examples/api/TicketAPI_WebService.yml` from your MSSTLite installation directory
   - Or download it to your local machine first if uploading from browser

6. Click **"Import"**

7. Verify the web service is created and **Valid** is set to Yes

### 2. Import Postman Collection

1. Open Postman

2. Click **Import** button (top left)

3. Select **"Upload Files"** tab

4. Choose: `examples/api/Znuny_TicketAPI_Postman_Collection.json` from your MSSTLite installation directory
   - Or copy the file content and paste in "Raw text" tab

5. Click **Import**

6. The collection "Znuny TicketAPI" will appear in your Collections

### 3. Configure Postman Environment

The collection includes these variables (need to be configured):
- `base_url`: http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl
- `username`: YOUR_USERNAME
- `password`: YOUR_PASSWORD
- `session_id`: (auto-populated after login)
- `last_ticket_id`: (auto-populated after ticket creation)
- `last_ticket_number`: (auto-populated after ticket creation)

### 4. Test the API

1. **First Test** - Check API Access:
   - Run: "Test Endpoints" → "Test API Access (No Auth)"
   - Expected: Empty response (not 403)

2. **Login**:
   - Run: "Session Management" → "Create Session (Login)"
   - Expected: Returns SessionID
   - The session_id is automatically saved

3. **Create a Ticket**:
   - Run: "Ticket Operations" → "Create Ticket"
   - Expected: Returns TicketID and TicketNumber
   - These are automatically saved for next requests

4. **Get Ticket Details**:
   - Run: "Ticket Operations" → "Get Ticket Details"
   - Uses the last created ticket ID automatically

## Features of the Postman Collection

### Auto-Login
- If no session exists, it automatically logs in before each request
- No need to manually manage sessions

### Test Scripts
- Automatically saves session IDs
- Saves last created ticket ID and number
- Validates responses
- Shows results in console

### Pre-configured Requests
- Create, Read, Update tickets
- Search tickets with filters
- Get ticket history
- Session management

### Environment Variables
- All URLs and credentials pre-configured
- Dynamic variables for ticket IDs
- Timestamp injection in ticket body

## Quick Test Commands

If you prefer command line:

```bash
# 1. Create session
SESSION=$(curl -s -X POST \
  http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/Session \
  -H "Content-Type: application/json" \
  -d '{"UserLogin":"YOUR_USERNAME","Password":"YOUR_PASSWORD"}' \
  | grep -o '"SessionID":"[^"]*"' | cut -d'"' -f4)

echo "Session: $SESSION"

# 2. Create ticket
RESULT=$(curl -s -X POST \
  http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/Ticket \
  -H "Content-Type: application/json" \
  -d "{
    \"SessionID\": \"$SESSION\",
    \"Ticket\": {
      \"Title\": \"Test from CLI\",
      \"Queue\": \"Raw\",
      \"State\": \"new\",
      \"Priority\": \"3 normal\",
      \"CustomerUser\": \"YOUR_CUSTOMER_USER\"
    },
    \"Article\": {
      \"Subject\": \"Test\",
      \"Body\": \"CLI test ticket\",
      \"ContentType\": \"text/plain; charset=utf8\",
      \"ArticleType\": \"note-external\",
      \"SenderType\": \"agent\"
    }
  }")

echo "Result: $RESULT"
```

## Troubleshooting

1. **Empty response on all requests**:
   - Web service not imported or not valid
   - Check Admin → Web Service Management

2. **403 Forbidden**:
   - License issue - check your MSSTLite license validity
   - Check if MSSTLite package is installed correctly

3. **"No Permission" errors**:
   - User might not have access to the queue
   - Try using "Postmaster" queue instead of "Raw"

4. **Session errors**:
   - Session might have expired
   - The collection auto-creates new sessions

## Download Files

The files are located in your MSSTLite installation directory:
- `examples/api/TicketAPI_WebService.yml`
- `examples/api/Znuny_TicketAPI_Postman_Collection.json`

You can download them using SCP or copy their content.