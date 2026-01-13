# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::System::IncidentKPIs;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Cache',
    'Kernel::Config',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 GetTicketsCreationHourly()

Get ticket creation counts by hour for a single day, grouped by priority.

    my %Result = $IncidentKPIsObject->GetTicketsCreationHourly(
        SelectedDate => '2025-11-13',  # YYYY-MM-DD format
    );

Returns:
    %Result = (
        HourlyBreakdown => [
            { Hour => '00', P1 => 0, P2 => 1, P3 => 2, P4 => 1, Total => 4 },
            { Hour => '01', P1 => 0, P2 => 4, P3 => 0, P4 => 0, Total => 4 },
            ...
        ],
        Summary => {
            P1 => 5, P2 => 20, P3 => 30, P4 => 10, Total => 65
        },
    );

=cut

sub GetTicketsCreationHourly {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    if ( !$Param{SelectedDate} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "GetTicketsCreationHourly: Need SelectedDate!",
        );
        return;
    }

    # Initialize result
    my @HourlyBreakdown;
    my %Summary = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0, Total => 0 );

    # Initialize all 24 hours with zero counts
    my %HourData;
    for my $Hour ( 0 .. 23 ) {
        my $HourStr = sprintf( "%02d", $Hour );
        $HourData{$HourStr} = { Hour => $HourStr, P1 => 0, P2 => 0, P3 => 0, P4 => 0, Total => 0 };
    }

    # Query ticket creation by hour and priority
    my $SQL = q{
        SELECT
            EXTRACT(HOUR FROM t.create_time)::integer AS hour,
            tp.name AS priority,
            COUNT(*) AS count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND t.create_time >= ?::timestamp
            AND t.create_time < (?::date + INTERVAL '1 day')::timestamp
        GROUP BY EXTRACT(HOUR FROM t.create_time), tp.name
        ORDER BY hour, priority
    };

    my $SelectedDate = $Param{SelectedDate};
    if ( !$DBObject->Prepare( SQL => $SQL, Bind => [ \$SelectedDate, \$SelectedDate ] ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "GetTicketsCreationHourly: SQL Prepare failed!",
        );
        return ( HourlyBreakdown => [], Summary => \%Summary );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Hour     = sprintf( "%02d", $Row[0] );
        my $Priority = $Row[1] || 'P4';
        my $Count    = $Row[2] || 0;

        # Map priority name to P1-P4
        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        $HourData{$Hour}{$PriorityKey} += $Count;
        $HourData{$Hour}{Total} += $Count;
        $Summary{$PriorityKey} += $Count;
        $Summary{Total} += $Count;
    }

    # Convert hash to sorted array
    for my $Hour ( sort keys %HourData ) {
        push @HourlyBreakdown, $HourData{$Hour};
    }

    return (
        HourlyBreakdown => \@HourlyBreakdown,
        Summary         => \%Summary,
    );
}

=head2 GetTicketsCreationDaily()

Get ticket creation counts by day for a date range, grouped by priority.

    my %Result = $IncidentKPIsObject->GetTicketsCreationDaily(
        StartDate => '2025-11-09',
        EndDate   => '2025-11-15',
    );

=cut

sub GetTicketsCreationDaily {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "GetTicketsCreationDaily: Need $Needed!",
            );
            return;
        }
    }

    # Initialize result
    my @DailyBreakdown;
    my %Summary = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0, Total => 0 );

    # Query ticket creation by day and priority
    my $SQL = q{
        SELECT
            DATE(t.create_time) AS date,
            tp.name AS priority,
            COUNT(*) AS count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND t.create_time >= ?::timestamp
            AND t.create_time < (?::date + INTERVAL '1 day')::timestamp
        GROUP BY DATE(t.create_time), tp.name
        ORDER BY date, priority
    };

    my $StartDate = $Param{StartDate};
    my $EndDate   = $Param{EndDate};

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => [ \$StartDate, \$EndDate ] ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "GetTicketsCreationDaily: SQL Prepare failed!",
        );
        return ( DailyBreakdown => [], Summary => \%Summary );
    }

    # Collect results by date
    my %DateData;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Date     = $Row[0];
        my $Priority = $Row[1] || 'P4';
        my $Count    = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( !exists $DateData{$Date} ) {
            $DateData{$Date} = { Date => $Date, P1 => 0, P2 => 0, P3 => 0, P4 => 0, Total => 0 };
        }

        $DateData{$Date}{$PriorityKey} += $Count;
        $DateData{$Date}{Total} += $Count;
        $Summary{$PriorityKey} += $Count;
        $Summary{Total} += $Count;
    }

    # Convert hash to sorted array
    for my $Date ( sort keys %DateData ) {
        push @DailyBreakdown, $DateData{$Date};
    }

    return (
        DailyBreakdown => \@DailyBreakdown,
        Summary        => \%Summary,
    );
}

=head2 GetTicketsCreationWeekly()

Get ticket creation counts by week for a given month, grouped by priority.

    my %Result = $IncidentKPIsObject->GetTicketsCreationWeekly(
        Year  => 2025,
        Month => 11,
    );

=cut

sub GetTicketsCreationWeekly {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(Year Month)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "GetTicketsCreationWeekly: Need $Needed!",
            );
            return;
        }
    }

    # Initialize result
    my @WeeklyBreakdown;
    my %Summary = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0, Total => 0 );

    # Query ticket creation by ISO week and priority
    my $SQL = q{
        SELECT
            TO_CHAR(t.create_time, 'IYYY-"W"IW') AS week,
            MIN(DATE(t.create_time)) AS week_start,
            tp.name AS priority,
            COUNT(*) AS count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND EXTRACT(YEAR FROM t.create_time) = ?
            AND EXTRACT(MONTH FROM t.create_time) = ?
        GROUP BY TO_CHAR(t.create_time, 'IYYY-"W"IW'), tp.name
        ORDER BY week, priority
    };

    my $Year  = $Param{Year};
    my $Month = $Param{Month};

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => [ \$Year, \$Month ] ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "GetTicketsCreationWeekly: SQL Prepare failed!",
        );
        return ( WeeklyBreakdown => [], Summary => \%Summary );
    }

    # Collect results by week
    my %WeekData;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Week      = $Row[0];
        my $WeekStart = $Row[1];
        my $Priority  = $Row[2] || 'P4';
        my $Count     = $Row[3] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( !exists $WeekData{$Week} ) {
            $WeekData{$Week} = {
                Week      => $Week,
                WeekStart => $WeekStart,
                P1        => 0,
                P2        => 0,
                P3        => 0,
                P4        => 0,
                Total     => 0,
            };
        }

        $WeekData{$Week}{$PriorityKey} += $Count;
        $WeekData{$Week}{Total} += $Count;
        $Summary{$PriorityKey} += $Count;
        $Summary{Total} += $Count;
    }

    # Convert hash to sorted array
    for my $Week ( sort keys %WeekData ) {
        push @WeeklyBreakdown, $WeekData{$Week};
    }

    return (
        WeeklyBreakdown => \@WeeklyBreakdown,
        Summary         => \%Summary,
    );
}

=head2 GetTicketsCreationMonthlyQuarter()

Get ticket creation counts by month for a given quarter, grouped by priority.

    my %Result = $IncidentKPIsObject->GetTicketsCreationMonthlyQuarter(
        Year    => 2025,
        Quarter => 3,  # 1-4
    );

=cut

sub GetTicketsCreationMonthlyQuarter {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(Year Quarter)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "GetTicketsCreationMonthlyQuarter: Need $Needed!",
            );
            return;
        }
    }

    # Initialize result
    my @MonthlyBreakdown;
    my %Summary = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0, Total => 0 );

    # Query ticket creation by month and priority for the quarter
    my $SQL = q{
        SELECT
            TO_CHAR(t.create_time, 'YYYY-MM') AS month,
            tp.name AS priority,
            COUNT(*) AS count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND EXTRACT(YEAR FROM t.create_time) = ?
            AND EXTRACT(QUARTER FROM t.create_time) = ?
        GROUP BY TO_CHAR(t.create_time, 'YYYY-MM'), tp.name
        ORDER BY month, priority
    };

    my $Year    = $Param{Year};
    my $Quarter = $Param{Quarter};

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => [ \$Year, \$Quarter ] ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "GetTicketsCreationMonthlyQuarter: SQL Prepare failed!",
        );
        return ( MonthlyBreakdown => [], Summary => \%Summary );
    }

    # Collect results by month
    my %MonthData;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Month    = $Row[0];
        my $Priority = $Row[1] || 'P4';
        my $Count    = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( !exists $MonthData{$Month} ) {
            $MonthData{$Month} = { Month => $Month, P1 => 0, P2 => 0, P3 => 0, P4 => 0, Total => 0 };
        }

        $MonthData{$Month}{$PriorityKey} += $Count;
        $MonthData{$Month}{Total} += $Count;
        $Summary{$PriorityKey} += $Count;
        $Summary{Total} += $Count;
    }

    # Convert hash to sorted array
    for my $Month ( sort keys %MonthData ) {
        push @MonthlyBreakdown, $MonthData{$Month};
    }

    return (
        MonthlyBreakdown => \@MonthlyBreakdown,
        Summary          => \%Summary,
    );
}

=head2 GetTicketsCreationMonthlyYear()

Get ticket creation counts by month for an entire year, grouped by priority.

    my %Result = $IncidentKPIsObject->GetTicketsCreationMonthlyYear(
        Year => 2025,
    );

=cut

sub GetTicketsCreationMonthlyYear {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    if ( !$Param{Year} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "GetTicketsCreationMonthlyYear: Need Year!",
        );
        return;
    }

    # Initialize result
    my @MonthlyBreakdown;
    my %Summary = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0, Total => 0 );

    # Query ticket creation by month and priority for the year
    my $SQL = q{
        SELECT
            TO_CHAR(t.create_time, 'YYYY-MM') AS month,
            tp.name AS priority,
            COUNT(*) AS count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND EXTRACT(YEAR FROM t.create_time) = ?
        GROUP BY TO_CHAR(t.create_time, 'YYYY-MM'), tp.name
        ORDER BY month, priority
    };

    my $Year = $Param{Year};

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => [ \$Year ] ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "GetTicketsCreationMonthlyYear: SQL Prepare failed!",
        );
        return ( MonthlyBreakdown => [], Summary => \%Summary );
    }

    # Collect results by month
    my %MonthData;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Month    = $Row[0];
        my $Priority = $Row[1] || 'P4';
        my $Count    = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( !exists $MonthData{$Month} ) {
            $MonthData{$Month} = { Month => $Month, P1 => 0, P2 => 0, P3 => 0, P4 => 0, Total => 0 };
        }

        $MonthData{$Month}{$PriorityKey} += $Count;
        $MonthData{$Month}{Total} += $Count;
        $Summary{$PriorityKey} += $Count;
        $Summary{Total} += $Count;
    }

    # Convert hash to sorted array
    for my $Month ( sort keys %MonthData ) {
        push @MonthlyBreakdown, $MonthData{$Month};
    }

    return (
        MonthlyBreakdown => \@MonthlyBreakdown,
        Summary          => \%Summary,
    );
}

=head2 _MapPriorityToKey()

Map priority name to P1/P2/P3/P4 key.

=cut

sub _MapPriorityToKey {
    my ( $Self, $Priority ) = @_;

    # Map common priority names to P1-P4
    my %PriorityMap = (
        '1 very high'    => 'P1',
        '1-Critical'     => 'P1',
        'P1-Critical'    => 'P1',
        'P1'             => 'P1',
        '2 high'         => 'P2',
        '2-High'         => 'P2',
        'P2-High'        => 'P2',
        'P2'             => 'P2',
        '3 normal'       => 'P3',
        '3-Medium'       => 'P3',
        'P3-Medium'      => 'P3',
        'P3'             => 'P3',
        '4 low'          => 'P4',
        '4-Low'          => 'P4',
        'P4-Low'         => 'P4',
        'P4'             => 'P4',
        '5 very low'     => 'P4',
    );

    return $PriorityMap{$Priority} || 'P4';
}

1;
