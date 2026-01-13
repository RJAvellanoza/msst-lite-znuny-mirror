# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentEscalatedActiveTicket;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Log',
    'Kernel::System::DB',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # Get data
    my %Data = $Self->_GetMTRDData();

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Active Tickets',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentEscalatedActiveTicket',
        Data         => \%Data,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetMTRDData {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Query for Escalated vs Non-Escalated ACTIVE Incident tickets
    # Escalated = ticket has MSITicketNumber populated
    # Non-Escalated = ticket has no MSITicketNumber (or empty)
    my $SQL = q{
        SELECT
            COUNT(CASE WHEN dfv_msi.value_text IS NOT NULL AND dfv_msi.value_text != '' THEN 1 END) as escalated,
            COUNT(CASE WHEN dfv_msi.value_text IS NULL OR dfv_msi.value_text = '' THEN 1 END) as non_escalated
        FROM ticket t
        JOIN ticket_state ts ON t.ticket_state_id = ts.id
        LEFT JOIN dynamic_field_value dfv_msi ON t.id = dfv_msi.object_id
            AND dfv_msi.field_id = (SELECT id FROM dynamic_field WHERE name = 'MSITicketNumber')
        WHERE t.type_id = 2
          AND ts.type_id != 3
    };

    my $Escalated = 0;
    my $NonEscalated = 0;

    if ( !$DBObject->Prepare( SQL => $SQL ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentEscalatedActiveTicket: Database query failed",
        );
        return (
            Escalated       => 0,
            NonEscalated    => 0,
            EscalatedPct    => 0,
            NonEscalatedPct => 0,
            GrandTotal      => 0,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Escalated    = $Row[0] || 0;
        $NonEscalated = $Row[1] || 0;
    }

    my $Total = $Escalated + $NonEscalated;
    my $EscalatedPct    = $Total > 0 ? sprintf("%.1f", ($Escalated / $Total) * 100) : 0;
    my $NonEscalatedPct = $Total > 0 ? sprintf("%.1f", ($NonEscalated / $Total) * 100) : 0;

    return (
        Escalated       => $Escalated,
        NonEscalated    => $NonEscalated,
        EscalatedPct    => $EscalatedPct,
        NonEscalatedPct => $NonEscalatedPct,
        GrandTotal      => $Total,
    );
}

1;
