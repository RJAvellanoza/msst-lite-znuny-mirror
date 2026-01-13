# Znuny REST API Setup Guide

## Import the Web Service

1. **Login to Znuny Admin**
   - URL: http://YOUR_ZNUNY_SERVER/otrs/index.pl
   - Username: YOUR_ADMIN_USERNAME
   - Password: YOUR_ADMIN_PASSWORD

2. **Navigate to Web Service Management**
   - Admin → Web Service Management
   - Click "Add Web Service"

3. **Import the YAML Configuration**
   - Click "Import web service"
   - Choose file: `examples/api/TicketAPI_WebService.yml` from your MSSTLite installation directory
   - Or copy the content and paste it
   - Click "Import"

## API Endpoints Created

After import, these endpoints will be available:

### Session Management
- `POST /Webservice/TicketAPI/Session` - Create session
- `GET /Webservice/TicketAPI/Session/:SessionID` - Get session info
- `DELETE /Webservice/TicketAPI/Session/:SessionID` - Remove session

### Ticket Operations
- `POST /Webservice/TicketAPI/Ticket` - Create ticket
- `GET /Webservice/TicketAPI/Ticket/:TicketID` - Get ticket
- `PATCH /Webservice/TicketAPI/Ticket/:TicketID` - Update ticket
- `GET /Webservice/TicketAPI/TicketSearch` - Search tickets
- `GET /Webservice/TicketAPI/TicketHistory/:TicketID` - Get ticket history

## Postman Examples

### 1. Create Session (Login)
```
POST http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/Session
Content-Type: application/json

{
  "UserLogin": "YOUR_USERNAME",
  "Password": "YOUR_PASSWORD"
}
```

Expected Response:
```json
{
  "SessionID": "YOUR_SESSION_ID"
}
```

### 2. Create Ticket
```
POST http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/Ticket
Content-Type: application/json

{
  "SessionID": "YOUR_SESSION_ID",
  "Ticket": {
    "Title": "Test Ticket from API",
    "Queue": "Raw",
    "State": "new",
    "Priority": "3 normal",
    "CustomerUser": "YOUR_CUSTOMER_USER"
  },
  "Article": {
    "Subject": "Initial Article",
    "Body": "This ticket was created via REST API",
    "ContentType": "text/plain; charset=utf8",
    "ArticleType": "note-external",
    "SenderType": "agent"
  }
}
```

Expected Response:
```json
{
  "TicketID": "75",
  "TicketNumber": "2025062810000016",
  "ArticleID": "87"
}
```

### 3. Get Ticket
```
GET http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/Ticket/75?SessionID=YOUR_SESSION_ID

OR with POST:

POST http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/Ticket/75
Content-Type: application/json

{
  "SessionID": "YOUR_SESSION_ID",
  "AllArticles": 1,
  "DynamicFields": 1,
  "Extended": 1,
  "Attachments": 1
}
```

### 4. Update Ticket
```
PATCH http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/Ticket/75
Content-Type: application/json

{
  "SessionID": "YOUR_SESSION_ID",
  "Ticket": {
    "State": "open",
    "Priority": "4 high",
    "Title": "Updated: Test Ticket from API"
  },
  "Article": {
    "Subject": "Update Note",
    "Body": "Ticket has been updated via API",
    "ContentType": "text/plain; charset=utf8",
    "ArticleType": "note-internal",
    "SenderType": "agent"
  }
}
```

### 5. Search Tickets
```
POST http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/TicketSearch
Content-Type: application/json

{
  "SessionID": "YOUR_SESSION_ID",
  "States": ["new", "open", "pending reminder"],
  "Queues": ["Raw"],
  "Priority": ["3 normal", "4 high", "5 very high"],
  "CreatedAfter": "2025-06-01 00:00:00",
  "Limit": 100,
  "SortBy": ["Age"],
  "OrderBy": ["Down"]
}
```

### 6. Get Ticket History
```
GET http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/TicketHistory/75?SessionID=YOUR_SESSION_ID
```

### 7. Remove Session (Logout)
```
DELETE http://YOUR_ZNUNY_SERVER/otrs/nph-genericinterface.pl/Webservice/TicketAPI/Session/YOUR_SESSION_ID
```

## Postman Collection Variables

Create these environment variables:
- `host`: YOUR_ZNUNY_SERVER
- `base_path`: /otrs/nph-genericinterface.pl
- `webservice`: TicketAPI
- `username`: YOUR_USERNAME
- `password`: YOUR_PASSWORD
- `session_id`: (automatically set after login)

## Postman Pre-request Script

Add this to collection level to auto-manage sessions:

```javascript
// Auto-login if no session
if (!pm.environment.get("session_id") && !pm.request.url.path.includes("Session")) {
    const loginRequest = {
        url: `http://${pm.environment.get("host")}${pm.environment.get("base_path")}/Webservice/${pm.environment.get("webservice")}/Session`,
        method: 'POST',
        header: { 'Content-Type': 'application/json' },
        body: {
            mode: 'raw',
            raw: JSON.stringify({
                "UserLogin": pm.environment.get("username"),
                "Password": pm.environment.get("password")
            })
        }
    };
    
    pm.sendRequest(loginRequest, (err, res) => {
        if (!err && res.code === 200) {
            const response = res.json();
            pm.environment.set("session_id", response.SessionID);
            console.log("Auto-login successful");
        }
    });
}
```

## Test Script for Session Endpoint

Add to SessionCreate request:

```javascript
if (pm.response.code === 200) {
    const response = pm.response.json();
    pm.environment.set("session_id", response.SessionID);
    console.log("Session saved: " + response.SessionID);
}
```

## Common Fields Reference

### Ticket States
- `new`
- `open`
- `pending reminder`
- `pending auto close+`
- `pending auto close-`
- `closed successful`
- `closed unsuccessful`
- `merged`
- `removed`

### Priorities
- `1 very low`
- `2 low`
- `3 normal`
- `4 high`
- `5 very high`

### Article Types
- `note-internal` - Internal note
- `note-external` - External note
- `email-external` - Email
- `phone` - Phone call
- `webrequest` - Web request

### Sender Types
- `agent` - Agent/Staff
- `system` - System
- `customer` - Customer

## Troubleshooting

1. **Empty Response**: Web service not imported or not valid
2. **403 Forbidden**: License check failed - check your MSSTLite license validity
3. **500 Error**: Check Apache error logs
4. **"No Permission"**: User lacks access to queue/operation
5. **"Invalid SessionID"**: Session expired, create new one