# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentActiveTicketsAssignment;

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
    my %Data = $Self->_GetAssignmentData();

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Active Tickets Assignment Report',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentActiveTicketsAssignment',
        Data         => \%Data,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetAssignmentData {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Query for ALL active tickets grouped by priority and assignment state (no date filter)
    my $SQL = q{
        SELECT
            tp.name as priority,
            COUNT(CASE WHEN t.user_id IS NOT NULL AND t.user_id NOT IN (1, 99) THEN 1 END) as assigned,
            COUNT(CASE WHEN t.user_id IS NULL OR t.user_id IN (1, 99) THEN 1 END) as unassigned,
            COUNT(*) as total
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = 2
          AND t.ticket_state_id NOT IN (
              SELECT id FROM ticket_state WHERE type_id = 3
          )
        GROUP BY tp.name, tp.id
        ORDER BY tp.id
    };

    my %ByPriority;
    my %Summary = (
        Total      => 0,
        Assigned   => 0,
        Unassigned => 0,
    );

    if ( !$DBObject->Prepare( SQL => $SQL ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentActiveTicketsAssignment: Database query failed",
        );
        return (
            ByPriority => \%ByPriority,
            Summary    => \%Summary,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $PriorityName = $Row[0];
        my $Assigned     = $Row[1] || 0;
        my $Unassigned   = $Row[2] || 0;
        my $Total        = $Row[3] || 0;

        # Calculate percentages
        my $AssignedPct   = $Total > 0 ? sprintf("%.1f", ($Assigned / $Total) * 100) : 0;
        my $UnassignedPct = $Total > 0 ? sprintf("%.1f", ($Unassigned / $Total) * 100) : 0;

        $ByPriority{$PriorityName} = {
            Assigned      => $Assigned,
            Unassigned    => $Unassigned,
            Total         => $Total,
            AssignedPct   => $AssignedPct,
            UnassignedPct => $UnassignedPct,
        };

        # Accumulate summary
        $Summary{Total}      += $Total;
        $Summary{Assigned}   += $Assigned;
        $Summary{Unassigned} += $Unassigned;
    }

    return (
        ByPriority      => \%ByPriority,
        TotalAssigned   => $Summary{Assigned},
        TotalUnassigned => $Summary{Unassigned},
        GrandTotal      => $Summary{Total},
    );
}

1;
