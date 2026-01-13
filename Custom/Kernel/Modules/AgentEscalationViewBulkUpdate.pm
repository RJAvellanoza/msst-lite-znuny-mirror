# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentEscalationViewBulkUpdate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::Modules::AgentEscalationViewBulkUpdate - AJAX handler for bulk updating eBonded incidents

=head1 DESCRIPTION

Handles AJAX requests to update individual eBonded incidents via ServiceNow integration.
Implements 10-minute cooldown per ticket and 24-hour automatic cleanup.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Get required objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # Validate session (this is critical for security)
    if ( !$Self->{SessionID} ) {
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=UTF-8',
            Content     => '{"success":false,"message":"Invalid session","updated":false}',
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Get ticket ID parameter
    my $TicketID = $ParamObject->GetParam( Param => 'TicketID' );

    if ( !$TicketID ) {
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=UTF-8',
            Content     => '{"success":false,"message":"Missing TicketID parameter","updated":false}',
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Cleanup old records (older than 24 hours) - PostgreSQL syntax
    $DBObject->Do(
        SQL => "DELETE FROM bulk_update_cooldown WHERE create_time < NOW() - INTERVAL '24 hours'",
    );

    # Check if ticket exists and user has permission
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $TicketID,
        UserID        => $Self->{UserID},
        DynamicFields => 0,
    );

    if ( !%Ticket ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentEscalationViewBulkUpdate: Ticket $TicketID not found or no permission for user $Self->{UserID}",
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=UTF-8',
            Content     => '{"success":false,"message":"Ticket not found or no permission","updated":false}',
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Check cooldown - PostgreSQL syntax
    my $InCooldown = 0;
    return if !$DBObject->Prepare(
        SQL   => "SELECT COUNT(*) FROM bulk_update_cooldown WHERE ticket_id = ? AND cooldown_until > NOW()",
        Bind  => [ \$TicketID ],
        Limit => 1,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $InCooldown = $Row[0];
    }

    if ( $InCooldown ) {
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=UTF-8',
            Content     => '{"success":false,"message":"Ticket in cooldown","updated":false}',
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Call EBonding API to pull updates
    my $EBondingObject = $Kernel::OM->Get('Kernel::System::EBonding');
    my ( $Success, $UpdateSummary, $ErrorMessage ) = $EBondingObject->PullFromServiceNow(
        IncidentID => $TicketID,
        UserID     => $Self->{UserID},
    );

    # Prepare ticket details for response
    my $TicketNumber = $Ticket{TicketNumber} || '';
    my $Title = $Ticket{Title} || '';
    $Title =~ s/"/\\"/g;  # Escape quotes for JSON

    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');
    my $JSONResponse;

    if ( $Success ) {
        # Set cooldown - PostgreSQL ON CONFLICT syntax
        my $CooldownSet = $DBObject->Do(
            SQL => "INSERT INTO bulk_update_cooldown (ticket_id, cooldown_until, create_time, update_time)
                    VALUES (?, NOW() + INTERVAL '10 minutes', NOW(), NOW())
                    ON CONFLICT (ticket_id)
                    DO UPDATE SET
                        cooldown_until = NOW() + INTERVAL '10 minutes',
                        update_time = NOW()",
            Bind => [ \$TicketID ],
        );

        if ( !$CooldownSet ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "AgentEscalationViewBulkUpdate: Failed to set cooldown for ticket $TicketID",
            );
        }

        my $Message = $UpdateSummary || 'Update successful';

        my %ResponseData = (
            success      => \1,  # JSON true
            updated      => \1,  # JSON true
            message      => $Message,
            ticketNumber => $TicketNumber,
            ticketTitle  => $Title,
            ticketID     => $TicketID,
        );
        $JSONResponse = $JSONObject->Encode( Data => \%ResponseData );

        $LogObject->Log(
            Priority => 'info',
            Message  => "AgentEscalationViewBulkUpdate: Successfully updated ticket $TicketID. $Message",
        );
    }
    else {
        # Update failed
        my $Message = $ErrorMessage || 'Update failed';

        my %ResponseData = (
            success      => \0,  # JSON false
            updated      => \0,  # JSON false
            message      => $Message,
            ticketNumber => $TicketNumber,
            ticketTitle  => $Title,
            ticketID     => $TicketID,
        );
        $JSONResponse = $JSONObject->Encode( Data => \%ResponseData );

        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentEscalationViewBulkUpdate: Failed to update ticket $TicketID. $Message",
        );

        # Error is already stored in MSIEbondAPIResponse dynamic field by EBonding module
    }

    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=UTF-8',
        Content     => $JSONResponse,
        Type        => 'inline',
        NoCache     => 1,
    );
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST Lite project.

This software comes with ABSOLUTELY NO WARRANTY.

=cut
