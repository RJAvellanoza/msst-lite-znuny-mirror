# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentAverageBacklog;

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
    my %Data = $Self->_GetBacklogData();

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Active Tickets Average Backlog',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentAverageBacklog',
        Data         => \%Data,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetBacklogData {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Query for average backlog (days since create_time) and count for active tickets grouped by priority
    my $SQL = q{
        SELECT
            tp.name as priority,
            tp.id as priority_id,
            ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - t.create_time)) / 86400)) as avg_days,
            COUNT(*) as ticket_count
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

    if ( !$DBObject->Prepare( SQL => $SQL ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentAverageBacklog: Database query failed",
        );
        return (
            ByPriority => \%ByPriority,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $PriorityName = $Row[0];
        my $PriorityID   = $Row[1];
        my $AvgDays      = $Row[2] || 0;
        my $Count        = $Row[3] || 0;

        $ByPriority{$PriorityName} = {
            AvgDays    => $AvgDays,
            Count      => $Count,
            PriorityID => $PriorityID,
        };
    }

    # Calculate simple averages across all priorities (P1 + P2 + P3 + P4) / 4
    my $P1Days = $ByPriority{'P1-Critical'}{AvgDays} || 0;
    my $P2Days = $ByPriority{'P2-High'}{AvgDays} || 0;
    my $P3Days = $ByPriority{'P3-Medium'}{AvgDays} || 0;
    my $P4Days = $ByPriority{'P4-Low'}{AvgDays} || 0;

    my $P1Count = $ByPriority{'P1-Critical'}{Count} || 0;
    my $P2Count = $ByPriority{'P2-High'}{Count} || 0;
    my $P3Count = $ByPriority{'P3-Medium'}{Count} || 0;
    my $P4Count = $ByPriority{'P4-Low'}{Count} || 0;

    my $AvgBacklogDays = sprintf("%.0f", ($P1Days + $P2Days + $P3Days + $P4Days) / 4);
    my $AvgTicketCount = sprintf("%.0f", ($P1Count + $P2Count + $P3Count + $P4Count) / 4);

    # Get open state IDs (non-closed states) for reliable links
    my @OpenStateIDs;
    my $StateSQL = q{SELECT id FROM ticket_state WHERE type_id != 3 ORDER BY id};
    if ( $DBObject->Prepare( SQL => $StateSQL ) ) {
        while ( my @Row = $DBObject->FetchrowArray() ) {
            push @OpenStateIDs, $Row[0];
        }
    }
    my $OpenStateIDsStr = join(',', @OpenStateIDs);

    # Get Incident type ID
    my $IncidentTypeID = 2;  # default
    my $TypeSQL = q{SELECT id FROM ticket_type WHERE name = 'Incident' AND valid_id = 1};
    if ( $DBObject->Prepare( SQL => $TypeSQL ) ) {
        my @Row = $DBObject->FetchrowArray();
        $IncidentTypeID = $Row[0] if @Row;
    }

    return (
        ByPriority      => \%ByPriority,
        AvgBacklogDays  => $AvgBacklogDays,
        AvgTicketCount  => $AvgTicketCount,
        OpenStateIDs    => $OpenStateIDsStr,
        IncidentTypeID  => $IncidentTypeID,
    );
}

1;
