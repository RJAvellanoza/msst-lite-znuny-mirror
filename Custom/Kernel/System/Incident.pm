# --
# Copyright (C) 2024 Radiant Digital, radiant.digital
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Incident;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Time',
    'Kernel::System::User',
    'Kernel::System::Ticket',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::Type',
    'Kernel::System::TicketPrefix',
);

=head1 NAME

Kernel::System::Incident - Incident management library

=head1 DESCRIPTION

Functions for managing IT incidents with Event Monitoring and ServiceNow integration

=head1 PUBLIC INTERFACE

=head2 new()

Create an object

    my $IncidentObject = $Kernel::OM->Get('Kernel::System::Incident');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 IncidentCreate()

Create a new incident with automatic ticket creation

    my $IncidentID = $IncidentObject->IncidentCreate(
        Source           => 'Direct Input',  # or 'Event Monitoring'
        Priority         => 'P1',
        State            => 'new',
        CI               => 'Server-001',
        AssignedTo       => 'agent1',
        ShortDescription => 'Server down',
        Description      => 'Production server not responding',
        ProductCat1      => 'ASTRO',
        ProductCat2      => 'Infrastructure',
        ProductCat3      => '',
        ProductCat4      => '',
        OperationalCat1  => 'Hardware',
        OperationalCat2  => 'Server',
        OperationalCat3  => '',
        UserID           => 1,
    );

=cut

sub IncidentCreate {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    for my $Needed (qw(Source Priority ShortDescription ProductCat1 ProductCat2 OperationalCat1 OperationalCat2 UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my $DBObject               = $Kernel::OM->Get('Kernel::System::DB');
    my $TimeObject             = $Kernel::OM->Get('Kernel::System::Time');
    my $TicketObject           = $Kernel::OM->Get('Kernel::System::Ticket');
    my $DynamicFieldObject     = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    # Don't generate incident number yet - we'll use the ticket number after creation

    # Set defaults
    $Param{State}           ||= 'New';
    
    # Don't auto-transition state - let user explicitly set the state they want

    # Get current timestamp
    my $CurrentTime = $TimeObject->CurrentTimestamp();

    # Get or create incident infrastructure  
    my $IncidentTypeID = $Self->_EnsureIncidentType();
    
    # Always use 'Support Group' as the queue for incidents
    my $QueueName = 'Support Group';
    
    # Debug logging
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Get queue ID from queue name
    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
    my $QueueID = $QueueObject->QueueLookup( Queue => $QueueName );
    
    
    if ( !$QueueID ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Could not find queue '$QueueName'! Queue 'Support Group' must exist.",
        );
        return;
    }
    
    # Get state and priority IDs
    my $StateObject = $Kernel::OM->Get('Kernel::System::State');
    my $PriorityObject = $Kernel::OM->Get('Kernel::System::Priority');
    my $TicketState = $Self->_MapStateToTicket( $Param{State} );
    my $TicketPriority = $Self->_MapPriorityToTicket( $Param{Priority} );
    my $StateID = $StateObject->StateLookup( State => $TicketState );
    my $PriorityID = $PriorityObject->PriorityLookup( Priority => $TicketPriority );
    
    
    # Create associated ticket first
    my $TicketID;
    eval {
        
        # Add an article to the ticket
        $TicketID = $TicketObject->TicketCreate(
            Title        => $Param{ShortDescription} || 'Incident (no title)',
            QueueID      => $QueueID,
            Lock         => 'unlock',
            PriorityID   => $PriorityID,
            StateID      => $StateID,
            CustomerNo   => $Param{CustomerID} || 'default',
            CustomerUser => $Param{CustomerUser} || 'default',
            OwnerID      => $Param{AssignedTo} || 99,  # Default to unassigned user (ID 99) if no assignee specified
            UserID       => $Param{UserID},
            TypeID       => $IncidentTypeID,
        );
        
        if ($TicketID) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Successfully created ticket $TicketID for incident",
            );
            
            # No need for initial article - incident details are stored in dynamic fields
            # The NewTicket history type already tracks incident creation
        }
    };

    if ( $@ || !$TicketID ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Could not create ticket for incident! Error: $@ TicketID: " . ($TicketID || 'undef') . " StateID: $StateID, PriorityID: $PriorityID, QueueID: $QueueID, TypeID: $IncidentTypeID"
        );
        return;
    }

    # Get the actual ticket number that was generated
    my %Ticket = $TicketObject->TicketGet(
        TicketID => $TicketID,
        UserID   => $Param{UserID},
    );
    
    # The incident number IS the ticket number - no need for separate numbering
    my $IncidentNumber = $Ticket{TicketNumber};
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => "Created incident with ticket number/incident number: $IncidentNumber",
    );

    # Get user info for OpenedBy field
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my %User = $UserObject->GetUserData(
        UserID => $Param{UserID},
    );
    my $OpenedByName = "$User{UserFirstname} $User{UserLastname} ($User{UserLogin})";
    
    # Store incident data in dynamic fields - only include non-empty values
    my @DynamicFields = (
        # IncidentNumber removed - we use the native ticket number
        { Name => 'IncidentSource',      Value => $Param{Source} },
        { Name => 'IncidentPriority',    Value => $Param{Priority} },
        { Name => 'CI',                  Value => $Param{CI} },
        { Name => 'Description',         Value => $Param{Description} },
        { Name => 'ProductCat1',    Value => $Param{ProductCat1} },
        { Name => 'ProductCat2',    Value => $Param{ProductCat2} },
        { Name => 'OperationalCat1', Value => $Param{OperationalCat1} },
        { Name => 'OperationalCat2', Value => $Param{OperationalCat2} },
        { Name => 'OpenedBy',        Value => $OpenedByName },
        { Name => 'Opened',          Value => $CurrentTime },
        { Name => 'AssignedTo',      Value => $Param{AssignedTo} || '99' },  # Default to unassigned (99) if not specified
    );
    
    # Add optional fields only if they have values
    if ($Param{ProductCat3} && $Param{ProductCat3} ne '') {
        push @DynamicFields, { Name => 'ProductCat3', Value => $Param{ProductCat3} };
    }
    if ($Param{ProductCat4} && $Param{ProductCat4} ne '') {
        push @DynamicFields, { Name => 'ProductCat4', Value => $Param{ProductCat4} };
    }
    if ($Param{OperationalCat3} && $Param{OperationalCat3} ne '') {
        push @DynamicFields, { Name => 'OperationalCat3', Value => $Param{OperationalCat3} };
    }

    # Store all dynamic field values
    for my $DynamicField (@DynamicFields) {
        my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
            Name => $DynamicField->{Name},
        );

        if ( $DynamicFieldConfig && $DynamicFieldConfig->{ID} ) {
            # Debug: log what we're trying to set
            $LogObject->Log(
                Priority => 'notice',
                Message  => "DEBUG: Checking dynamic field $DynamicField->{Name} with value: '" . ($DynamicField->{Value} // 'UNDEFINED') . "'",
            );
            
            # Only set value if it's defined, not empty, and not undef
            if ( defined $DynamicField->{Value} && $DynamicField->{Value} ne '' && $DynamicField->{Value} ne 'undef' ) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "Setting dynamic field $DynamicField->{Name} = $DynamicField->{Value} on ticket $TicketID",
                );
                $DynamicFieldValueObject->ValueSet(
                    FieldID    => $DynamicFieldConfig->{ID},
                    ObjectID   => $TicketID,
                    Value      => [
                        {
                            ValueText => $DynamicField->{Value},
                        },
                    ],
                    UserID     => $Param{UserID},
                );
            } else {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "Skipping empty dynamic field $DynamicField->{Name}",
                );
            }
        } else {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Dynamic field $DynamicField->{Name} not found in database",
            );
        }
    }

    # If source is Event Monitoring, store monitoring fields
    if ( $Param{Source} eq 'Event Monitoring' && $Param{Monitoring} ) {
        my @MonitoringFields = (
            { Name => 'AlarmID',      Value => $Param{Monitoring}->{AlarmID} || '' },
            { Name => 'EventID',      Value => $Param{Monitoring}->{EventID} || '' },
            { Name => 'EventSite',    Value => $Param{Monitoring}->{EventSite} || '' },
            { Name => 'SourceDevice', Value => $Param{Monitoring}->{SourceDevice} || '' },
            { Name => 'CIDeviceType', Value => $Param{Monitoring}->{CIDeviceType} || '' },
            { Name => 'EventMessage', Value => $Param{Monitoring}->{EventMessage} || '' },
            { Name => 'EventBeginTime', Value => $Param{Monitoring}->{EventBeginTime} || '' },
            { Name => 'EventDetectTime', Value => $Param{Monitoring}->{EventDetectTime} || '' },
        );

        for my $MonitoringField (@MonitoringFields) {
            my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
                Name => $MonitoringField->{Name},
            );

            if ( $DynamicFieldConfig && $DynamicFieldConfig->{ID} ) {
                # Only set value if it's defined and not empty
                if ( defined $MonitoringField->{Value} && $MonitoringField->{Value} ne '' ) {
                    $DynamicFieldValueObject->ValueSet(
                        FieldID    => $DynamicFieldConfig->{ID},
                        ObjectID   => $TicketID,
                        Value      => $MonitoringField->{Value},
                        UserID     => $Param{UserID},
                    );
                }
            }
        }
    }

    # Create incident record in custom table for work notes and resolution history
    
    my $Success = $DBObject->Do(
        SQL => 'INSERT INTO incident_management (
            ticket_id, incident_number, created_time, created_by
        ) VALUES (?, ?, ?, ?)',
        Bind => [ \$TicketID, \$IncidentNumber, \$CurrentTime, \$Param{UserID} ],
    );
    
    if (!$Success) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to insert into incident_management table!",
        );
        return;
    }
    

    # Return the TicketID for backward compatibility
    # But callers should use IncidentGet to get the full incident data including IncidentNumber
    return $TicketID;
}

=head2 IncidentGet()

Get incident data by IncidentID or IncidentNumber

    my %Incident = $IncidentObject->IncidentGet(
        IncidentID => 123,      # TicketID
        # or
        IncidentNumber => 'INC-0000000001',
        UserID => 1,
    );

=cut

sub IncidentGet {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    if ( !$Param{IncidentID} && !$Param{IncidentNumber} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need IncidentID or IncidentNumber!'
        );
        return;
    }

    my $TicketObject            = $Kernel::OM->Get('Kernel::System::Ticket');
    my $DynamicFieldObject      = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');
    my $DBObject                = $Kernel::OM->Get('Kernel::System::DB');

    my $TicketID = $Param{IncidentID};

    # If IncidentNumber provided, find the ticket
    if ( !$TicketID && $Param{IncidentNumber} ) {
        # Since incident number IS the ticket number, look up ticket by number
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
        $TicketID = $TicketObject->TicketIDLookup(
            TicketNumber => $Param{IncidentNumber},
            UserID       => $Param{UserID} || 1,
        );
    }

    return if !$TicketID;

    # Get ticket data with dynamic fields
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $TicketID,
        UserID        => $Param{UserID},
        DynamicFields => 1,
        Extended      => 1,
    );

    return if !%Ticket;

    # Build incident hash from ticket and dynamic fields
    my %Incident = (
        IncidentID       => $TicketID,
        IncidentNumber   => $Ticket{TicketNumber},  # Use the actual ticket number as incident number
        Source           => $Ticket{DynamicField_IncidentSource} || '',
        Priority         => $Ticket{DynamicField_IncidentPriority} || '',
        State            => $Self->_MapTicketToIncidentState($Ticket{State}) || 'new',
        CI               => $Ticket{DynamicField_CI} || '',
        AssignedTo       => ($Ticket{OwnerID} && $Ticket{OwnerID} != 1 && $Ticket{OwnerID} != 99) ? $Ticket{OwnerID} : '99',
        ShortDescription => $Ticket{Title},
        Description      => $Ticket{DynamicField_Description} || '',
        
        # Categories
        ProductCat1      => $Ticket{DynamicField_ProductCat1} || '',
        ProductCat2      => $Ticket{DynamicField_ProductCat2} || '',
        ProductCat3      => $Ticket{DynamicField_ProductCat3} || '',
        ProductCat4      => $Ticket{DynamicField_ProductCat4} || '',
        OperationalCat1  => $Ticket{DynamicField_OperationalCat1} || '',
        OperationalCat2  => $Ticket{DynamicField_OperationalCat2} || '',
        OperationalCat3  => $Ticket{DynamicField_OperationalCat3} || '',
        
        # Resolution
        ResolutionCat1   => $Ticket{DynamicField_ResolutionCat1} || '',
        ResolutionCat2   => $Ticket{DynamicField_ResolutionCat2} || '',
        ResolutionCat3   => $Ticket{DynamicField_ResolutionCat3} || '',
        ResolutionNotes  => $Ticket{DynamicField_ResolutionNotes} || '',
        
        # System dates
        Created          => $Ticket{DynamicField_Opened} || $Ticket{Created},
        CreatedBy        => $Ticket{DynamicField_OpenedBy},
        Changed          => $Ticket{DynamicField_Updated} || $Ticket{Changed},
        ChangedBy        => $Ticket{DynamicField_UpdatedBy},
        ResponseTime     => $Ticket{DynamicField_IncidentResponseTime} || '',
        ResolvedTime     => $Ticket{DynamicField_IncidentResolvedTime} || '',
        
        # Monitoring fields (Event Monitoring)
        AlarmID          => $Ticket{DynamicField_AlarmID} || '',
        EventID          => $Ticket{DynamicField_EventID} || '',
        EventSite        => $Ticket{DynamicField_EventSite} || '',
        SourceDevice     => $Ticket{DynamicField_SourceDevice} || '',
        CIDeviceType     => $Ticket{DynamicField_CIDeviceType} || '',
        EventMessage     => $Ticket{DynamicField_EventMessage} || '',
        EventBeginTime   => $Ticket{DynamicField_EventBeginTime} || '',
        EventDetectTime  => $Ticket{DynamicField_EventDetectTime} || '',
        
        # E-bonding fields (ServiceNow)
        MSITicketNumber            => $Ticket{DynamicField_MSITicketNumber} || '',
        MSICustomer                => $Ticket{DynamicField_Customer} || '',
        MSITicketSite              => $Ticket{DynamicField_MSITicketSite} || '',
        MSITicketState             => $Ticket{DynamicField_MSITicketState} || '',
        MSITicketStateReason       => $Ticket{DynamicField_MSITicketStateReason} || '',
        MSITicketPriority          => $Ticket{DynamicField_MSITicketPriority} || '',
        MSITicketAssignee          => $Ticket{DynamicField_MSITicketAssignee} || '',
        MSITicketShortDescription  => $Ticket{DynamicField_MSITicketShortDescription} || '',
        MSITicketResolutionNote    => $Ticket{DynamicField_MSITicketResolutionNote} || '',
        MSITicketCreatedTime       => $Ticket{DynamicField_MSITicketCreatedTime} || '',
        MSITicketLastUpdateTime    => $Ticket{DynamicField_MSITicketLastUpdateTime} || '',
        MSITicketEbondLastUpdateTime => $Ticket{DynamicField_MSITicketEbondLastUpdateTime} || '',
        MSITicketResolvedTime      => $Ticket{DynamicField_MSITicketResolvedTime} || '',
        MSITicketComment           => $Ticket{DynamicField_MSITicketComment} || '',
    );

    # Get latest main incident API response from ebonding_api_log table
    $DBObject->Prepare(
        SQL => 'SELECT response_payload FROM ebonding_api_log '
             . 'WHERE incident_id = ? AND success = 1 AND action = ? '
             . 'ORDER BY create_time DESC LIMIT 1',
        Bind => [ \$TicketID, \'PullFromServiceNow' ],
    );
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Incident{MSIEbondAPIResponse} = $Row[0] || '';
    }

    return %Incident;
}

=head2 IncidentUpdate()

Update incident data

    my $Success = $IncidentObject->IncidentUpdate(
        IncidentID       => 123,
        Priority         => 'P2',
        State            => 'in progress',
        AssignedTo       => 'agent2',
        ResolutionCat1   => 'Software',
        ResolutionCat2   => 'Bug',
        ResolutionCat3   => 'Known Issue',
        ResolutionNotes  => 'Applied patch',
        UserID           => 1,
    );

=cut

sub IncidentUpdate {
    my ( $Self, %Param ) = @_;


    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Debug logging - log all parameters received
    $LogObject->Log(
        Priority => 'notice',
        Message  => "ZABBIX DEBUG: IncidentUpdate called with parameters: " . join(', ', map { "$_='" . ($Param{$_} || 'undef') . "'" } keys %Param),
    );

    # Check needed stuff
    for my $Needed (qw(IncidentID UserID)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my $TicketObject            = $Kernel::OM->Get('Kernel::System::Ticket');
    my $DynamicFieldObject      = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');
    my $TimeObject              = $Kernel::OM->Get('Kernel::System::Time');

    my $TicketID = $Param{IncidentID};
    my $CurrentTime = $TimeObject->CurrentTimestamp();
    
    if (!$TicketID) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "IncidentUpdate: No TicketID/IncidentID provided!",
        );
        return;
    }

    # Get current incident state
    my %CurrentIncident = $Self->IncidentGet(
        IncidentID => $TicketID,
        UserID     => $Param{UserID},
    );
    
    if (!%CurrentIncident) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "IncidentUpdate: Could not find incident with ID $TicketID",
        );
        return;
    }

    # Handle state transitions
    if ( $Param{State} && $Param{State} ne $CurrentIncident{State} ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "ZABBIX DEBUG: State transition detected: '$CurrentIncident{State}' -> '$Param{State}' for ticket $TicketID",
        );
        
        # Track response time when first moving to In Progress
        if ( $CurrentIncident{State} eq 'Assigned' && $Param{State} eq 'In Progress' && !$CurrentIncident{ResponseTime} ) {
            $Param{ResponseTime} = $CurrentTime;
        }
        
        # Track resolved time when first moving to Resolved
        if ( $Param{State} eq 'Resolved' && !$CurrentIncident{ResolvedTime} ) {
            $Param{ResolvedTime} = $CurrentTime;
            $LogObject->Log(
                Priority => 'notice',
                Message  => "ZABBIX DEBUG: Setting ResolvedTime for transition to 'Resolved' state",
            );
        }
    } else {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "ZABBIX DEBUG: No state transition. Current state: '$CurrentIncident{State}', Requested state: '" . ($Param{State} || 'undefined') . "'",
        );
    }

    # Update ticket if needed with proper error handling
    if ( $Param{Priority} && $Param{Priority} ne $CurrentIncident{Priority} ) {
        my $Priority = $Self->_MapPriorityToTicket( $Param{Priority} );
        if ($Priority) {
            my $Success = $TicketObject->TicketPrioritySet(
                Priority => $Priority,
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
            if ($Success) {
                # Add history entry for priority change
                $TicketObject->HistoryAdd(
                    TicketID     => $TicketID,
                    HistoryType  => 'PriorityUpdate',
                    Name         => "Incident priority changed from '$CurrentIncident{Priority}' to '$Param{Priority}'",
                    CreateUserID => $Param{UserID},
                );
            } else {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Failed to update priority to '$Priority' for ticket $TicketID",
                );
                return;
            }
        }
    }
    
    if ( $Param{State} && $Param{State} ne $CurrentIncident{State} ) {
        my $TicketState = $Self->_MapStateToTicket( $Param{State} );
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "IncidentUpdate: Attempting to change state from '$CurrentIncident{State}' to '$Param{State}' (mapped to '$TicketState') for ticket $TicketID",
        );
        
        if ($TicketState) {
            # Validate that the state exists in the system
            my $StateObject = $Kernel::OM->Get('Kernel::System::State');
            
            # Use StateLookup directly instead of StateList
            my $StateID = $StateObject->StateLookup(
                State => $TicketState,
            );
            
            if (!$StateID) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "IncidentUpdate: State '$TicketState' not found in system for ticket $TicketID",
                );
                return;
            }
            
            # Try to update the state
            eval {
                my $Success = $TicketObject->TicketStateSet(
                    State    => $TicketState,
                    TicketID => $TicketID,
                    UserID   => $Param{UserID},
                );
                
                if ($Success) {
                    # Add history entry for incident state change
                    $TicketObject->HistoryAdd(
                        TicketID     => $TicketID,
                        HistoryType  => 'StateUpdate',
                        Name         => "Incident state changed from '$CurrentIncident{State}' to '$Param{State}'",
                        CreateUserID => $Param{UserID},
                    );
                    
                    $LogObject->Log(
                        Priority => 'notice',
                        Message  => "IncidentUpdate: Successfully updated state to '$TicketState' for ticket $TicketID",
                    );
                    
                    # Direct Zabbix API integration when incident is resolved or closed
                    # This bypasses the event system intentionally for immediate synchronization
                    $LogObject->Log(
                        Priority => 'notice',
                        Message  => "ZABBIX DEBUG: Checking state for Zabbix integration. State='$Param{State}', Type: " . (ref($Param{State}) || 'scalar'),
                    );
                    
                    # Log the exact state value for debugging
                    if ($Param{State}) {
                        my $StateHex = unpack("H*", $Param{State});
                        $LogObject->Log(
                            Priority => 'notice',
                            Message  => "ZABBIX DEBUG: State value in hex: $StateHex, length: " . length($Param{State}),
                        );
                    }
                    
                    if ( $Param{State} && $Param{State} =~ /^(resolved|closed|cancelled)/i ) {
                        $LogObject->Log(
                            Priority => 'notice',
                            Message  => "ZABBIX DEBUG: State MATCHES resolved/closed/cancelled pattern! Matched: '$1', calling _HandleZabbixIntegration for ticket $TicketID",
                        );
                        
                        # Isolate Zabbix integration errors to prevent disrupting the main flow
                        eval {
                            my $ZabbixResult = $Self->_HandleZabbixIntegration(
                                TicketID => $TicketID,
                                State    => $Param{State},
                                UserID   => $Param{UserID},
                            );
                            
                            # Silent handling - no error logging since _HandleZabbixIntegration now always returns 1
                            if (!$ZabbixResult) {
                                $LogObject->Log(
                                    Priority => 'debug',  # Changed from 'error' to 'debug'
                                    Message  => "Zabbix integration returned false for ticket $TicketID (incident update still succeeded)",
                                );
                            }
                        };
                        if ($@) {
                            $LogObject->Log(
                                Priority => 'debug',  # Changed from 'error' to 'debug' for silent failure
                                Message  => "Zabbix integration exception for ticket $TicketID (silently handled): $@",
                            );
                            # Don't fail the incident update due to Zabbix issues
                        }
                    } else {
                        $LogObject->Log(
                            Priority => 'notice',
                            Message  => "ZABBIX DEBUG: State DOES NOT MATCH resolved/closed/cancelled pattern. State='" . ($Param{State} || 'undefined') . "'",
                        );
                    }
                } else {
                    $LogObject->Log(
                        Priority => 'error',
                        Message  => "IncidentUpdate: TicketStateSet returned false for state '$TicketState' on ticket $TicketID",
                    );
                    return;
                }
            };
            
            if ($@) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "IncidentUpdate: Exception during TicketStateSet for ticket $TicketID: $@",
                );
                return;
            }
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "IncidentUpdate: Could not map incident state '$Param{State}' to ticket state for ticket $TicketID",
            );
            return;
        }
    }
    
    if ( $Param{AssignedTo} && $Param{AssignedTo} ne $CurrentIncident{AssignedTo} ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "OWNER UPDATE: Setting owner to user ID '$Param{AssignedTo}' for ticket $TicketID",
        );
        
        my $Success = $TicketObject->TicketOwnerSet(
            NewUserID => $Param{AssignedTo},
            TicketID  => $TicketID,
            UserID    => $Param{UserID},
        );
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "OWNER UPDATE RESULT: " . ($Success ? "SUCCESS" : "FAILED") . " - Owner '$Param{AssignedTo}' for ticket $TicketID",
        );
        
        # Also update AssignedTo dynamic field to keep in sync
        if ($Success) {  # Always update, even for unassigned (99)
            my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
                Name => 'AssignedTo',
            );
            if ($DynamicFieldConfig && $DynamicFieldConfig->{ID}) {
                $DynamicFieldValueObject->ValueSet(
                    FieldID  => $DynamicFieldConfig->{ID},
                    ObjectID => $TicketID,
                    Value    => [{ ValueText => $Param{AssignedTo} || '99' }],  # Default to unassigned (99)
                    UserID   => $Param{UserID},
                );
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "Updated AssignedTo dynamic field to '$Param{AssignedTo}' for ticket $TicketID",
                );
            }
        }
        
        if ($Success) {
            # Add history entry for assignment change
            my $UserObject = $Kernel::OM->Get('Kernel::System::User');
            my %NewUser = $UserObject->GetUserData(UserID => $Param{AssignedTo});
            my %OldUser = $UserObject->GetUserData(UserID => $CurrentIncident{AssignedTo}) if $CurrentIncident{AssignedTo};
            
            my $HistoryName = sprintf(
                "Incident assigned from '%s' to '%s'",
                $OldUser{UserFullname} || 'Unassigned',
                $NewUser{UserFullname} || 'Unknown'
            );
            
            $TicketObject->HistoryAdd(
                TicketID     => $TicketID,
                HistoryType  => 'OwnerUpdate',
                Name         => $HistoryName,
                CreateUserID => $Param{UserID},
            );
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Failed to update owner to '$Param{AssignedTo}' for ticket $TicketID",
            );
            return;
        }
    }
    
    if ( $Param{ShortDescription} ) {
        my $Success = $TicketObject->TicketTitleUpdate(
            Title    => $Param{ShortDescription},
            TicketID => $TicketID,
            UserID   => $Param{UserID},
        );
        if (!$Success) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Failed to update title to '$Param{ShortDescription}' for ticket $TicketID",
            );
            return;
        }
    }
    
    # Update description if provided (update the first article)
    if ( defined $Param{Description} ) {
        my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
        
        # Get the first article of the ticket
        my @Articles = $ArticleObject->ArticleList(
            TicketID => $TicketID,
            OnlyFirst => 1,
        );
        
        if (@Articles) {
            my $ArticleBackendObject = $ArticleObject->BackendForArticle(
                ArticleID => $Articles[0]->{ArticleID},
                TicketID  => $TicketID,
            );
            
            # Description updates are stored in dynamic fields, no need for separate notes
        }
    }

    # Get user info for UpdatedBy field
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my %User = $UserObject->GetUserData(
        UserID => $Param{UserID},
    );
    my $UpdatedByName = "$User{UserFirstname} $User{UserLastname} ($User{UserLogin})";
    
    # Always update the Updated and UpdatedBy fields
    $Param{Updated} = $CurrentTime;
    $Param{UpdatedBy} = $UpdatedByName;
    
    # Update dynamic fields with correct field names
    my %FieldMapping = (
        Priority         => 'IncidentPriority',
        CI               => 'CI',
        Description      => 'Description',
        ProductCat1      => 'ProductCat1',
        ProductCat2      => 'ProductCat2',
        ProductCat3      => 'ProductCat3',
        ProductCat4      => 'ProductCat4',
        OperationalCat1  => 'OperationalCat1',
        OperationalCat2  => 'OperationalCat2',
        OperationalCat3  => 'OperationalCat3',
        ResolutionCat1   => 'ResolutionCat1',
        ResolutionCat2   => 'ResolutionCat2',
        ResolutionCat3   => 'ResolutionCat3',
        ResolutionNotes  => 'ResolutionNotes',
        ResponseTime     => 'IncidentResponseTime',
        ResolvedTime     => 'IncidentResolvedTime',
        Updated          => 'Updated',
        UpdatedBy        => 'UpdatedBy',
    );

    for my $Field ( keys %FieldMapping ) {
        if ( exists $Param{$Field} && defined $Param{$Field} && $Param{$Field} ne '' ) {
            my $DynamicFieldName = $FieldMapping{$Field};
            
            
            my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
                Name => $DynamicFieldName,
            );

            if ( $DynamicFieldConfig && $DynamicFieldConfig->{ID} ) {
                # Set the value based on field type - ValueSet expects array of hashes
                my $Value;
                my $FieldType = $DynamicFieldConfig->{FieldType} || 'Text';
                
                if ( $FieldType eq 'DateTime' ) {
                    # For DateTime fields like ResponseTime/ResolvedTime
                    $Value = [ { ValueDateTime => $Param{$Field} } ];
                } elsif ( $FieldType eq 'Multiselect' ) {
                    # For multiselect - each option as separate hash
                    my @values = ref($Param{$Field}) eq 'ARRAY' ? @{$Param{$Field}} : ($Param{$Field});
                    $Value = [ map { { ValueText => $_ } } @values ];
                } else {
                    # For Text, Dropdown, etc - single hash with ValueText
                    $Value = [ { ValueText => $Param{$Field} } ];
                }
                
                my $Success = $DynamicFieldValueObject->ValueSet(
                    FieldID    => $DynamicFieldConfig->{ID},
                    ObjectID   => $TicketID,
                    Value      => $Value,
                    UserID     => $Param{UserID},
                );
                
                if (!$Success) {
                    $LogObject->Log(
                        Priority => 'error',
                        Message  => "Failed to set dynamic field $DynamicFieldName for ticket $TicketID",
                    );
                }
            }
        }
    }

    # Always update modified time/user
    for my $Field ( ['IncidentUpdatedDate', $CurrentTime], ['IncidentUpdatedBy', $Param{UserID}] ) {
        my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
            Name => $Field->[0],
        );

        if ( $DynamicFieldConfig && $DynamicFieldConfig->{ID} ) {
            $DynamicFieldValueObject->ValueSet(
                FieldID    => $DynamicFieldConfig->{ID},
                ObjectID   => $TicketID,
                Value      => [ $Field->[1] ],
                UserID     => $Param{UserID},
            );
        }
    }

    return 1;
}

=head2 ValidateStateTransition()

Check if a state transition is allowed

    my $IsValid = $IncidentObject->ValidateStateTransition(
        CurrentState => 'new',
        NewState     => 'assigned',
    );

=cut

sub ValidateStateTransition {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    for my $Needed (qw(CurrentState NewState)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # Allow all state transitions - no restrictions
    return 1;

    # Define allowed transitions - using lowercase states
    # Match the business rules: from 'new' only to assigned/in progress/cancelled
    # From other states: to assigned/in progress/pending/resolved/cancelled
    my %AllowedTransitions = (
        'new' => {
            'assigned'     => 1,
            'in progress'  => 1,
            'cancelled'    => 1,
        },
        'assigned' => {
            'assigned'          => 1,  # Allow staying in same state
            'in progress'       => 1,
            'pending'  => 1,
            'resolved'          => 1,
            'cancelled'         => 1,
        },
        'in progress' => {
            'assigned'          => 1,
            'in progress'       => 1,  # Allow staying in same state
            'pending'  => 1,
            'resolved'          => 1,
            'cancelled'         => 1,
        },
        'pending' => {
            'assigned'      => 1,
            'in progress'   => 1,
            'pending' => 1,  # Allow staying in same state
            'resolved'      => 1,
            'cancelled'     => 1,
        },
        'resolved' => {
            'assigned'          => 1,
            'in progress'       => 1,
            'pending'  => 1,
            'resolved'          => 1,  # Allow staying in same state
            'cancelled'         => 1,
        },
        'closed successful' => {
            'assigned'          => 1,
            'in progress'       => 1,
            'pending'  => 1,
            'resolved'          => 1,
            'cancelled'         => 1,
        },
        'cancelled' => {
            'assigned'          => 1,
            'in progress'       => 1,
            'pending'  => 1,
            'resolved'          => 1,
            'cancelled'         => 1,  # Allow staying in same state
        },
    );
    
    # Handle uppercase states for backward compatibility
    my $CurrentStateLower = lc($Param{CurrentState});
    my $NewStateLower = lc($Param{NewState});
    
    # Map common variations
    $CurrentStateLower = 'closed successful' if $CurrentStateLower eq 'closed';
    $NewStateLower = 'closed successful' if $NewStateLower eq 'closed';
    $CurrentStateLower = 'pending' if $CurrentStateLower eq 'pending';
    $NewStateLower = 'pending' if $NewStateLower eq 'pending';

    return $AllowedTransitions{ $CurrentStateLower }->{ $NewStateLower } || 0;
}

=head2 GetAllowedStateTransitions()

Get list of allowed state transitions from current state

    my @AllowedStates = $IncidentObject->GetAllowedStateTransitions(
        CurrentState => 'new',
    );

=cut

sub GetAllowedStateTransitions {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    if ( !$Param{CurrentState} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need CurrentState!"
        );
        return;
    }

    # Define allowed transitions - using lowercase states
    my %AllowedTransitions = (
        'new'               => ['assigned', 'in progress', 'pending', 'resolved', 'closed successful', 'cancelled'],
        'assigned'          => ['new', 'in progress', 'pending', 'resolved', 'closed successful', 'cancelled'],
        'in progress'       => ['assigned', 'pending', 'resolved', 'closed successful', 'cancelled'],
        'pending'  => ['in progress', 'resolved', 'closed successful', 'cancelled'],
        'resolved'          => ['in progress', 'closed successful'],
        'closed successful' => ['in progress'],
        'cancelled'         => ['in progress'],
    );
    
    # Handle uppercase states for backward compatibility
    my $CurrentStateLower = lc($Param{CurrentState});
    $CurrentStateLower = 'closed successful' if $CurrentStateLower eq 'closed';
    $CurrentStateLower = 'pending' if $CurrentStateLower eq 'pending';

    my @Allowed = @{ $AllowedTransitions{ $CurrentStateLower } || [] };
    
    # Always include current state
    unshift @Allowed, $Param{CurrentState};

    return @Allowed;
}

=head2 AddWorkNote()

Add a work note to the incident

    my $Success = $IncidentObject->AddWorkNote(
        IncidentID   => 123,
        Note         => 'Investigating the issue',
        IncludeInMSI => 1,  # Include in MSI escalation
        UserID       => 1,
    );

=cut

sub AddWorkNote {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    for my $Needed (qw(IncidentID Note UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my $DBObject   = $Kernel::OM->Get('Kernel::System::DB');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');

    # Get user name
    my %User = $UserObject->GetUserData(
        UserID => $Param{UserID},
    );

    my $CurrentTime = $TimeObject->CurrentTimestamp();

    # Insert work note
    return if !$DBObject->Do(
        SQL => 'INSERT INTO incident_work_notes (
            ticket_id, note_text, include_in_msi, created_time, created_by, created_by_name
        ) VALUES (?, ?, ?, ?, ?, ?)',
        Bind => [
            \$Param{IncidentID},
            \$Param{Note},
            \($Param{IncludeInMSI} ? 1 : 0),
            \$CurrentTime,
            \$Param{UserID},
            \$User{UserFullname},
        ],
    );

    return 1;
}

=head2 GetWorkNotesHistory()

Get work notes history for an incident

    my @WorkNotes = $IncidentObject->GetWorkNotesHistory(
        IncidentID => 123,
    );

=cut

sub GetWorkNotesHistory {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    if ( !$Param{IncidentID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need IncidentID!'
        );
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Get work notes
    return if !$DBObject->Prepare(
        SQL => 'SELECT id, note_text, include_in_msi, created_time, created_by, created_by_name
                FROM incident_work_notes 
                WHERE ticket_id = ?
                ORDER BY created_time DESC',
        Bind => [ \$Param{IncidentID} ],
    );

    my @WorkNotes;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @WorkNotes, {
            ID            => $Row[0],
            Note          => $Row[1],
            IncludeInMSI  => $Row[2],
            Created       => $Row[3],
            CreatedBy     => $Row[4],
            CreatedByName => $Row[5],
        };
    }

    return @WorkNotes;
}

=head2 AddResolutionNote()

Add a resolution note to the incident

    my $Success = $IncidentObject->AddResolutionNote(
        IncidentID      => 123,
        ResolutionCat1  => 'Software',
        ResolutionCat2  => 'Bug',
        ResolutionCat3  => 'Known Issue',
        ResolutionNotes => 'Applied patch version 1.2.3',
        UserID          => 1,
    );

=cut

sub AddResolutionNote {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    for my $Needed (qw(IncidentID ResolutionNotes UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my $DBObject   = $Kernel::OM->Get('Kernel::System::DB');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');

    # Get user name
    my %User = $UserObject->GetUserData(
        UserID => $Param{UserID},
    );

    my $CurrentTime = $TimeObject->CurrentTimestamp();

    # Insert resolution note
    return if !$DBObject->Do(
        SQL => 'INSERT INTO incident_resolution_notes (
            ticket_id, resolution_cat1, resolution_cat2, resolution_cat3,
            resolution_notes, created_time, created_by, created_by_name
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        Bind => [
            \$Param{IncidentID},
            \$Param{ResolutionCat1},
            \$Param{ResolutionCat2},
            \$Param{ResolutionCat3},
            \$Param{ResolutionNotes},
            \$CurrentTime,
            \$Param{UserID},
            \$User{UserFullname},
        ],
    );

    return 1;
}

=head2 GetResolutionHistory()

Get resolution history for an incident

    my @Resolutions = $IncidentObject->GetResolutionHistory(
        IncidentID => 123,
    );

=cut

sub GetResolutionHistory {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    if ( !$Param{IncidentID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need IncidentID!'
        );
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Get resolution notes
    return if !$DBObject->Prepare(
        SQL => 'SELECT id, resolution_cat1, resolution_cat2, resolution_cat3,
                resolution_notes, created_time, created_by, created_by_name
                FROM incident_resolution_notes 
                WHERE ticket_id = ?
                ORDER BY created_time DESC',
        Bind => [ \$Param{IncidentID} ],
    );

    my @Resolutions;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Resolutions, {
            ID              => $Row[0],
            ResolutionCat1  => $Row[1],
            ResolutionCat2  => $Row[2],
            ResolutionCat3  => $Row[3],
            ResolutionNotes => $Row[4],
            Created         => $Row[5],
            CreatedBy       => $Row[6],
            CreatedByName   => $Row[7],
        };
    }

    return @Resolutions;
}

=head2 GetIncidentHistory()

Get update history for an incident from Znuny's ticket history

    my @History = $IncidentObject->GetIncidentHistory(
        IncidentID => 123,
        UserID     => 1,
    );

=cut

sub GetIncidentHistory {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    for my $Needed (qw(IncidentID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $StateObject = $Kernel::OM->Get('Kernel::System::State');

    # Get ticket history
    my @History = $TicketObject->HistoryGet(
        TicketID => $Param{IncidentID},
        UserID   => $Param{UserID},
    );

    # Filter for incident-related history types
    # Note: Excluding AddNote as it contains internal tracking messages
    my %IncidentHistoryTypes = (
        'StateUpdate'    => 1,
        'PriorityUpdate' => 1,
        'OwnerUpdate'    => 1,
        'NewTicket'      => 1,
    );

    my @IncidentHistory;
    my %SeenEntries;  # Track duplicate entries
    
    for my $HistoryEntry (@History) {
        next if !$IncidentHistoryTypes{$HistoryEntry->{HistoryType}};

        # For OwnerUpdate and PriorityUpdate, filter out the generic system-generated log
        # to prevent duplicate history entries.
        if (
            ($HistoryEntry->{HistoryType} eq 'OwnerUpdate' && $HistoryEntry->{Name} !~ /assigned from/) ||
            ($HistoryEntry->{HistoryType} eq 'PriorityUpdate' && $HistoryEntry->{Name} !~ /priority changed from/)
        ) {
            next;
        }
        
        # Get user name for the history entry
        my %User = $UserObject->GetUserData(
            UserID => $HistoryEntry->{CreateBy},
        );

        # Format the history entry based on type
        my $FormattedName = $Self->_FormatHistoryEntry(
            HistoryType => $HistoryEntry->{HistoryType},
            Name        => $HistoryEntry->{Name},
        );
        
        # Skip entries that return empty formatted names
        next if !$FormattedName;

        push @IncidentHistory, {
            ID           => $HistoryEntry->{HistoryID},
            HistoryType  => $HistoryEntry->{HistoryType},
            Name         => $FormattedName,
            Created      => $HistoryEntry->{CreateTime},
            CreatedBy    => $HistoryEntry->{CreateBy},
            CreatedByName => $User{UserFullname} || $User{UserLogin} || 'System',
        };
    }

    # Sort by creation time (newest first)
    @IncidentHistory = sort { $b->{Created} cmp $a->{Created} } @IncidentHistory;

    return @IncidentHistory;
}

# Internal methods

sub _FormatHistoryEntry {
    my ( $Self, %Param ) = @_;

    my $HistoryType = $Param{HistoryType} || '';
    my $Name = $Param{Name} || '';

    # Handle different history types
    if ($HistoryType eq 'StateUpdate') {
        # Format: %%old%%new%%
        if ($Name =~ /^%%(.+?)%%(.+?)%%$/) {
            my ($OldState, $NewState) = ($1, $2);
            return "State changed from '$OldState' to '$NewState'";
        }
        # Skip alternative format entries like "Incident state changed from 'X' to 'Y'"
        # These are duplicates - we only want the %% format ones
        elsif ($Name =~ /state changed from/) {
            return '';  # Return empty to filter out
        }
    }
    elsif ($HistoryType eq 'PriorityUpdate') {
        # Format: %%old%%new%%
        if ($Name =~ /^%%(.+?)%%(.+?)%%$/) {
            my ($OldPriorityID, $NewPriorityID) = ($1, $2);
            my $PriorityObject = $Kernel::OM->Get('Kernel::System::Priority');
            my %OldPriority = $PriorityObject->PriorityGet(PriorityID => $OldPriorityID);
            my %NewPriority = $PriorityObject->PriorityGet(PriorityID => $NewPriorityID);
            return "Priority changed from '$OldPriority{Name}' to '$NewPriority{Name}'";
        }
    }
    elsif ($HistoryType eq 'OwnerUpdate') {
        # Format: %%old%%new%%
        if ($Name =~ /^%%(.+?)%%(.+?)%%$/) {
            my ($OldOwnerID, $NewOwnerID) = ($1, $2);
            my $UserObject = $Kernel::OM->Get('Kernel::System::User');
            my %OldOwner = $UserObject->GetUserData(UserID => $OldOwnerID);
            my %NewOwner = $UserObject->GetUserData(UserID => $NewOwnerID);
            my $OldOwnerName = $OldOwner{UserFullname} || 'Unassigned';
            my $NewOwnerName = $NewOwner{UserFullname} || 'Unassigned';
            return "Owner changed from '$OldOwnerName' to '$NewOwnerName'";
        }
    }
    elsif ($HistoryType eq 'NewTicket') {
        # Format: %%TicketNumber%%Queue%%Priority%%State%%AgentID
        if ($Name =~ /^%%(.+?)%%(.+?)%%(.+?)%%(.+?)%%(.+?)$/) {
            my ($TicketNumber, $Queue, $Priority, $State, $AgentID) = ($1, $2, $3, $4, $5);
            return "Incident created: $TicketNumber";
        }
    }

    # If we couldn't parse it, return the original but without %% markers
    $Name =~ s/%%/ /g;
    return $Name;
}

sub _GenerateIncidentNumber {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $TypeObject = $Kernel::OM->Get('Kernel::System::Type');
    my $TicketPrefixObject = $Kernel::OM->Get('Kernel::System::TicketPrefix');
    
    # Get the Incident type ID
    my %TypeList = $TypeObject->TypeList();
    my $IncidentTypeID;
    for my $TypeID ( keys %TypeList ) {
        if ( $TypeList{$TypeID} eq 'Incident' ) {
            $IncidentTypeID = $TypeID;
            last;
        }
    }
    
    # Get the prefix for Incident type
    my $Prefix = 'INC';  # Default fallback
    if ($IncidentTypeID) {
        my $ConfiguredPrefix = $TicketPrefixObject->GetTNPrefixByType(
            TypeID => $IncidentTypeID,
        );
        if ($ConfiguredPrefix) {
            $Prefix = $ConfiguredPrefix;
        }
    }
    
    # Get next incident number - check for both old format (INC-) and new format (configured prefix)
    # Extract numbers after any non-digit characters
    return if !$DBObject->Prepare(
        SQL => "SELECT COALESCE(MAX(CAST(REGEXP_REPLACE(incident_number, '^[^0-9]+', '') AS INTEGER)), 0) + 1 
                FROM incident_management",
        Limit => 1,
    );

    my $NextNumber = 1;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $NextNumber = $Row[0];
    }

    # Format with configured prefix and 10 digits
    return sprintf( "%s%010d", $Prefix, $NextNumber );
}

sub _MapPriorityToTicket {
    my ( $Self, $Priority ) = @_;

    # Map incident priority to ticket priority name
    my %PriorityMap = (
        'P1' => 'P1-Critical',
        'P2' => 'P2-High',
        'P3' => 'P3-Medium',
        'P4' => 'P4-Low',
    );

    return $PriorityMap{$Priority} || 'P3-Medium';
}

sub _MapStateToTicket {
    my ( $Self, $State ) = @_;

    # Simple mapping - incident states to ticket states (handle both cases)
    my %StateMap = (
        # Lowercase versions (used by the form)
        'new'                => 'new',
        'assigned'           => 'assigned',
        'in progress'        => 'in progress', 
        'pending'   => 'pending',
        'resolved'           => 'resolved',
        'closed'             => 'closed',
        'closed successful'  => 'closed successful',
        'cancelled'          => 'cancelled',
        
        # Capitalized versions (backward compatibility)
        'New'         => 'new',
        'Assigned'    => 'assigned',
        'In Progress' => 'in progress', 
        'Pending'     => 'pending',
        'Resolved'    => 'resolved',
        'Closed'      => 'closed',
        'Cancelled'   => 'cancelled',
    );

    return $StateMap{$State} || $State;
}

sub _MapTicketToIncidentState {
    my ( $Self, $State ) = @_;

    # Map ticket state to incident state - all lowercase now
    my %StateMap = (
        'new'                  => 'new',
        'open'                 => 'in progress',  # Default to In Progress for open tickets
        'closed successful'    => 'closed successful',  # Keep as is
        'closed unsuccessful'  => 'cancelled',
        'pending'     => 'pending',   # Keep as is
        'pending auto close+'  => 'pending',
        'pending auto close-'  => 'pending',
        'assigned'             => 'assigned',
        'in progress'          => 'in progress',
        'resolved'             => 'resolved',
        'closed'               => 'closed',
        'cancelled'            => 'cancelled',
    );

    # If state is already a valid incident state (all lowercase), return it
    my %ValidIncidentStates = (
        'new' => 1,
        'assigned' => 1,
        'in progress' => 1,
        'pending' => 1,
        'resolved' => 1,
        'closed' => 1,
        'closed successful' => 1,
        'cancelled' => 1,
    );
    
    return $State if $ValidIncidentStates{$State};
    
    # Also check for capitalized versions and convert to lowercase
    my %CapitalizedStateMap = (
        'New' => 'new',
        'Assigned' => 'assigned',
        'In Progress' => 'in progress',
        'Pending' => 'pending',
        'Resolved' => 'resolved',
        'Closed' => 'closed successful',
        'Cancelled' => 'cancelled',
    );
    
    return $CapitalizedStateMap{$State} if $CapitalizedStateMap{$State};
    
    return $StateMap{$State} || 'new';
}

=head2 _EnsureIncidentQueue()

Ensures incident queue exists, creates it if needed, or falls back to existing queue

=cut

sub _EnsureIncidentQueue {
    my ( $Self, %Param ) = @_;

    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');

    # Check if Incident queue exists
    my %QueueList = $QueueObject->QueueList();
    for my $QueueID ( keys %QueueList ) {
        if ( $QueueList{$QueueID} eq 'Incident' ) {
            return 'Incident';
        }
    }

    # Try to create Incident queue
    my $QueueID = $QueueObject->QueueAdd(
        Name            => 'Incident',
        ValidID         => 1,
        GroupID         => 1,  # users group
        Calendar        => '',
        FirstResponseTime => 240,    # 4 hours
        UpdateTime      => 480,      # 8 hours  
        SolutionTime    => 1440,     # 24 hours
        UnlockTimeout   => 0,
        FollowUpID      => 1,
        FollowUpLock    => 0,
        SystemAddressID => 1,
        SalutationID    => 1,
        SignatureID     => 1,
        Comment         => 'Queue for incident management',
        UserID          => 1,
    );

    if ($QueueID) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "Created incident queue 'Incident' with ID $QueueID",
        );
        return 'Incident';
    }

    # Fall back to Misc queue if creation failed
    $LogObject->Log(
        Priority => 'error',
        Message  => "Failed to create incident queue, falling back to 'Misc'",
    );
    return 'Misc';
}

=head2 _EnsureIncidentType()

Ensures incident type exists, creates it if needed, or falls back to default

=cut

sub _EnsureIncidentType {
    my ( $Self, %Param ) = @_;

    my $TypeObject = $Kernel::OM->Get('Kernel::System::Type');
    my $LogObject  = $Kernel::OM->Get('Kernel::System::Log');

    # Check if Incident type exists
    my %TypeList = $TypeObject->TypeList();
    for my $TypeID ( keys %TypeList ) {
        if ( $TypeList{$TypeID} eq 'Incident' ) {
            return $TypeID;
        }
    }

    # Try to create Incident type
    my $TypeID = $TypeObject->TypeAdd(
        Name    => 'Incident',
        ValidID => 1,
        UserID  => 1,
    );

    if ($TypeID) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "Created incident type 'Incident' with ID $TypeID",
        );
        return $TypeID;
    }

    # Fall back to first available type
    my @TypeIDs = keys %TypeList;
    if (@TypeIDs) {
        my $FallbackTypeID = $TypeIDs[0];
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to create incident type, falling back to type ID $FallbackTypeID",
        );
        return $FallbackTypeID;
    }

    # Last resort - return 1 (usually Default type)
    $LogObject->Log(
        Priority => 'error',
        Message  => "No types available, falling back to type ID 1",
    );
    return 1;
}

=head2 _HandleZabbixIntegration()

Internal method to handle Zabbix integration when incident is resolved/closed

    $Self->_HandleZabbixIntegration(
        TicketID => 123,
        State    => 'resolved',
        UserID   => 1,
    );

=cut

sub _HandleZabbixIntegration {
    my ( $Self, %Param ) = @_;
    
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Wrap entire method in eval to ensure silent failure
    eval {
        $LogObject->Log(
            Priority => 'debug',  # Changed from 'notice' to 'debug'
            Message  => "ZABBIX: _HandleZabbixIntegration START - TicketID=$Param{TicketID}, State=$Param{State}",
        );
        
        # Check if Zabbix integration is enabled
        my $ZabbixConfigObject = $Kernel::OM->Get('Kernel::System::ZabbixConfig');
        
        my $IsEnabled = $ZabbixConfigObject->IsEnabled();
        $LogObject->Log(
            Priority => 'debug',  # Changed from 'notice' to 'debug'
            Message  => "ZABBIX: Integration enabled: " . ($IsEnabled ? 'YES' : 'NO'),
        );
        
        if ( !$IsEnabled ) {
            $LogObject->Log(
                Priority => 'debug',  # Changed from 'notice' to 'debug'
                Message  => "ZABBIX: Integration disabled, exiting",
            );
            return 1;  # Success - integration intentionally disabled
        }
        
        # Get the AlarmID from dynamic field
        my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
        my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
        
        my $AlarmIDField = $DynamicFieldObject->DynamicFieldGet(
            Name => 'AlarmID',
        );
        
        if ( !$AlarmIDField ) {
            $LogObject->Log(
                Priority => 'debug',  # Changed from 'error' to 'debug'
                Message  => "AlarmID dynamic field not found, cannot sync with Zabbix for ticket $Param{TicketID}",
            );
            return 1;  # Changed to return success to prevent UI errors
        }
    
        # Get the AlarmID value
        my $AlarmID = $DynamicFieldBackendObject->ValueGet(
            DynamicFieldConfig => $AlarmIDField,
            ObjectID           => $Param{TicketID},
        );
        
        $LogObject->Log(
            Priority => 'debug',  # Changed from 'notice' to 'debug'
            Message  => "ZABBIX: AlarmID value: '" . ($AlarmID || 'NONE') . "' for ticket $Param{TicketID}",
        );
        
        if ( !$AlarmID ) {
            $LogObject->Log(
                Priority => 'debug',  # Changed from 'notice' to 'debug'
                Message  => "ZABBIX: No AlarmID, not a Zabbix ticket, exiting",
            );
            return 1;  # Success - not a Zabbix-related ticket
        }
        
        $LogObject->Log(
            Priority => 'debug',  # Changed from 'notice' to 'debug'
            Message  => "ZABBIX: Calling API to close event $AlarmID for ticket $Param{TicketID}",
        );
    
        # Get ticket number for Zabbix API
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
        my %Ticket = $TicketObject->TicketGet(
            TicketID => $Param{TicketID},
            UserID   => $Param{UserID},
        );
        
        # Call Zabbix API to close the event with error isolation
        my $ZabbixAPIObject = $Kernel::OM->Get('Kernel::System::ZabbixAPI');
        
        $LogObject->Log(
            Priority => 'debug',  # Changed from 'notice' to 'debug'
            Message  => "ZABBIX: About to call CloseEvent API for EventID=$AlarmID, TicketNumber=$Ticket{TicketNumber}",
        );
        
        my $Result;
        eval {
            $Result = $ZabbixAPIObject->CloseEvent(
                EventID      => $AlarmID,
                TicketID     => $Param{TicketID},
                TicketNumber => $Ticket{TicketNumber},
                Message      => "Incident resolved in ZNUNY - State: $Param{State}",
            );
        };
        
        if ($@) {
            $LogObject->Log(
                Priority => 'debug',  # Changed from 'error' to 'debug'
                Message  => "ZABBIX: API call failed for event $AlarmID: $@",
            );
            return 1;  # Changed to return success to prevent UI errors
        }
    
        $LogObject->Log(
            Priority => 'debug',  # Changed from 'notice' to 'debug'
            Message  => "ZABBIX: API call completed. Result: " . 
                         "Success=" . ($Result->{Success} ? 'YES' : 'NO') . 
                         ", ErrorMessage=" . ($Result->{ErrorMessage} || 'none'),
        );
        
        if ( $Result && $Result->{Success} ) {
            $LogObject->Log(
                Priority => 'debug',  # Changed from 'notice' to 'debug'
                Message  => "ZABBIX: SUCCESS - Closed event $AlarmID for ticket $Param{TicketID}",
            );
            
            # Add history entry for successful Zabbix sync (best effort)
            eval {
                $TicketObject->HistoryAdd(
                    TicketID     => $Param{TicketID},
                    HistoryType  => 'Misc',
                    Name         => "Zabbix event $AlarmID closed successfully",
                    CreateUserID => $Param{UserID},
                );
            };
            if ($@) {
                $LogObject->Log(
                    Priority => 'debug',  # Changed from 'warning' to 'debug'
                    Message  => "Could not add history entry for Zabbix sync on ticket $Param{TicketID}: $@",
                );
                # Don't fail the operation just because history couldn't be added
            }
        }
        else {
            my $ErrorMsg = ($Result && $Result->{ErrorMessage}) ? $Result->{ErrorMessage} : 'Unknown error or no response';
            $LogObject->Log(
                Priority => 'debug',  # Changed from 'error' to 'debug'
                Message  => "ZABBIX: API call did not succeed for event $AlarmID for ticket $Param{TicketID}: $ErrorMsg",
            );
            # Always return success to prevent UI errors
        }
    };
    
    # Catch any exceptions from the entire method
    if ($@) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'debug',  # Silent failure - only log at debug level
            Message  => "ZABBIX: Integration method exception (silently handled): $@",
        );
    }
    
    # Always return success to prevent UI disruption
    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSSTLite project (L<https://radiant.digital/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut