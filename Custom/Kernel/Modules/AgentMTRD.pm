# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentMTRD;

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
        Title => 'Active Tickets Response Status',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentMTRD',
        Data         => \%Data,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetMTRDData {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Query for Responded vs Unresponded ACTIVE tickets by priority
    # Responded = ticket currently has an owner assigned (user_id NOT IN root/unassigned)
    # Unresponded = ticket has no owner assigned (user_id is root or unassigned)
    my $SQL = q{
        SELECT
            tp.name as priority,
            COUNT(CASE WHEN t.user_id NOT IN (1, 99) THEN 1 END) as responded,
            COUNT(CASE WHEN t.user_id IN (1, 99) THEN 1 END) as unresponded
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_state ts ON t.ticket_state_id = ts.id
        WHERE t.type_id = 2
          AND ts.type_id != 3
        GROUP BY tp.name, tp.id
        ORDER BY tp.id
    };

    my %ByPriority;

    if ( !$DBObject->Prepare( SQL => $SQL ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentMTRD: Database query failed",
        );
        return (
            ByPriority => \%ByPriority,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $PriorityName = $Row[0];
        my $Responded    = $Row[1] || 0;
        my $Unresponded  = $Row[2] || 0;
        my $Total        = $Responded + $Unresponded;
        my $RespondedPct = $Total > 0 ? sprintf("%.1f", ($Responded / $Total) * 100) : 0;
        my $UnrespondedPct = $Total > 0 ? sprintf("%.1f", ($Unresponded / $Total) * 100) : 0;

        $ByPriority{$PriorityName} = {
            Responded      => $Responded,
            Unresponded    => $Unresponded,
            Total          => $Total,
            RespondedPct   => $RespondedPct,
            UnrespondedPct => $UnrespondedPct,
        };
    }

    # Calculate totals
    my $TotalResponded = 0;
    my $TotalUnresponded = 0;
    for my $Priority (keys %ByPriority) {
        $TotalResponded += $ByPriority{$Priority}{Responded} || 0;
        $TotalUnresponded += $ByPriority{$Priority}{Unresponded} || 0;
    }

    return (
        ByPriority       => \%ByPriority,
        TotalResponded   => $TotalResponded,
        TotalUnresponded => $TotalUnresponded,
        GrandTotal       => $TotalResponded + $TotalUnresponded,
    );
}

1;
