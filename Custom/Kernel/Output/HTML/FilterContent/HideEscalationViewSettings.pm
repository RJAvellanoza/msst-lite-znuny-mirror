# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::FilterContent::HideEscalationViewSettings;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Web::Request',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get template name
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action      = $ParamObject->GetParam( Param => 'Action' ) || '';

    # only run on AgentTicketEscalationView
    return 1 if $Action ne 'AgentTicketEscalationView';

    # hide the settings icon using CSS
    my $CSS = qq{
<style type="text/css">
/* Hide column settings icon on escalation view to lock columns */
.ContextSettings {
    display: none !important;
}
</style>
};

    # inject CSS before the closing head tag
    ${ $Param{Data} } =~ s{</head>}{$CSS</head>}xmsi;

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST Lite project.

This software comes with ABSOLUTELY NO WARRANTY.

=cut
