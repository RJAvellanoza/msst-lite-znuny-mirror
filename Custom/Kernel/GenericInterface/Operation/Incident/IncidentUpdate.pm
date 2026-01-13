# --
# Copyright (C) 2024 Radiant Digital, radiant.digital
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::GenericInterface::Operation::Incident::IncidentUpdate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsStringWithData IsHashRefWithData IsArrayRefWithData);

use parent qw(
    Kernel::GenericInterface::Operation::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Operation::Incident::IncidentUpdate - GenericInterface Incident Update Operation backend

=head1 DESCRIPTION

=head2 new()

usually, you want to create an instance of this
by using Kernel::GenericInterface::Operation->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw(DebuggerObject WebserviceID)) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    return $Self;
}

=head2 Run()

perform IncidentUpdate Operation. This will update an existing incident.

    my $Result = $OperationObject->Run(
        Data => {
            SessionID => '1234567890123456',  # Optional, if not provided UserLogin and Password must be provided
            UserLogin => 'some agent',       # Optional, if not provided SessionID must be provided  
            Password  => 'some password',    # Optional, if not provided SessionID must be provided

            IncidentID => 123,               # Required - Either IncidentID or TicketID or IncidentNumber
            TicketID   => 456,               # Alternative to IncidentID
            IncidentNumber => 'INC00001',    # Alternative to IncidentID/TicketID

            Incident => {
                Priority         => 'P2-High',                    # Optional
                State            => 'In Progress',               # Optional
                CI               => 'Configuration Item Name',   # Optional
                AssignedTo       => 'agent_login',               # Optional
                ShortDescription => 'Updated description',       # Optional
                Description      => 'Updated detailed desc',    # Optional
                ProductCat1      => 'Product Category 1',       # Optional
                ProductCat2      => 'Product Category 2',       # Optional
                ProductCat3      => 'Product Category 3',       # Optional
                ProductCat4      => 'Product Category 4',       # Optional
                OperationalCat1  => 'Operational Category 1',   # Optional
                OperationalCat2  => 'Operational Category 2',   # Optional
                OperationalCat3  => 'Operational Category 3',   # Optional
                ResolutionCat1   => 'Resolution Category 1',    # Optional
                ResolutionCat2   => 'Resolution Category 2',    # Optional
                ResolutionCat3   => 'Resolution Category 3',    # Optional
                ResolutionNotes  => 'Resolution notes',         # Optional
                WorkNotes        => 'Work notes to add',        # Optional
            },
        },
    );

    $Result = {
        Success => 1,                       # 0 or 1
        ErrorMessage => '',                 # In case of an error
        Data => {
            IncidentID => 123,
            TicketID   => 456,
            Error => {
                ErrorCode    => 'IncidentUpdate.InvalidParameter',
                ErrorMessage => 'Incident parameter is missing!',
            },
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !IsHashRefWithData( $Param{Data} ) ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentUpdate.MissingParameter',
            ErrorMessage => "IncidentUpdate: The request is empty!",
        );
    }

    # Check authentication
    my ($UserID, $UserType) = $Self->Auth(
        Data => $Param{Data},
    );
    
    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentUpdate.AuthFail',
            ErrorMessage => "IncidentUpdate: Authorization failing!",
        );
    }

    # Get incident/ticket ID
    my $TicketID;
    my $IncidentID;
    
    if ( $Param{Data}->{IncidentID} ) {
        # Check if it's an incident number (INC-XXXXXXX) or numeric ID
        if ( $Param{Data}->{IncidentID} =~ /^INC-/ ) {
            # This is an incident number, look it up
            my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
            $TicketID = $TicketObject->TicketIDLookup(
                TicketNumber => $Param{Data}->{IncidentID},
                UserID       => $UserID,
            );
            $IncidentID = $TicketID if $TicketID;
        }
        else {
            # This is a numeric incident ID
            $IncidentID = $Param{Data}->{IncidentID};
            $TicketID = $IncidentID;  # In our system, IncidentID = TicketID
        }
    }
    elsif ( $Param{Data}->{TicketID} ) {
        $TicketID = $Param{Data}->{TicketID};
        $IncidentID = $TicketID;
    }
    elsif ( $Param{Data}->{IncidentNumber} ) {
        # Look up ticket by incident number
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
        $TicketID = $TicketObject->TicketIDLookup(
            TicketNumber => $Param{Data}->{IncidentNumber},
            UserID       => $UserID,
        );
        $IncidentID = $TicketID if $TicketID;
    }

    if ( !$TicketID ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentUpdate.MissingParameter',
            ErrorMessage => "IncidentUpdate: IncidentID, TicketID, or IncidentNumber is required!",
        );
    }

    # Check if ticket exists and user has access
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my %TicketData = $TicketObject->TicketGet(
        TicketID      => $TicketID,
        UserID        => $UserID,
        DynamicFields => 1,
        Extended      => 1,
    );

    if ( !%TicketData ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentUpdate.AccessDenied',
            ErrorMessage => "IncidentUpdate: Ticket not found or access denied!",
        );
    }

    # Check if data is directly in Param{Data} instead of Param{Data}->{Incident}
    my %Incident;
    if ( IsHashRefWithData( $Param{Data}->{Incident} ) ) {
        %Incident = %{ $Param{Data}->{Incident} };
    }
    else {
        # Data might be directly in the root (exclude auth and ID fields)
        %Incident = %{ $Param{Data} };
        delete $Incident{SessionID};
        delete $Incident{UserLogin};
        delete $Incident{Password};
        delete $Incident{IncidentID};
        delete $Incident{TicketID};
        delete $Incident{IncidentNumber};
    }

    if ( !%Incident ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentUpdate.MissingParameter',
            ErrorMessage => "IncidentUpdate: No incident data provided for update!",
        );
    }

    # Priority mapping: P1, P2, P3, P4 -> Znuny ticket priorities
    my %PriorityMapping = (
        'P1' => 'P1-Critical',
        'P2' => 'P2-High',
        'P3' => 'P3-Medium',
        'P4' => 'P4-Low',
    );

    # Handle priority mapping - support both short (P1) and full (P1-Critical) formats
    if ( $Incident{Priority} ) {
        if ( exists $PriorityMapping{$Incident{Priority}} ) {
            # Short format like P1, P2, etc.
            my $OriginalPriority = $Incident{Priority};  # Store P1, P2, etc.
            
            # Set Znuny Ticket Priority (system field)
            $Incident{Priority} = $PriorityMapping{$OriginalPriority};
            
            # Set IncidentPriority dynamic field to P1, P2, etc.
            $Incident{IncidentPriority} = $OriginalPriority;
        }
        elsif ( $Incident{Priority} =~ /^P[1-4]-(Critical|High|Medium|Low)$/ ) {
            # Already in full format like P2-High, extract short form for dynamic field
            if ( $Incident{Priority} =~ /^(P[1-4])-/ ) {
                $Incident{IncidentPriority} = $1;  # Store P1, P2, etc. in dynamic field
            }
            # Priority field already has correct format for ticket
        }
    }

    # Get incident object
    my $IncidentObject = $Kernel::OM->Get('Kernel::System::Incident');

    # Update incident
    my $Success = $IncidentObject->IncidentUpdate(
        IncidentID => $IncidentID,
        %Incident,
        UserID => $UserID,
    );

    if ( !$Success ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentUpdate.UpdateFailed',
            ErrorMessage => "IncidentUpdate: Incident could not be updated!",
        );
    }

    # Get updated ticket data
    %TicketData = $TicketObject->TicketGet(
        TicketID      => $TicketID,
        UserID        => $UserID,
        DynamicFields => 1,
        Extended      => 1,
    );

    # Get updated incident data
    my %IncidentData = $IncidentObject->IncidentGet(
        IncidentID => $IncidentID,
        UserID     => $UserID,
    );

    # SMS notifications are now handled by the event handler (SMSNotification.pm)
    # which automatically catches state changes and sends SMS

    return {
        Success => 1,
        Data    => {
            IncidentID   => $IncidentID,
            TicketID     => $TicketID,
            TicketNumber => $TicketData{TicketNumber} || '',
            Message      => "Incident $IncidentID updated successfully" . 
                           ($TicketData{TicketNumber} ? " (ticket number " . $TicketData{TicketNumber} . ")" : ""),
        },
    };
}

1;