# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::FilterContent::EscalationViewBulkUpdate;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Web::Request',
);

=head1 NAME

Kernel::Output::HTML::FilterContent::EscalationViewBulkUpdate - Output filter to inject bulk update checkboxes

=head1 DESCRIPTION

Injects checkboxes into the AgentTicketEscalationView ticket table for bulk update selection.
Runs ONLY on Action=AgentTicketEscalationView (not dashboard widgets).

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Get request object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action      = $ParamObject->GetParam( Param => 'Action' ) || '';

    # CRITICAL: Only run on AgentTicketEscalationView PAGE, not dashboard widget
    return 1 if $Action ne 'AgentTicketEscalationView';

    # Get template content
    my $Content = ${ $Param{Data} };

    # Step 1: Add checkbox column header (empty, no select-all)
    my $HeaderCheckbox = '<th class="BulkUpdateCheckboxColumn"></th>';

    # Inject into first <thead><tr>
    $Content =~ s{(<thead[^>]*>.*?<tr[^>]*>)}{$1$HeaderCheckbox}s;

    # Step 2: Add checkbox cell to each ticket row
    # Extract TicketID from id="TicketID_NNN" attribute and inject checkbox after <tr>
    # Use slash delimiters to avoid conflicts with braces in replacement code
    $Content =~ s/(<tr\s+id="TicketID_(\d+)"[^>]*class="[^"]*MasterAction[^"]*"[^>]*>)/$1 . qq{<td class="BulkUpdateCheckboxColumn"><input type="checkbox" class="BulkUpdateCheckbox" data-ticket-id="$2" \/><\/td>}/sge;

    # Update the content reference
    ${ $Param{Data} } = $Content;

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST Lite project.

This software comes with ABSOLUTELY NO WARRANTY.

=cut
