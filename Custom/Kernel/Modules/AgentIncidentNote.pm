package Kernel::Modules::AgentIncidentNote;

use strict;
use warnings;

use parent qw(Kernel::Modules::AgentTicketNote);

# Override new() to add incident-specific initialization
sub new {
    my ( $Type, %Param ) = @_;
    
    my $Self = $Type->SUPER::new(%Param);
    
    # Add incident-specific configuration
    $Self->{IncidentMode} = 1;
    
    return $Self;
}

# Override Run() to add incident-specific logic
sub Run {
    my ( $Self, %Param ) = @_;
    
    # Check if ticket is an incident type
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Self->{TicketID},
        UserID   => $Self->{UserID},
    );
    
    # Verify this is an incident ticket
    if ($Ticket{Type} !~ /incident/i) {
        return $Self->SUPER::Run(%Param);
    }
    
    # Check ticket state for editability
    if ($Ticket{State} =~ /^(closed|cancelled)/i) {
        my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
        return $LayoutObject->ErrorScreen(
            Message => 'Cannot update incidents in closed or cancelled state',
            Comment => 'Please contact your administrator if you need to update this incident.',
        );
    }
    
    # Check if ticket is locked (only locked tickets cannot be edited)
    if ($Ticket{Lock} eq 'lock') {
        my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
        return $LayoutObject->ErrorScreen(
            Message => 'This incident is locked and cannot be updated',
            Comment => 'Only unlocked incidents can be edited.',
        );
    }
    
    # Continue with normal processing
    return $Self->SUPER::Run(%Param);
}

1;