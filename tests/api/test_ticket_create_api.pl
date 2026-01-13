#!/usr/bin/perl
# Test script to create a ticket directly using Znuny API operations
# This bypasses the web service layer to test the operation directly

use strict;
use warnings;

# Get Znuny path from environment or try to detect it
BEGIN {
    my $znuny_root;
    
    # First check environment variable
    if ($ENV{ZNUNY_ROOT}) {
        $znuny_root = $ENV{ZNUNY_ROOT};
    }
    # Try common installation paths
    elsif (-d '/opt/znuny-6.5.15') {
        $znuny_root = '/opt/znuny-6.5.15';
    }
    elsif (-d '/opt/znuny') {
        $znuny_root = '/opt/znuny';
    }
    else {
        die "Cannot find Znuny installation. Please set ZNUNY_ROOT environment variable.\n";
    }
    
    unshift @INC, "$znuny_root";
    unshift @INC, "$znuny_root/Kernel/cpan-lib";
    unshift @INC, "$znuny_root/Custom";
}

# Re-get the paths for use in the script
my $znuny_root = $ENV{ZNUNY_ROOT} || (-d '/opt/znuny-6.5.15' ? '/opt/znuny-6.5.15' : '/opt/znuny');
my $server_url = $ENV{ZNUNY_SERVER} || 'localhost';

use Kernel::System::ObjectManager;
use Data::Dumper;

# Create object manager
local $Kernel::OM = Kernel::System::ObjectManager->new();

# Get necessary objects
my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
my $UserObject = $Kernel::OM->Get('Kernel::System::User');
my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

print "Testing Ticket Creation via API\n";
print "================================\n\n";

# First, check if we can authenticate
my $user_login = $ENV{ZNUNY_USER} || 'root@localhost';
my $UserID = $UserObject->UserLookup(
    UserLogin => $user_login,
);

if (!$UserID) {
    print "Error: Could not find user $user_login\n";
    exit 1;
}

print "✓ User found: $user_login (ID: $UserID)\n\n";

# Create a test ticket
print "Creating test ticket...\n";

my $TicketID = $TicketObject->TicketCreate(
    Title        => 'Test Ticket Created via API',
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'new',
    TypeID       => 2,  # Incident type for testing prefix
    CustomerUser => 'customer@example.com',
    OwnerID      => $UserID,
    UserID       => $UserID,
);

if (!$TicketID) {
    print "Error: Could not create ticket\n";
    exit 1;
}

print "✓ Ticket created successfully! TicketID: $TicketID\n";

# Get ticket number
my $TicketNumber = $TicketObject->TicketNumberLookup(
    TicketID => $TicketID,
);

print "✓ Ticket Number: $TicketNumber\n\n";

# Add an article to the ticket
print "Adding article to ticket...\n";

my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
my $ArticleBackendObject = $ArticleObject->BackendForChannel(ChannelName => 'Internal');

my $ArticleID = $ArticleBackendObject->ArticleCreate(
    TicketID             => $TicketID,
    IsVisibleForCustomer => 1,
    SenderType           => 'agent',
    Subject              => 'Test Article via API',
    Body                 => 'This is a test article created through the API.',
    ContentType          => 'text/plain; charset=UTF-8',
    HistoryType          => 'AddNote',
    HistoryComment       => 'Added via API test',
    UserID               => $UserID,
);

if ($ArticleID) {
    print "✓ Article added successfully! ArticleID: $ArticleID\n";
} else {
    print "✗ Failed to add article\n";
}

print "\n";
print "Ticket Details:\n";
print "--------------\n";
print "TicketID: $TicketID\n";
print "TicketNumber: $TicketNumber\n";
print "Title: Test Ticket Created via API\n";
print "Queue: Raw\n";
print "State: new\n";
print "Priority: 3 normal\n";
print "\n";
print "You can view this ticket at:\n";
print "http://$server_url/otrs/index.pl?Action=AgentTicketZoom;TicketID=$TicketID\n";