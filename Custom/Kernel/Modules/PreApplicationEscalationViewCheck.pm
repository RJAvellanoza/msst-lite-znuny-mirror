# --
# Kernel/Modules/PreApplicationEscalationViewCheck.pm - Block escalation view when Easy MSI Escalation disabled
# Copyright (C) 2025 MSST
# --
# This module enforces Easy MSI Escalation requirement for escalation view access
# --

package Kernel::Modules::PreApplicationEscalationViewCheck;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub PreRun {
    my ( $Self, %Param ) = @_;

    # Get needed objects
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # Get current action
    my $Action = $ParamObject->GetParam( Param => 'Action' ) || '';

    # Only check for escalation view action
    return if $Action ne 'AgentTicketEscalationView';

    # Check if Easy MSI Escalation integration is enabled
    my $EBondingEnabled = $ConfigObject->Get('EBondingIntegration::Enabled');

    # Allow access if Easy MSI Escalation is enabled
    return if $EBondingEnabled;

    # Block access if Easy MSI Escalation is disabled
    # Escalation view only shows MSI-escalated incidents, which require Easy MSI Escalation
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    print $LayoutObject->Header(
        Title => 'Feature Not Available',
    );
    print $LayoutObject->Warning(
        Message => 'Escalation View Not Available',
        Comment => 'The escalation view requires Easy MSI Escalation integration to be enabled. This feature displays incidents that have been escalated to MSI ServiceNow. Please contact your administrator to enable Easy MSI Escalation integration in System Configuration.',
    );
    print $LayoutObject->Footer();

    # Exit to prevent further processing
    exit;
}

1;
