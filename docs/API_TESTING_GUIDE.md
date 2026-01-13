# Znuny API Testing Guide for Postman

## Important Note: License Blocking
**With MSSTLite installed and no valid license, all API calls will return:**
```json
{
  "Error": "Access denied. Invalid or expired license.",
  "LicenseStatus": "NotFound"
}
```
HTTP Status: 403 Forbidden

To test the actual APIs, you'll need to upload a valid license first.

## Base URL
```
http://localhost/otrs/nph-genericinterface.pl/Webservice/{WebserviceName}/{Operation}
```

## Available Operations in Znuny

### 1. Session Management

#### Create Session (Login)
```
POST /Webservice/GenericTicketConnectorREST/SessionCreate
Content-Type: application/json

{
  "UserLogin": "YOUR_USERNAME",
  "Password": "your-password"
}
```

Response:
```json
{
  "SessionID": "1234567890abcdef..."
}
```

#### Get Session Info
```
POST /Webservice/GenericTicketConnectorREST/SessionGet
Content-Type: application/json

{
  "SessionID": "1234567890abcdef..."
}
```

#### Remove Session (Logout)
```
POST /Webservice/GenericTicketConnectorREST/SessionRemove
Content-Type: application/json

{
  "SessionID": "1234567890abcdef..."
}
```

### 2. Ticket Operations

#### Create Ticket
```
POST /Webservice/GenericTicketConnectorREST/TicketCreate
Content-Type: application/json

{
  "SessionID": "1234567890abcdef...",
  "Ticket": {
    "Title": "Test Ticket from API",
    "Queue": "Raw",
    "State": "new",
    "Priority": "3 normal",
    "CustomerUser": "customer@example.com"
  },
  "Article": {
    "Subject": "Test Article",
    "Body": "This is a test ticket created via API",
    "ContentType": "text/plain; charset=utf8",
    "ArticleType": "note-external",
    "SenderType": "customer"
  }
}
```

#### Search Tickets
```
POST /Webservice/GenericTicketConnectorREST/TicketSearch
Content-Type: application/json

{
  "SessionID": "1234567890abcdef...",
  "States": ["new", "open"],
  "Queues": ["Raw"],
  "Limit": 10
}
```

#### Get Ticket Details
```
POST /Webservice/GenericTicketConnectorREST/TicketGet
Content-Type: application/json

{
  "SessionID": "1234567890abcdef...",
  "TicketID": 1,
  "AllArticles": 1,
  "Attachments": 1
}
```

#### Update Ticket
```
POST /Webservice/GenericTicketConnectorREST/TicketUpdate
Content-Type: application/json

{
  "SessionID": "1234567890abcdef...",
  "TicketID": 1,
  "Ticket": {
    "State": "open",
    "Priority": "4 high"
  },
  "Article": {
    "Subject": "Update via API",
    "Body": "Ticket updated through API",
    "ContentType": "text/plain; charset=utf8"
  }
}
```

### 3. User Operations

#### Get/Set Out of Office
```
POST /Webservice/GenericTicketConnectorREST/OutOfOffice
Content-Type: application/json

{
  "SessionID": "1234567890abcdef...",
  "UserLogin": "agent",
  "OutOfOffice": 1,
  "OutOfOfficeStartYear": 2025,
  "OutOfOfficeStartMonth": 6,
  "OutOfOfficeStartDay": 28,
  "OutOfOfficeEndYear": 2025,
  "OutOfOfficeEndMonth": 7,
  "OutOfOfficeEndDay": 5
}
```

## Setting up Postman

### 1. Create Environment Variables
- `base_url`: http://localhost/otrs/nph-genericinterface.pl
- `session_id`: (will be set after login)

### 2. Create Pre-request Script for Authentication
```javascript
// For endpoints that need SessionID
if (!pm.environment.get("session_id")) {
    console.log("No session ID found. Please login first.");
}
```

### 3. Create a Collection with:
1. **Login Request** - saves SessionID to environment
2. **API Requests** - uses {{session_id}} from environment
3. **Logout Request** - cleans up session

### 4. Login Request Script (Tests tab)
```javascript
if (pm.response.code === 200) {
    var jsonData = pm.response.json();
    if (jsonData.SessionID) {
        pm.environment.set("session_id", jsonData.SessionID);
        console.log("Session ID saved: " + jsonData.SessionID);
    }
}
```

## Common Issues

1. **403 Forbidden with License Error**
   - MSSTLite is blocking API access due to missing/invalid license
   - Upload a valid license through the web interface

2. **500 Internal Server Error**
   - Web service might not be configured
   - Check if the web service name is correct

3. **No Response**
   - Check if Apache is running
   - Check Apache error logs: `/path/to/apache/error.log`

## Testing License Blocking

To specifically test that license blocking is working:

```
GET /Webservice/Test
```

Expected Response (403):
```json
{
  "Error": "Access denied. Invalid or expired license.",
  "LicenseStatus": "NotFound"
}
```

## Note on Web Services

Znuny doesn't come with pre-configured REST web services by default. You need to:
1. Go to Admin → Web Service Management
2. Add a new web service
3. Configure it as REST
4. Add the operations you want to expose
5. Use the web service name in your API calls

The "GenericTicketConnectorREST" mentioned above is a common example name, but you'll need to create and configure it first.