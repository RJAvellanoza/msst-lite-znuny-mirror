# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentTicketResolution;

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
    my %Data = $Self->_GetMTTRData();

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Ticket Resolution Status',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentTicketResolution',
        Data         => \%Data,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetMTTRData {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Query for Resolved vs Active tickets by priority
    # Resolved = ticket state is 'resolved' or 'closed' (NOT 'cancelled')
    # Active = ticket state type is not 'closed' (type_id != 3)
    # Cancelled tickets (state_id = 23) are excluded entirely
    my $SQL = q{
        SELECT
            tp.name as priority,
            tp.id as priority_id,
            COUNT(CASE WHEN ts.type_id = 3 AND ts.name != 'cancelled' THEN 1 END) as resolved,
            COUNT(CASE WHEN ts.type_id != 3 THEN 1 END) as active
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_state ts ON t.ticket_state_id = ts.id
        WHERE t.type_id = 2
          AND ts.name != 'cancelled'
        GROUP BY tp.name, tp.id
        ORDER BY tp.id
    };

    my %ByPriority;

    if ( !$DBObject->Prepare( SQL => $SQL ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentTicketResolution: Database query failed",
        );
        return (
            ByPriority => \%ByPriority,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $PriorityName = $Row[0];
        my $PriorityID   = $Row[1];
        my $Resolved     = $Row[2] || 0;
        my $Active       = $Row[3] || 0;
        my $Total        = $Resolved + $Active;
        my $ResolvedPct  = $Total > 0 ? sprintf("%.1f", ($Resolved / $Total) * 100) : 0;
        my $ActivePct    = $Total > 0 ? sprintf("%.1f", ($Active / $Total) * 100) : 0;

        $ByPriority{$PriorityName} = {
            Resolved    => $Resolved,
            Active      => $Active,
            Total       => $Total,
            ResolvedPct => $ResolvedPct,
            ActivePct   => $ActivePct,
            PriorityID  => $PriorityID,
        };
    }

    # Calculate totals
    my $TotalResolved = 0;
    my $TotalActive = 0;
    for my $Priority (keys %ByPriority) {
        $TotalResolved += $ByPriority{$Priority}{Resolved} || 0;
        $TotalActive += $ByPriority{$Priority}{Active} || 0;
    }

    # Get open state IDs (non-closed states) for reliable links
    my @OpenStateIDs;
    my $OpenStateSQL = q{SELECT id FROM ticket_state WHERE type_id != 3 ORDER BY id};
    if ( $DBObject->Prepare( SQL => $OpenStateSQL ) ) {
        while ( my @Row = $DBObject->FetchrowArray() ) {
            push @OpenStateIDs, $Row[0];
        }
    }
    my $OpenStateIDsStr = join(',', @OpenStateIDs);

    # Get closed state IDs (resolved/closed but not cancelled) for reliable links
    my @ClosedStateIDs;
    my $ClosedStateSQL = q{SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled' ORDER BY id};
    if ( $DBObject->Prepare( SQL => $ClosedStateSQL ) ) {
        while ( my @Row = $DBObject->FetchrowArray() ) {
            push @ClosedStateIDs, $Row[0];
        }
    }
    my $ClosedStateIDsStr = join(',', @ClosedStateIDs);

    # Get all state IDs (open + closed, excluding cancelled)
    my $AllStateIDsStr = $OpenStateIDsStr . ',' . $ClosedStateIDsStr;

    return (
        ByPriority       => \%ByPriority,
        TotalResolved    => $TotalResolved,
        TotalActive      => $TotalActive,
        GrandTotal       => $TotalResolved + $TotalActive,
        OpenStateIDs     => $OpenStateIDsStr,
        ClosedStateIDs   => $ClosedStateIDsStr,
        AllStateIDs      => $AllStateIDsStr,
    );
}

1;
