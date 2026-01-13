#!/usr/bin/perl
# Test notification with existing customer

use strict;
use warnings;

# Get Znuny path from environment or use default
BEGIN {
    # For this specific server, use the actual path if ZNUNY_ROOT is not set
    my $znuny_root = $ENV{ZNUNY_ROOT} || '/opt/znuny-6.5.15';
    unshift @INC, "$znuny_root";
    unshift @INC, "$znuny_root/Kernel/cpan-lib";
    unshift @INC, "$znuny_root/Custom";
}

my $znuny_root = $ENV{ZNUNY_ROOT} || '/opt/znuny-6.5.15';

use Kernel::System::ObjectManager;
local $Kernel::OM = Kernel::System::ObjectManager->new();

my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

print "=== Testing with Existing Customer ===\n\n";

# Use the existing customer
my $CustomerUserID = 'markryan.orosa';
print "Using existing customer: $CustomerUserID\n";

# Verify customer
my %CustomerUser = $CustomerUserObject->CustomerUserDataGet(
    User => $CustomerUserID,
);

print "Customer: $CustomerUser{UserFirstname} $CustomerUser{UserLastname}\n";
print "Email: $CustomerUser{UserEmail}\n\n";

# Create ticket
print "Creating ticket...\n";
my $TicketID = $TicketObject->TicketCreate(
    Title        => 'Notification Test - ' . localtime(),
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'new',
    CustomerID   => $CustomerUser{UserCustomerID} || 'TestCompany',
    CustomerUser => $CustomerUserID,
    OwnerID      => 1,
    UserID       => 1,
);

print "Created ticket: $TicketID\n";

# Get ticket details
my %Ticket = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => 1,
);

print "Ticket Number: $Ticket{TicketNumber}\n";
print "CustomerUser in ticket: $Ticket{CustomerUserID}\n\n";

# Create article - this should trigger ArticleCreate event
print "Creating article...\n";
my $ArticleBackendObject = $ArticleObject->BackendForChannel(
    ChannelName => 'Email',
);

my $ArticleID = $ArticleBackendObject->ArticleCreate(
    TicketID             => $TicketID,
    IsVisibleForCustomer => 1,
    SenderType           => 'agent',
    Subject              => 'Test Article for Notification',
    Body                 => 'This is a test article that should trigger customer notification.',
    ContentType          => 'text/plain; charset=utf-8',
    HistoryType          => 'EmailAgent',
    HistoryComment       => 'Customer notification test',
    UserID               => 1,
    NoAgentNotify        => 0,
);

print "Created article: $ArticleID\n\n";

# Also trigger events manually to be sure
print "Manually triggering notification events...\n";
my $EventObject = $Kernel::OM->Get('Kernel::System::Ticket::Event::NotificationEvent');

for my $Event ('NotificationNewTicket', 'ArticleCreate', 'TicketCreate') {
    print "  Triggering: $Event... ";
    my $Result = $EventObject->Run(
        Event => $Event,
        Data  => {
            TicketID  => $TicketID,
            ArticleID => $ArticleID,
        },
        Config => {},
        UserID => 1,
    );
    print $Result ? "OK\n" : "FAILED\n";
}

print "\nWaiting for queue processing...\n";
sleep(5);

# Check mail queue
print "\nChecking mail queue...\n";
system("su - znuny -c '$znuny_root/bin/otrs.Console.pl Maint::Email::MailQueue --list 2>&1' | grep -v ERROR | grep -v Traceback");

print "\nDone.\n";