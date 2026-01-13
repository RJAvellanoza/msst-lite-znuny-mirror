# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::Dashboard::EscalatedTickets;

use strict;
use warnings;

use parent qw(Kernel::Output::HTML::Dashboard::TicketGeneric);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::Output::HTML::Dashboard::EscalatedTickets - Dashboard widget for escalated tickets

=head1 DESCRIPTION

Extends TicketGeneric to show only tickets that have been escalated to MSI ServiceNow
(i.e., tickets with MSITicketNumber dynamic field populated).

=head1 PUBLIC INTERFACE

=head2 new()

Create an object. Inherits from TicketGeneric.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # Call parent constructor
    my $Self = $Type->SUPER::new(%Param);

    return $Self;
}

=head2 Run()

Override parent Run to check if Easy MSI Escalation is enabled.

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # Check if Easy MSI Escalation integration is enabled
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $EBondingEnabled = $ConfigObject->Get('EBondingIntegration::Enabled') || 0;

    # If Easy MSI Escalation is disabled, return empty content (hide widget)
    if (!$EBondingEnabled) {
        return '';
    }

    # Call parent Run method
    return $Self->SUPER::Run(%Param);
}

=head2 Config()

Override parent Config to ensure proper cache key.

=cut

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },
        CacheKey => 'EscalatedTickets-'
            . $Self->{UserID} . '-'
            . $Kernel::OM->Get('Kernel::Output::HTML::Layout')->{UserLanguage},
    );
}

=head2 _SearchParamsGet()

Override parent _SearchParamsGet to add MSITicketNumber filter.

=cut

sub _SearchParamsGet {
    my ( $Self, %Param ) = @_;

    # Call parent to get base search params
    my %SearchParams = $Self->SUPER::_SearchParamsGet(%Param);

    # Get dynamic field object
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

    # Get MSITicketNumber dynamic field config
    my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
        Name => 'MSITicketNumber',
    );

    if ($DynamicFieldConfig) {
        # Add dynamic field search for MSITicketNumber not empty
        # Empty => 0 means "search for fields with a value present"
        $SearchParams{TicketSearch}->{'DynamicField_MSITicketNumber'} = {
            Empty => 0,  # Filter for non-empty values only
        };
    }

    return %SearchParams;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST Lite project.

This software comes with ABSOLUTELY NO WARRANTY.

=cut
