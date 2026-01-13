package Kernel::System::Ticket::Event::IncidentLockManager;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::System::Ticket',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Check needed params
    for my $Needed (qw(Data Event Config)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # Only handle StateUpdate events
    return 1 if $Param{Event} ne 'TicketStateUpdate';

    my $TicketID = $Param{Data}->{TicketID};
    return 1 if !$TicketID;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    
    # Get ticket details
    my %Ticket = $TicketObject->TicketGet(
        TicketID => $TicketID,
        UserID   => 1,
    );

    # Only process incident tickets
    return 1 if $Ticket{Type} !~ /incident/i;

    # Auto-lock if state is closed or cancelled
    if ( $Ticket{State} =~ /^(closed|cancelled)/i && $Ticket{Lock} eq 'unlock' ) {
        $TicketObject->TicketLockSet(
            Lock     => 'lock',
            TicketID => $TicketID,
            UserID   => $Param{UserID} || 1,
        );
    }
    # Auto-unlock if state is changed from closed/cancelled to active
    elsif ( $Ticket{State} !~ /^(closed|cancelled)/i && $Ticket{Lock} eq 'lock' ) {
        # Check if previous state was closed/cancelled
        my @HistoryLines = $TicketObject->HistoryGet(
            TicketID => $TicketID,
            UserID   => 1,
        );
        
        # Get the second to last state (before current change)
        my $PreviousState = '';
        for my $i (reverse 0..$#HistoryLines) {
            if ($HistoryLines[$i]->{HistoryType} eq 'StateUpdate') {
                $PreviousState = $HistoryLines[$i]->{Name} || '';
                last;
            }
        }
        
        # Only auto-unlock if coming from closed/cancelled state
        if ($PreviousState =~ /^(closed|cancelled)/i) {
            $TicketObject->TicketLockSet(
                Lock     => 'unlock',
                TicketID => $TicketID,
                UserID   => $Param{UserID} || 1,
            );
        }
    }

    return 1;
}

1;