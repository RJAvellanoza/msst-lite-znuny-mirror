#!/bin/bash
# Test API ticket creation and SMTP notification

echo "=== Testing API Ticket Creation with SMTP Notification ==="
echo ""

# Variables
BASE_URL="http://localhost/otrs/nph-genericinterface.pl/Webservice/TicketAPI"
USER="root@localhost"
PASS="JluBLzI8VTKotTZB"

# Step 1: Create session
echo "1. Creating session..."
SESSION_RESPONSE=$(curl -s -X POST \
  "$BASE_URL/Session" \
  -H "Content-Type: application/json" \
  -d "{
    \"UserLogin\": \"$USER\",
    \"Password\": \"$PASS\"
  }")

SESSION_ID=$(echo "$SESSION_RESPONSE" | grep -o '"SessionID":"[^"]*"' | cut -d'"' -f4)

if [ -z "$SESSION_ID" ]; then
    echo "Failed to create session!"
    echo "Response: $SESSION_RESPONSE"
    exit 1
fi

echo "Session created: $SESSION_ID"
echo ""

# Step 2: Create ticket
echo "2. Creating ticket via API..."
TICKET_RESPONSE=$(curl -s -X POST \
  "$BASE_URL/Ticket" \
  -H "Content-Type: application/json" \
  -d "{
    \"SessionID\": \"$SESSION_ID\",
    \"Ticket\": {
      \"Title\": \"API Test - SMTP Notification - $(date)\",
      \"Queue\": \"Raw\",
      \"State\": \"new\",
      \"Priority\": \"3 normal\",
      \"CustomerUser\": \"markryan.orosa\"
    },
    \"Article\": {
      \"Subject\": \"API Test Article\",
      \"Body\": \"This ticket was created via REST API to test SMTP notifications.\",
      \"ContentType\": \"text/plain; charset=utf8\",
      \"ArticleType\": \"note-external\",
      \"SenderType\": \"agent\"
    }
  }")

echo "Response: $TICKET_RESPONSE"
echo ""

# Extract ticket ID
TICKET_ID=$(echo "$TICKET_RESPONSE" | grep -o '"TicketID":"[^"]*"' | cut -d'"' -f4)
TICKET_NUMBER=$(echo "$TICKET_RESPONSE" | grep -o '"TicketNumber":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TICKET_ID" ]; then
    echo "Failed to create ticket!"
    exit 1
fi

echo "Ticket created: ID=$TICKET_ID, Number=$TICKET_NUMBER"
echo ""

# Step 3: Wait and check mail queue
echo "3. Waiting 5 seconds for mail queue processing..."
sleep 5

echo ""
echo "4. Checking mail queue..."
su - znuny -c "/opt/znuny-6.5.15/bin/otrs.Console.pl Maint::Email::MailQueue --list"

echo ""
echo "5. Checking notification event configuration..."
su - znuny -c "/opt/znuny-6.5.15/bin/otrs.Console.pl Admin::Config::List" | grep -i smtp

echo ""
echo "Done."