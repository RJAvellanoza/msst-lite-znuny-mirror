# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Config::Files::ZZZZZEscalationViewConditional;

use strict;
use warnings;

use utf8;

=head1 NAME

Kernel::Config::Files::ZZZZZEscalationViewConditional - Conditional navigation for escalation view

=head1 DESCRIPTION

This configuration file controls the visibility of the AgentTicketEscalationView menu item
based on whether Easy MSI Escalation integration is enabled. The escalation view only shows MSI-escalated
incidents, so it should only be visible when Easy MSI Escalation is enabled.

File name starts with ZZZZZ to ensure it loads after all other configuration files,
allowing it to override the navigation setting based on runtime configuration.

=cut

sub Load {
    my ($File, $Self) = @_;

    # Check if Easy MSI Escalation integration is enabled
    my $EBondingEnabled = $Self->{'EBondingIntegration::Enabled'};

    # Only show escalation view menu if Easy MSI Escalation is enabled
    # If Easy MSI Escalation is disabled, remove the navigation menu item
    if (!$EBondingEnabled) {
        # Remove the escalation view from ticket navigation
        delete $Self->{'Frontend::Navigation'}->{'AgentTicketEscalationView'}->{'002-Ticket'};
    }

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST Lite project.

This software comes with ABSOLUTELY NO WARRANTY.

=cut
