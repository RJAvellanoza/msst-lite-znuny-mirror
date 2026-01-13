# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentEscalationViewUnlinkTickets;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::Modules::AgentEscalationViewUnlinkTickets - AJAX handler for unlinking tickets from ServiceNow

=head1 DESCRIPTION

Handles AJAX requests to unlink tickets from ServiceNow by clearing MSI dynamic fields.
Used when bulk update fails because tickets no longer exist in ServiceNow.

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
    my $LayoutObject       = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject        = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LogObject          = $Kernel::OM->Get('Kernel::System::Log');
    my $TicketObject       = $Kernel::OM->Get('Kernel::System::Ticket');
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $BackendObject      = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $JSONObject         = $Kernel::OM->Get('Kernel::System::JSON');

    # Validate session (this is critical for security)
    if ( !$Self->{SessionID} ) {
        my %ResponseData = (
            success => \0,
            message => 'Invalid session',
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=UTF-8',
            Content     => $JSONObject->Encode( Data => \%ResponseData ),
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Get ticket IDs parameter (comma-separated)
    my $TicketIDsParam = $ParamObject->GetParam( Param => 'TicketIDs' );

    if ( !$TicketIDsParam ) {
        my %ResponseData = (
            success => \0,
            message => 'Missing TicketIDs parameter',
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=UTF-8',
            Content     => $JSONObject->Encode( Data => \%ResponseData ),
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Parse ticket IDs
    my @TicketIDs = split /,/, $TicketIDsParam;

    # Get MSI dynamic field configurations
    my $MSITicketNumberField = $DynamicFieldObject->DynamicFieldGet(
        Name => 'MSITicketNumber',
    );
    my $MSITicketURLField = $DynamicFieldObject->DynamicFieldGet(
        Name => 'MSITicketURL',
    );
    my $MSITicketSysIDField = $DynamicFieldObject->DynamicFieldGet(
        Name => 'MSITicketSysID',
    );
    my $MSIEbondAPIResponseField = $DynamicFieldObject->DynamicFieldGet(
        Name => 'MSIEbondAPIResponse',
    );

    if ( !$MSITicketNumberField || !$MSITicketURLField || !$MSITicketSysIDField ) {
        my %ResponseData = (
            success => \0,
            message => 'MSI dynamic fields not found',
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=UTF-8',
            Content     => $JSONObject->Encode( Data => \%ResponseData ),
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Process each ticket
    my $UnlinkedCount = 0;
    my @Errors;

    for my $TicketID (@TicketIDs) {
        # Validate ticket exists and user has permission
        my %Ticket = $TicketObject->TicketGet(
            TicketID      => $TicketID,
            UserID        => $Self->{UserID},
            DynamicFields => 0,
        );

        if ( !%Ticket ) {
            push @Errors, "Ticket $TicketID not found or no permission";
            next;
        }

        # Clear MSI dynamic fields
        my $Success = 1;

        # Clear MSITicketNumber
        $Success = $BackendObject->ValueSet(
            DynamicFieldConfig => $MSITicketNumberField,
            ObjectID           => $TicketID,
            Value              => '',
            UserID             => $Self->{UserID},
        ) && $Success;

        # Clear MSITicketURL
        $Success = $BackendObject->ValueSet(
            DynamicFieldConfig => $MSITicketURLField,
            ObjectID           => $TicketID,
            Value              => '',
            UserID             => $Self->{UserID},
        ) && $Success;

        # Clear MSITicketSysID
        $Success = $BackendObject->ValueSet(
            DynamicFieldConfig => $MSITicketSysIDField,
            ObjectID           => $TicketID,
            Value              => '',
            UserID             => $Self->{UserID},
        ) && $Success;

        # Clear MSIEbondAPIResponse if it exists
        if ($MSIEbondAPIResponseField) {
            $BackendObject->ValueSet(
                DynamicFieldConfig => $MSIEbondAPIResponseField,
                ObjectID           => $TicketID,
                Value              => '',
                UserID             => $Self->{UserID},
            );
        }

        if ($Success) {
            $UnlinkedCount++;
            $LogObject->Log(
                Priority => 'notice',
                Message  => "AgentEscalationViewUnlinkTickets: Unlinked ticket $TicketID ($Ticket{TicketNumber}) from ServiceNow",
            );
        }
        else {
            push @Errors, "Failed to unlink ticket $Ticket{TicketNumber}";
            $LogObject->Log(
                Priority => 'error',
                Message  => "AgentEscalationViewUnlinkTickets: Failed to unlink ticket $TicketID",
            );
        }
    }

    # Build response
    my %ResponseData;
    if ( $UnlinkedCount > 0 ) {
        %ResponseData = (
            success       => \1,
            unlinkedCount => $UnlinkedCount,
            message       => "Successfully unlinked $UnlinkedCount tickets",
        );
        if (@Errors) {
            $ResponseData{warnings} = \@Errors;
        }
    }
    else {
        %ResponseData = (
            success => \0,
            message => 'No tickets were unlinked. ' . join( ', ', @Errors ),
        );
    }

    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=UTF-8',
        Content     => $JSONObject->Encode( Data => \%ResponseData ),
        Type        => 'inline',
        NoCache     => 1,
    );
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST Lite project.

This software comes with ABSOLUTELY NO WARRANTY.

=cut
