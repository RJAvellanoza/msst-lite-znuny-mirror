# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::System::OperationalKPIs;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Cache',
    'Kernel::System::Ticket',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Time',
    'Kernel::Config',
    'Kernel::System::JSON',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub CalculateMTRD {
    my ( $Self, %Param ) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $CacheObject  = $Kernel::OM->Get('Kernel::System::Cache');

    # Check required parameters
    for my $Needed (qw(StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "CalculateMTRD: Need $Needed!",
            );
            return;
        }
    }

    # Set defaults
    $Param{AggregationLevel} ||= 'daily';

    # Check cache first
    my $CacheEnabled = $ConfigObject->Get('OperationalKPIs::CacheEnabled');
    my $CacheKey;  # Declare outside if block so it's available throughout method

    if ($CacheEnabled) {
        $CacheKey = join '::', 'MTRD', $Param{StartDate}, $Param{EndDate},
            ($Param{Priority} || 'all'), ($Param{Source} || 'all'), $Param{AggregationLevel};

        my $Cached = $CacheObject->Get(
            Type => 'OperationalKPIs',
            Key  => $CacheKey,
        );
        return %{$Cached} if $Cached;
    }

    # Try to get data from cache table first
    my %CacheResult = $Self->_GetFromCacheTable(
        ReportType       => 'mtrd',
        StartDate        => $Param{StartDate},
        EndDate          => $Param{EndDate},
        Priority         => $Param{Priority},
        Source           => $Param{Source},
        AggregationLevel => $Param{AggregationLevel},
    );

    if (%CacheResult) {
        # Store in memory cache for faster access
        if ($CacheEnabled) {
            my $CacheTTL = $ConfigObject->Get('OperationalKPIs::CacheTTL') || 60;
            $CacheObject->Set(
                Type  => 'OperationalKPIs',
                Key   => $CacheKey,
                Value => \%CacheResult,
                TTL   => $CacheTTL * 60,
            );
        }
        return %CacheResult;
    }

    # Calculate from database
    my %Result = $Self->_CalculateMTRDFromDatabase(%Param);

    # Store in cache
    if ($CacheEnabled) {
        my $CacheTTL = $ConfigObject->Get('OperationalKPIs::CacheTTL') || 60;
        $CacheObject->Set(
            Type  => 'OperationalKPIs',
            Key   => $CacheKey,
            Value => \%Result,
            TTL   => $CacheTTL * 60,
        );
    }

    return %Result;
}

sub _CalculateMTRDFromDatabase {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Initialize result with default values
    my %Result = (
        TotalIncidents => 0,
        AverageMTRD    => 0,
    );

    # Log input parameters
    $LogObject->Log(
        Priority => 'notice',
        Message  => "_CalculateMTRDFromDatabase called with StartDate=$Param{StartDate}, EndDate=$Param{EndDate}, "
                   . "Priority=" . ($Param{Priority} || 'none') . ", Source=" . ($Param{Source} || 'none'),
    );

    # Build SQL query for MTRD calculation
    my $SQL = q{
        SELECT
            COUNT(*) as total_incidents,
            AVG(EXTRACT(EPOCH FROM (COALESCE(df_response.value_date, t.change_time) - t.create_time))) as avg_mtrd_seconds
        FROM ticket t
        LEFT JOIN dynamic_field_value df_response ON df_response.object_id = t.id
            AND df_response.field_id = (SELECT id FROM dynamic_field WHERE name = 'Response')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.create_time >= ?
        AND t.create_time < ?
        AND t.user_id IS NOT NULL  -- Has been assigned
        AND t.user_id NOT IN (1, 99)  -- Exclude root and 'unassigned' user (treated as unassigned)
    };

    my @Bind;

    # Add date range (use scalar references for Znuny DBI)
    push @Bind, \$Param{StartDate}, \$Param{EndDate};

    # Add filters
    if ( $Param{Priority} ) {
        $SQL .= " AND t.ticket_priority_id = (SELECT id FROM ticket_priority WHERE name = ?) ";
        push @Bind, \$Param{Priority};
    }

    if ( $Param{Source} ) {
        $SQL .= q{
            AND EXISTS (
                SELECT 1 FROM dynamic_field_value df_source
                WHERE df_source.object_id = t.id
                AND df_source.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
                AND df_source.value_text = ?
            )
        };
        push @Bind, \$Param{Source};
    }

    # Execute query
    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_CalculateMTRDFromDatabase: SQL Prepare failed for date range $Param{StartDate} to $Param{EndDate}",
        );
        return %Result;  # Return hash with zeros
    }

    # Fetch results
    my $RowCount = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $RowCount++;
        $Result{TotalIncidents} = $Row[0] || 0;
        $Result{AverageMTRD}    = int($Row[1] || 0);  # Convert to integer
    }

    # Log results
    $LogObject->Log(
        Priority => 'notice',
        Message  => "_CalculateMTRDFromDatabase: Fetched $RowCount row(s), TotalIncidents=$Result{TotalIncidents}, AverageMTRD=$Result{AverageMTRD}",
    );

    # Calculate breakdown by period if needed
    if ( $Param{AggregationLevel} && $Param{AggregationLevel} ne 'total' ) {
        $Result{BreakdownByPeriod} = $Self->_CalculateMTRDBreakdown(%Param);
    }

    return %Result;
}

sub _CalculateMTRDBreakdown {
    my ( $Self, %Param ) = @_;

    # Implementation for period breakdown (daily, weekly, monthly)
    # This would group results by date periods
    return [];
}

sub CalculateMTRDByPriority {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # SQL to get MTRD broken down by priority
    my $SQL = q{
        SELECT
            tp.name as priority_name,
            COUNT(*) as incident_count,
            AVG(EXTRACT(EPOCH FROM (COALESCE(df_response.value_date, t.change_time) - t.create_time))) as avg_mtrd_seconds
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        LEFT JOIN dynamic_field_value df_response ON df_response.object_id = t.id
            AND df_response.field_id = (SELECT id FROM dynamic_field WHERE name = 'Response')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.create_time >= ?
        AND t.create_time < ?
        AND t.user_id IS NOT NULL
        GROUP BY tp.name, tp.id
        ORDER BY tp.id
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my @Breakdown;
    my $TotalCount = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $TotalCount += $Row[1];
        push @Breakdown, {
            Priority    => $Row[0],
            Count       => $Row[1] || 0,
            AverageMTRD => int($Row[2] || 0),
        };
    }

    # Calculate percentages
    for my $Item (@Breakdown) {
        $Item->{Percentage} = $TotalCount > 0 ? sprintf("%.1f", ($Item->{Count} / $TotalCount) * 100) : 0;
    }

    return @Breakdown;
}

sub CalculateMTRDBySource {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # SQL to get MTRD broken down by source
    my $SQL = q{
        SELECT
            COALESCE(df_source.value_text, 'Unknown') as source,
            COUNT(*) as incident_count,
            AVG(EXTRACT(EPOCH FROM (COALESCE(df_response.value_date, t.change_time) - t.create_time))) as avg_mtrd_seconds
        FROM ticket t
        LEFT JOIN dynamic_field_value df_source ON df_source.object_id = t.id
            AND df_source.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        LEFT JOIN dynamic_field_value df_response ON df_response.object_id = t.id
            AND df_response.field_id = (SELECT id FROM dynamic_field WHERE name = 'Response')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.create_time >= ?
        AND t.create_time < ?
        AND t.user_id IS NOT NULL
        GROUP BY df_source.value_text
        ORDER BY incident_count DESC
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my @Breakdown;
    my $TotalCount = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $TotalCount += $Row[1];
        push @Breakdown, {
            Source      => $Row[0],
            Count       => $Row[1] || 0,
            AverageMTRD => int($Row[2] || 0),
        };
    }

    # Calculate percentages
    for my $Item (@Breakdown) {
        $Item->{Percentage} = $TotalCount > 0 ? sprintf("%.1f", ($Item->{Count} / $TotalCount) * 100) : 0;
    }

    return @Breakdown;
}

sub GetLiveUnassignedDashboard {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Get current unassigned incidents with details
    my $SQL = q{
        SELECT
            t.id,
            t.tn as ticket_number,
            t.title,
            tp.name as priority,
            t.create_time,
            COALESCE(df_source.value_text, 'Unknown') as source
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        LEFT JOIN dynamic_field_value df_source
            ON df_source.object_id = t.id
            AND df_source.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND (t.user_id IS NULL OR t.user_id IN (1, 99))  -- Include root and 'unassigned' user as unassigned
        AND t.ticket_state_id NOT IN (
            SELECT id FROM ticket_state WHERE type_id = 3
        )
        ORDER BY tp.id ASC, t.create_time ASC
    };

    return () if !$DBObject->Prepare( SQL => $SQL );

    my @UnassignedTickets;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        # Calculate age
        my $CreateSystemTime = $TimeObject->TimeStamp2SystemTime(
            String => $Row[4],
        );
        my $CurrentTime = $TimeObject->SystemTime();
        my $AgeSeconds = $CurrentTime - $CreateSystemTime;

        # Format age in simple format: "8 days 6 hours"
        my $Days = int($AgeSeconds / (24 * 3600));
        my $RemainingSeconds = $AgeSeconds % (24 * 3600);
        my $Hours = int($RemainingSeconds / 3600);

        my $AgeFormatted;
        if ($Days > 0) {
            $AgeFormatted = sprintf("%d days %d hours", $Days, $Hours);
        } elsif ($Hours > 0) {
            my $Minutes = int(($RemainingSeconds % 3600) / 60);
            $AgeFormatted = sprintf("%d hours %d mins", $Hours, $Minutes);
        } else {
            my $Minutes = int($AgeSeconds / 60);
            $AgeFormatted = sprintf("%d mins", $Minutes);
        }

        push @UnassignedTickets, {
            TicketID     => $Row[0],
            TicketNumber => $Row[1],
            Title        => $Row[2],
            Priority     => $Row[3],
            CreatedTime  => $Row[4],
            Age          => $AgeFormatted,
            AgeSeconds   => $CurrentTime - $CreateSystemTime,
            Source       => $Row[5],
        };
    }

    return @UnassignedTickets;
}

sub CalculateMTRDDaily {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    if ( !$Param{SelectedDate} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "CalculateMTRDDaily: Need SelectedDate!",
        );
        return;
    }

    # SQL for hourly breakdown
    my $SQL = q{
        SELECT
            EXTRACT(HOUR FROM t.create_time) as hour,
            COUNT(*) as total,
            COUNT(CASE WHEN t.user_id IS NOT NULL AND t.user_id NOT IN (1, 99) THEN 1 END) as assigned,
            COUNT(CASE WHEN t.user_id IS NULL OR t.user_id IN (1, 99) THEN 1 END) as unassigned,
            AVG(CASE WHEN t.user_id IS NOT NULL AND t.user_id NOT IN (1, 99)
                THEN EXTRACT(EPOCH FROM (COALESCE(df_response.value_date, t.change_time) - t.create_time))
                END) as avg_mtrd_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        LEFT JOIN dynamic_field_value df_response
            ON df_response.object_id = t.id
            AND df_response.field_id = (SELECT id FROM dynamic_field WHERE name = 'Response')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND DATE(t.create_time) = DATE(?)
        GROUP BY EXTRACT(HOUR FROM t.create_time)
        ORDER BY hour
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{SelectedDate} ],
    );

    my @HourlyBreakdown;
    my %Summary = (
        Total => 0, Assigned => 0, Unassigned => 0,
        AverageMTRD => 0, P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %HourData = (
            Hour        => $Row[0],
            Total       => $Row[1] || 0,
            Assigned    => $Row[2] || 0,
            Unassigned  => $Row[3] || 0,
            AverageMTRD => int($Row[4] || 0),
            P1          => $Row[5] || 0,
            P2          => $Row[6] || 0,
            P3          => $Row[7] || 0,
            P4          => $Row[8] || 0,
        );
        push @HourlyBreakdown, \%HourData;

        # Accumulate summary
        $Summary{Total} += $HourData{Total};
        $Summary{Assigned} += $HourData{Assigned};
        $Summary{Unassigned} += $HourData{Unassigned};
        $Summary{P1} += $HourData{P1};
        $Summary{P2} += $HourData{P2};
        $Summary{P3} += $HourData{P3};
        $Summary{P4} += $HourData{P4};
    }

    # Calculate overall average MTRD for the day
    if ( $Summary{Assigned} > 0 ) {
        my $TotalMTRD = 0;
        my $Count = 0;
        for my $Hour (@HourlyBreakdown) {
            if ( $Hour->{Assigned} > 0 ) {
                $TotalMTRD += $Hour->{AverageMTRD} * $Hour->{Assigned};
                $Count += $Hour->{Assigned};
            }
        }
        $Summary{AverageMTRD} = $Count > 0 ? int($TotalMTRD / $Count) : 0;
    }

    return (
        Date => $Param{SelectedDate},
        HourlyBreakdown => \@HourlyBreakdown,
        Summary => \%Summary,
    );
}

sub CalculateMTRDWeekly {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "CalculateMTRDWeekly: Need $Needed!",
            );
            return;
        }
    }

    # SQL for daily breakdown within the week
    my $SQL = q{
        SELECT
            TO_CHAR(t.create_time, 'Day') as weekday,
            EXTRACT(DOW FROM t.create_time) as day_number,
            DATE(t.create_time) as date,
            COUNT(*) as total,
            AVG(CASE WHEN t.user_id IS NOT NULL
                THEN EXTRACT(EPOCH FROM (COALESCE(df_response.value_date, t.change_time) - t.create_time))
                END) as avg_mtrd_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        LEFT JOIN dynamic_field_value df_response
            ON df_response.object_id = t.id
            AND df_response.field_id = (SELECT id FROM dynamic_field WHERE name = 'Response')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.create_time >= ?
        AND t.create_time < ?
        GROUP BY TO_CHAR(t.create_time, 'Day'), EXTRACT(DOW FROM t.create_time), DATE(t.create_time)
        ORDER BY day_number
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my @DailyBreakdown;
    my %Summary = (
        Total => 0, AverageMTRD => 0,
        P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %DayData = (
            Weekday     => $Row[0],
            DayNumber   => $Row[1],
            Date        => $Row[2],
            Total       => $Row[3] || 0,
            AverageMTRD => int($Row[4] || 0),
            P1          => $Row[5] || 0,
            P2          => $Row[6] || 0,
            P3          => $Row[7] || 0,
            P4          => $Row[8] || 0,
        );
        push @DailyBreakdown, \%DayData;

        $Summary{Total} += $DayData{Total};
        $Summary{P1} += $DayData{P1};
        $Summary{P2} += $DayData{P2};
        $Summary{P3} += $DayData{P3};
        $Summary{P4} += $DayData{P4};
    }

    # Calculate weighted average MTRD
    if ( @DailyBreakdown ) {
        my $TotalMTRD = 0;
        my $Count = 0;
        for my $Day (@DailyBreakdown) {
            if ( $Day->{Total} > 0 && $Day->{AverageMTRD} > 0 ) {
                $TotalMTRD += $Day->{AverageMTRD} * $Day->{Total};
                $Count += $Day->{Total};
            }
        }
        $Summary{AverageMTRD} = $Count > 0 ? int($TotalMTRD / $Count) : 0;
    }

    return (
        StartDate => $Param{StartDate},
        EndDate => $Param{EndDate},
        DailyBreakdown => \@DailyBreakdown,
        Summary => \%Summary,
    );
}

sub CalculateMTRDMonthly {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(Year Month)) {
        if ( !defined $Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "CalculateMTRDMonthly: Need $Needed!",
            );
            return;
        }
    }

    # SQL for weekly breakdown within the month
    my $SQL = q{
        SELECT
            DATE_TRUNC('week', t.create_time) as week_start,
            COUNT(*) as total,
            AVG(CASE WHEN t.user_id IS NOT NULL
                THEN EXTRACT(EPOCH FROM (COALESCE(df_response.value_date, t.change_time) - t.create_time))
                END) as avg_mtrd_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        LEFT JOIN dynamic_field_value df_response
            ON df_response.object_id = t.id
            AND df_response.field_id = (SELECT id FROM dynamic_field WHERE name = 'Response')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND EXTRACT(YEAR FROM t.create_time) = ?
        AND EXTRACT(MONTH FROM t.create_time) = ?
        GROUP BY DATE_TRUNC('week', t.create_time)
        ORDER BY week_start
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{Year}, \$Param{Month} ],
    );

    my @WeeklyBreakdown;
    my %Summary = (
        Total => 0, AverageMTRD => 0,
        P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );
    my $WeekNumber = 1;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %WeekData = (
            WeekNumber  => $WeekNumber++,
            WeekStart   => $Row[0],
            Total       => $Row[1] || 0,
            AverageMTRD => int($Row[2] || 0),
            P1          => $Row[3] || 0,
            P2          => $Row[4] || 0,
            P3          => $Row[5] || 0,
            P4          => $Row[6] || 0,
        );
        push @WeeklyBreakdown, \%WeekData;

        $Summary{Total} += $WeekData{Total};
        $Summary{P1} += $WeekData{P1};
        $Summary{P2} += $WeekData{P2};
        $Summary{P3} += $WeekData{P3};
        $Summary{P4} += $WeekData{P4};
    }

    # Calculate weighted average
    if ( @WeeklyBreakdown ) {
        my $TotalMTRD = 0;
        my $Count = 0;
        for my $Week (@WeeklyBreakdown) {
            if ( $Week->{Total} > 0 && $Week->{AverageMTRD} > 0 ) {
                $TotalMTRD += $Week->{AverageMTRD} * $Week->{Total};
                $Count += $Week->{Total};
            }
        }
        $Summary{AverageMTRD} = $Count > 0 ? int($TotalMTRD / $Count) : 0;
    }

    return (
        Year => $Param{Year},
        Month => $Param{Month},
        WeeklyBreakdown => \@WeeklyBreakdown,
        Summary => \%Summary,
    );
}

sub CalculateMTRDQuarterly {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(Year Quarter)) {
        if ( !defined $Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "CalculateMTRDQuarterly: Need $Needed!",
            );
            return;
        }
    }

    # Calculate month range for quarter
    my $StartMonth = ($Param{Quarter} - 1) * 3 + 1;
    my $EndMonth = $StartMonth + 2;

    # SQL for monthly breakdown within the quarter
    my $SQL = q{
        SELECT
            EXTRACT(MONTH FROM t.create_time) as month,
            COUNT(*) as total,
            AVG(CASE WHEN t.user_id IS NOT NULL
                THEN EXTRACT(EPOCH FROM (COALESCE(df_response.value_date, t.change_time) - t.create_time))
                END) as avg_mtrd_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        LEFT JOIN dynamic_field_value df_response
            ON df_response.object_id = t.id
            AND df_response.field_id = (SELECT id FROM dynamic_field WHERE name = 'Response')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND EXTRACT(YEAR FROM t.create_time) = ?
        AND EXTRACT(MONTH FROM t.create_time) BETWEEN ? AND ?
        GROUP BY EXTRACT(MONTH FROM t.create_time)
        ORDER BY month
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{Year}, \$StartMonth, \$EndMonth ],
    );

    my @MonthlyBreakdown;
    my %Summary = (
        Total => 0, AverageMTRD => 0,
        P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );

    my @MonthNames = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %MonthData = (
            Month       => $Row[0],
            MonthName   => $MonthNames[$Row[0] - 1],
            Total       => $Row[1] || 0,
            AverageMTRD => int($Row[2] || 0),
            P1          => $Row[3] || 0,
            P2          => $Row[4] || 0,
            P3          => $Row[5] || 0,
            P4          => $Row[6] || 0,
        );
        push @MonthlyBreakdown, \%MonthData;

        $Summary{Total} += $MonthData{Total};
        $Summary{P1} += $MonthData{P1};
        $Summary{P2} += $MonthData{P2};
        $Summary{P3} += $MonthData{P3};
        $Summary{P4} += $MonthData{P4};
    }

    # Calculate weighted average
    if ( @MonthlyBreakdown ) {
        my $TotalMTRD = 0;
        my $Count = 0;
        for my $Month (@MonthlyBreakdown) {
            if ( $Month->{Total} > 0 && $Month->{AverageMTRD} > 0 ) {
                $TotalMTRD += $Month->{AverageMTRD} * $Month->{Total};
                $Count += $Month->{Total};
            }
        }
        $Summary{AverageMTRD} = $Count > 0 ? int($TotalMTRD / $Count) : 0;
    }

    return (
        Year => $Param{Year},
        Quarter => $Param{Quarter},
        MonthlyBreakdown => \@MonthlyBreakdown,
        Summary => \%Summary,
    );
}

sub CalculateMTRDYearly {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    if ( !defined $Param{Year} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "CalculateMTRDYearly: Need Year!",
        );
        return;
    }

    # SQL for monthly breakdown for the year
    my $SQL = q{
        SELECT
            EXTRACT(MONTH FROM t.create_time) as month,
            COUNT(*) as total,
            AVG(CASE WHEN t.user_id IS NOT NULL
                THEN EXTRACT(EPOCH FROM (COALESCE(df_response.value_date, t.change_time) - t.create_time))
                END) as avg_mtrd_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        LEFT JOIN dynamic_field_value df_response
            ON df_response.object_id = t.id
            AND df_response.field_id = (SELECT id FROM dynamic_field WHERE name = 'Response')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND EXTRACT(YEAR FROM t.create_time) = ?
        GROUP BY EXTRACT(MONTH FROM t.create_time)
        ORDER BY month
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{Year} ],
    );

    my @MonthlyBreakdown;
    my %Summary = (
        Total => 0, AverageMTRD => 0,
        P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );

    my @MonthNames = qw(January February March April May June July August September October November December);

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %MonthData = (
            Month       => $Row[0],
            MonthName   => $MonthNames[$Row[0] - 1],
            Total       => $Row[1] || 0,
            AverageMTRD => int($Row[2] || 0),
            P1          => $Row[3] || 0,
            P2          => $Row[4] || 0,
            P3          => $Row[5] || 0,
            P4          => $Row[6] || 0,
        );
        push @MonthlyBreakdown, \%MonthData;

        $Summary{Total} += $MonthData{Total};
        $Summary{P1} += $MonthData{P1};
        $Summary{P2} += $MonthData{P2};
        $Summary{P3} += $MonthData{P3};
        $Summary{P4} += $MonthData{P4};
    }

    # Calculate weighted average
    if ( @MonthlyBreakdown ) {
        my $TotalMTRD = 0;
        my $Count = 0;
        for my $Month (@MonthlyBreakdown) {
            if ( $Month->{Total} > 0 && $Month->{AverageMTRD} > 0 ) {
                $TotalMTRD += $Month->{AverageMTRD} * $Month->{Total};
                $Count += $Month->{Total};
            }
        }
        $Summary{AverageMTRD} = $Count > 0 ? int($TotalMTRD / $Count) : 0;
    }

    return (
        Year => $Param{Year},
        MonthlyBreakdown => \@MonthlyBreakdown,
        Summary => \%Summary,
    );
}

sub CalculateMTTRDaily {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    if ( !$Param{SelectedDate} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "CalculateMTTRDaily: Need SelectedDate!",
        );
        return;
    }

    # SQL for hourly breakdown of resolved incidents
    my $SQL = q{
        SELECT
            EXTRACT(HOUR FROM t.create_time) as hour,
            COUNT(*) as total,
            AVG(EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 27
                       AND th.state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
                    ),
                    t.change_time
                ) - t.create_time
            ))) as avg_mttr_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.ticket_state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
        AND DATE(t.create_time) = DATE(?)
        GROUP BY EXTRACT(HOUR FROM t.create_time)
        ORDER BY hour
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{SelectedDate} ],
    );

    my @HourlyBreakdown;
    my %Summary = (
        Total => 0, AverageMTTR => 0,
        P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %HourData = (
            Hour        => $Row[0],
            Total       => $Row[1] || 0,
            AverageMTTR => int($Row[2] || 0),
            P1          => $Row[3] || 0,
            P2          => $Row[4] || 0,
            P3          => $Row[5] || 0,
            P4          => $Row[6] || 0,
        );
        push @HourlyBreakdown, \%HourData;

        # Accumulate summary
        $Summary{Total} += $HourData{Total};
        $Summary{P1} += $HourData{P1};
        $Summary{P2} += $HourData{P2};
        $Summary{P3} += $HourData{P3};
        $Summary{P4} += $HourData{P4};
    }

    # Calculate overall average MTTR for the day (weighted average)
    if ( @HourlyBreakdown ) {
        my $TotalMTTR = 0;
        my $Count = 0;
        for my $Hour (@HourlyBreakdown) {
            if ( $Hour->{Total} > 0 ) {
                $TotalMTTR += $Hour->{AverageMTTR} * $Hour->{Total};
                $Count += $Hour->{Total};
            }
        }
        $Summary{AverageMTTR} = $Count > 0 ? int($TotalMTTR / $Count) : 0;
    }

    return (
        Date => $Param{SelectedDate},
        HourlyBreakdown => \@HourlyBreakdown,
        Summary => \%Summary,
    );
}

sub CalculateMTTRWeekly {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "CalculateMTTRWeekly: Need $Needed!",
            );
            return;
        }
    }

    # SQL for daily breakdown of resolved incidents within the week
    my $SQL = q{
        SELECT
            TO_CHAR(t.create_time, 'Day') as weekday,
            EXTRACT(DOW FROM t.create_time) as day_number,
            DATE(t.create_time) as date,
            COUNT(*) as total,
            AVG(EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 27
                       AND th.state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
                    ),
                    t.change_time
                ) - t.create_time
            ))) as avg_mttr_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.ticket_state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
        AND t.create_time >= ?
        AND t.create_time < ? + INTERVAL '1 day'
        GROUP BY TO_CHAR(t.create_time, 'Day'), EXTRACT(DOW FROM t.create_time), DATE(t.create_time)
        ORDER BY day_number
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my @DailyBreakdown;
    my %Summary = (
        Total => 0, AverageMTTR => 0,
        P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %DayData = (
            Weekday     => $Row[0],
            DayNumber   => $Row[1],
            Date        => $Row[2],
            Total       => $Row[3] || 0,
            AverageMTTR => int($Row[4] || 0),
            P1          => $Row[5] || 0,
            P2          => $Row[6] || 0,
            P3          => $Row[7] || 0,
            P4          => $Row[8] || 0,
        );
        push @DailyBreakdown, \%DayData;

        $Summary{Total} += $DayData{Total};
        $Summary{P1} += $DayData{P1};
        $Summary{P2} += $DayData{P2};
        $Summary{P3} += $DayData{P3};
        $Summary{P4} += $DayData{P4};
    }

    # Calculate weighted average MTTR
    if ( @DailyBreakdown ) {
        my $TotalMTTR = 0;
        my $Count = 0;
        for my $Day (@DailyBreakdown) {
            if ( $Day->{Total} > 0 && $Day->{AverageMTTR} > 0 ) {
                $TotalMTTR += $Day->{AverageMTTR} * $Day->{Total};
                $Count += $Day->{Total};
            }
        }
        $Summary{AverageMTTR} = $Count > 0 ? int($TotalMTTR / $Count) : 0;
    }

    return (
        StartDate => $Param{StartDate},
        EndDate => $Param{EndDate},
        DailyBreakdown => \@DailyBreakdown,
        Summary => \%Summary,
    );
}

sub CalculateMTTRMonthly {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(Year Month)) {
        if ( !defined $Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "CalculateMTTRMonthly: Need $Needed!",
            );
            return;
        }
    }

    # SQL for weekly breakdown of resolved incidents within the month
    my $SQL = q{
        SELECT
            DATE_TRUNC('week', t.create_time) as week_start,
            COUNT(*) as total,
            AVG(EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 27
                       AND th.state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
                    ),
                    t.change_time
                ) - t.create_time
            ))) as avg_mttr_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.ticket_state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
        AND EXTRACT(YEAR FROM t.create_time) = ?
        AND EXTRACT(MONTH FROM t.create_time) = ?
        GROUP BY DATE_TRUNC('week', t.create_time)
        ORDER BY week_start
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{Year}, \$Param{Month} ],
    );

    my @WeeklyBreakdown;
    my %Summary = (
        Total => 0, AverageMTTR => 0,
        P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );
    my $WeekNumber = 1;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %WeekData = (
            WeekNumber  => $WeekNumber++,
            WeekStart   => $Row[0],
            Total       => $Row[1] || 0,
            AverageMTTR => int($Row[2] || 0),
            P1          => $Row[3] || 0,
            P2          => $Row[4] || 0,
            P3          => $Row[5] || 0,
            P4          => $Row[6] || 0,
        );
        push @WeeklyBreakdown, \%WeekData;

        $Summary{Total} += $WeekData{Total};
        $Summary{P1} += $WeekData{P1};
        $Summary{P2} += $WeekData{P2};
        $Summary{P3} += $WeekData{P3};
        $Summary{P4} += $WeekData{P4};
    }

    # Calculate weighted average
    if ( @WeeklyBreakdown ) {
        my $TotalMTTR = 0;
        my $Count = 0;
        for my $Week (@WeeklyBreakdown) {
            if ( $Week->{Total} > 0 && $Week->{AverageMTTR} > 0 ) {
                $TotalMTTR += $Week->{AverageMTTR} * $Week->{Total};
                $Count += $Week->{Total};
            }
        }
        $Summary{AverageMTTR} = $Count > 0 ? int($TotalMTTR / $Count) : 0;
    }

    return (
        Year => $Param{Year},
        Month => $Param{Month},
        WeeklyBreakdown => \@WeeklyBreakdown,
        Summary => \%Summary,
    );
}

sub CalculateMTTRQuarterly {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(Year Quarter)) {
        if ( !defined $Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "CalculateMTTRQuarterly: Need $Needed!",
            );
            return;
        }
    }

    # Calculate month range for quarter
    my $StartMonth = ($Param{Quarter} - 1) * 3 + 1;
    my $EndMonth = $StartMonth + 2;

    # SQL for monthly breakdown of resolved incidents within the quarter
    my $SQL = q{
        SELECT
            EXTRACT(MONTH FROM t.create_time) as month,
            COUNT(*) as total,
            AVG(EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 27
                       AND th.state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
                    ),
                    t.change_time
                ) - t.create_time
            ))) as avg_mttr_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.ticket_state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
        AND EXTRACT(YEAR FROM t.create_time) = ?
        AND EXTRACT(MONTH FROM t.create_time) BETWEEN ? AND ?
        GROUP BY EXTRACT(MONTH FROM t.create_time)
        ORDER BY month
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{Year}, \$StartMonth, \$EndMonth ],
    );

    my @MonthlyBreakdown;
    my %Summary = (
        Total => 0, AverageMTTR => 0,
        P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );

    my @MonthNames = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %MonthData = (
            Month       => $Row[0],
            MonthName   => $MonthNames[$Row[0] - 1],
            Total       => $Row[1] || 0,
            AverageMTTR => int($Row[2] || 0),
            P1          => $Row[3] || 0,
            P2          => $Row[4] || 0,
            P3          => $Row[5] || 0,
            P4          => $Row[6] || 0,
        );
        push @MonthlyBreakdown, \%MonthData;

        $Summary{Total} += $MonthData{Total};
        $Summary{P1} += $MonthData{P1};
        $Summary{P2} += $MonthData{P2};
        $Summary{P3} += $MonthData{P3};
        $Summary{P4} += $MonthData{P4};
    }

    # Calculate weighted average
    if ( @MonthlyBreakdown ) {
        my $TotalMTTR = 0;
        my $Count = 0;
        for my $Month (@MonthlyBreakdown) {
            if ( $Month->{Total} > 0 && $Month->{AverageMTTR} > 0 ) {
                $TotalMTTR += $Month->{AverageMTTR} * $Month->{Total};
                $Count += $Month->{Total};
            }
        }
        $Summary{AverageMTTR} = $Count > 0 ? int($TotalMTTR / $Count) : 0;
    }

    return (
        Year => $Param{Year},
        Quarter => $Param{Quarter},
        MonthlyBreakdown => \@MonthlyBreakdown,
        Summary => \%Summary,
    );
}

sub CalculateMTTRYearly {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    if ( !defined $Param{Year} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "CalculateMTTRYearly: Need Year!",
        );
        return;
    }

    # SQL for monthly breakdown of resolved incidents for the year
    my $SQL = q{
        SELECT
            EXTRACT(MONTH FROM t.create_time) as month,
            COUNT(*) as total,
            AVG(EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 27
                       AND th.state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
                    ),
                    t.change_time
                ) - t.create_time
            ))) as avg_mttr_seconds,
            COUNT(CASE WHEN tp.name = 'P1-Critical' THEN 1 END) as p1,
            COUNT(CASE WHEN tp.name = 'P2-High' THEN 1 END) as p2,
            COUNT(CASE WHEN tp.name = 'P3-Medium' THEN 1 END) as p3,
            COUNT(CASE WHEN tp.name = 'P4-Low' THEN 1 END) as p4
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.ticket_state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
        AND EXTRACT(YEAR FROM t.create_time) = ?
        GROUP BY EXTRACT(MONTH FROM t.create_time)
        ORDER BY month
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{Year} ],
    );

    my @MonthlyBreakdown;
    my %Summary = (
        Total => 0, AverageMTTR => 0,
        P1 => 0, P2 => 0, P3 => 0, P4 => 0,
    );

    my @MonthNames = qw(January February March April May June July August September October November December);

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %MonthData = (
            Month       => $Row[0],
            MonthName   => $MonthNames[$Row[0] - 1],
            Total       => $Row[1] || 0,
            AverageMTTR => int($Row[2] || 0),
            P1          => $Row[3] || 0,
            P2          => $Row[4] || 0,
            P3          => $Row[5] || 0,
            P4          => $Row[6] || 0,
        );
        push @MonthlyBreakdown, \%MonthData;

        $Summary{Total} += $MonthData{Total};
        $Summary{P1} += $MonthData{P1};
        $Summary{P2} += $MonthData{P2};
        $Summary{P3} += $MonthData{P3};
        $Summary{P4} += $MonthData{P4};
    }

    # Calculate weighted average
    if ( @MonthlyBreakdown ) {
        my $TotalMTTR = 0;
        my $Count = 0;
        for my $Month (@MonthlyBreakdown) {
            if ( $Month->{Total} > 0 && $Month->{AverageMTTR} > 0 ) {
                $TotalMTTR += $Month->{AverageMTTR} * $Month->{Total};
                $Count += $Month->{Total};
            }
        }
        $Summary{AverageMTTR} = $Count > 0 ? int($TotalMTTR / $Count) : 0;
    }

    return (
        Year => $Param{Year},
        MonthlyBreakdown => \@MonthlyBreakdown,
        Summary => \%Summary,
    );
}

sub GetMTRDTabularData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "GetMTRDTabularData: Need $Needed!",
            );
            return;
        }
    }

    # SQL for detailed incident list with MTRD
    my $SQL = q{
        SELECT
            t.tn as ticket_number,
            t.title,
            t.create_time as start_date,
            EXTRACT(EPOCH FROM (COALESCE(df_response.value_date, t.change_time) - t.create_time)) as mtrd_seconds,
            tp.name as priority,
            ts.name as status,
            CONCAT(u.first_name, ' ', u.last_name) as assigned_to,
            COALESCE(df_source.value_text, 'Unknown') as source
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_state ts ON t.ticket_state_id = ts.id
        LEFT JOIN users u ON t.user_id = u.id
        LEFT JOIN dynamic_field_value df_response
            ON df_response.object_id = t.id
            AND df_response.field_id = (SELECT id FROM dynamic_field WHERE name = 'Response')
        LEFT JOIN dynamic_field_value df_source
            ON df_source.object_id = t.id
            AND df_source.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.create_time >= ?
        AND t.create_time < ?
        ORDER BY t.create_time DESC
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my @TabularData;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $MTRDSeconds = $Row[3] || 0;
        my $MTRDHours = $MTRDSeconds / 3600;
        my $MTRDFormatted = sprintf("%.2f hours", $MTRDHours);

        push @TabularData, {
            TicketNumber   => $Row[0],
            Title          => $Row[1],
            StartDate      => $Row[2],
            MTRD           => int($MTRDSeconds),
            MTRDFormatted  => $MTRDFormatted,
            Priority       => $Row[4],
            Status         => $Row[5],
            AssignedTo     => $Row[6] || 'Unassigned',
            Source         => $Row[7],
        };
    }

    return @TabularData;
}

sub GetMTTRTabularData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "GetMTTRTabularData: Need $Needed!",
            );
            return;
        }
    }

    # SQL for detailed incident list with MTTR (resolved incidents only)
    my $SQL = q{
        SELECT
            t.tn as ticket_number,
            t.title,
            t.create_time as start_date,
            EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 27
                       AND th.state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
                    ),
                    t.change_time
                ) - t.create_time
            )) as mttr_seconds,
            tp.name as priority,
            ts.name as status,
            CONCAT(u.first_name, ' ', u.last_name) as assigned_to,
            COALESCE(df_source.value_text, 'Unknown') as source
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_state ts ON t.ticket_state_id = ts.id
        LEFT JOIN users u ON t.user_id = u.id
        LEFT JOIN dynamic_field_value df_source
            ON df_source.object_id = t.id
            AND df_source.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.ticket_state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
        AND t.create_time >= ?
        AND t.create_time < ? + INTERVAL '1 day'
        ORDER BY t.create_time DESC
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my @TabularData;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $MTTRSeconds = $Row[3] || 0;
        my $MTTRHours = $MTTRSeconds / 3600;
        my $MTTRFormatted = sprintf("%.2f hours", $MTTRHours);

        push @TabularData, {
            TicketNumber   => $Row[0],
            Title          => $Row[1],
            StartDate      => $Row[2],
            MTTR           => int($MTTRSeconds),
            MTTRFormatted  => $MTTRFormatted,
            Priority       => $Row[4],
            Status         => $Row[5],
            AssignedTo     => $Row[6] || 'Unassigned',
            Source         => $Row[7],
        };
    }

    return @TabularData;
}

sub GetAssignmentStats {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # SQL for assignment statistics
    my $SQL = q{
        SELECT
            COUNT(*) as total_incidents,
            COUNT(CASE WHEN t.user_id IS NOT NULL AND t.user_id NOT IN (1, 99) THEN 1 END) as assigned_count,
            COUNT(CASE WHEN t.user_id IS NULL OR t.user_id IN (1, 99) THEN 1 END) as unassigned_count
        FROM ticket t
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.create_time >= ?
        AND t.create_time < ?
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my %Stats = (
        TotalIncidents    => 0,
        AssignedCount     => 0,
        UnassignedCount   => 0,
        AssignmentRate    => 0,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Stats{TotalIncidents}  = $Row[0] || 0;
        $Stats{AssignedCount}   = $Row[1] || 0;
        $Stats{UnassignedCount} = $Row[2] || 0;
        $Stats{AssignmentRate}  = $Row[0] > 0 ? sprintf("%.1f", ($Row[1] / $Row[0]) * 100) : 0;
    }

    return %Stats;
}

sub CalculateMTTR {
    my ( $Self, %Param ) = @_;

    # Similar structure to CalculateMTRD
    # Implementation follows same pattern but calculates time to resolution

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $CacheObject  = $Kernel::OM->Get('Kernel::System::Cache');

    # Check required parameters
    for my $Needed (qw(StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "CalculateMTTR: Need $Needed!",
            );
            return;
        }
    }

    # Set defaults
    $Param{AggregationLevel} ||= 'daily';

    # Check cache first
    my $CacheEnabled = $ConfigObject->Get('OperationalKPIs::CacheEnabled');
    my $CacheKey;  # Declare outside if block so it's available throughout method

    if ($CacheEnabled) {
        $CacheKey = join '::', 'MTTR', $Param{StartDate}, $Param{EndDate},
            ($Param{Priority} || 'all'), ($Param{Source} || 'all'), $Param{AggregationLevel};

        my $Cached = $CacheObject->Get(
            Type => 'OperationalKPIs',
            Key  => $CacheKey,
        );
        return %{$Cached} if $Cached;
    }

    # Try cache table
    my %CacheResult = $Self->_GetFromCacheTable(
        ReportType       => 'mttr',
        StartDate        => $Param{StartDate},
        EndDate          => $Param{EndDate},
        Priority         => $Param{Priority},
        Source           => $Param{Source},
        AggregationLevel => $Param{AggregationLevel},
    );

    if (%CacheResult) {
        if ($CacheEnabled) {
            my $CacheTTL = $ConfigObject->Get('OperationalKPIs::CacheTTL') || 60;
            $CacheObject->Set(
                Type  => 'OperationalKPIs',
                Key   => $CacheKey,
                Value => \%CacheResult,
                TTL   => $CacheTTL * 60,
            );
        }
        return %CacheResult;
    }

    # Calculate from database
    my %Result = $Self->_CalculateMTTRFromDatabase(%Param);

    # Store in cache
    if ($CacheEnabled) {
        my $CacheTTL = $ConfigObject->Get('OperationalKPIs::CacheTTL') || 60;
        $CacheObject->Set(
            Type  => 'OperationalKPIs',
            Key   => $CacheKey,
            Value => \%Result,
            TTL   => $CacheTTL * 60,
        );
    }

    return %Result;
}

sub _CalculateMTTRFromDatabase {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Initialize result with default values
    my %Result = (
        ResolvedCount => 0,
        AverageMTTR   => 0,
    );

    # Log input parameters
    $LogObject->Log(
        Priority => 'notice',
        Message  => "_CalculateMTTRFromDatabase called with StartDate=$Param{StartDate}, EndDate=$Param{EndDate}, "
                   . "Priority=" . ($Param{Priority} || 'none') . ", Source=" . ($Param{Source} || 'none'),
    );

    # Build SQL query for MTTR calculation
    # MTTR = Time from creation to resolution (closed state)
    # Resolution time determined by (in priority order):
    # 1. First StateUpdate to closed state in ticket_history
    # 2. Ticket's current change_time as fallback
    my $SQL = q{
        SELECT
            COUNT(*) as total_resolved,
            AVG(EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 27
                       AND th.state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
                    ),
                    t.change_time
                ) - t.create_time
            ))) as avg_mttr_seconds
        FROM ticket t
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.ticket_state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
        AND t.create_time >= ?
        AND t.create_time < ?
    };

    my @Bind;

    # Add date range (use scalar references for Znuny DBI)
    push @Bind, \$Param{StartDate}, \$Param{EndDate};

    # Add filters
    if ( $Param{Priority} ) {
        $SQL .= " AND t.ticket_priority_id = (SELECT id FROM ticket_priority WHERE name = ?) ";
        push @Bind, \$Param{Priority};
    }

    if ( $Param{Source} ) {
        $SQL .= q{
            AND EXISTS (
                SELECT 1 FROM dynamic_field_value df_source
                WHERE df_source.object_id = t.id
                AND df_source.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
                AND df_source.value_text = ?
            )
        };
        push @Bind, \$Param{Source};
    }

    # Execute query
    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_CalculateMTTRFromDatabase: SQL Prepare failed for date range $Param{StartDate} to $Param{EndDate}",
        );
        return %Result;  # Return hash with zeros
    }

    # Fetch results
    my $RowCount = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $RowCount++;
        $Result{ResolvedCount} = $Row[0] || 0;
        $Result{AverageMTTR}   = int($Row[1] || 0);  # Convert to integer
    }

    # Log results
    $LogObject->Log(
        Priority => 'notice',
        Message  => "_CalculateMTTRFromDatabase: Fetched $RowCount row(s), ResolvedCount=$Result{ResolvedCount}, AverageMTTR=$Result{AverageMTTR}",
    );

    return %Result;
}

sub CalculateMTTRByPriority {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # SQL to get MTTR broken down by priority
    my $SQL = q{
        SELECT
            tp.name as priority_name,
            COUNT(*) as resolved_count,
            AVG(EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 27
                       AND th.state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
                    ),
                    t.change_time
                ) - t.create_time
            ))) as avg_mttr_seconds
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.ticket_state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
        AND t.create_time >= ?
        AND t.create_time < ?
        GROUP BY tp.name, tp.id
        ORDER BY tp.id
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my @Breakdown;
    my $TotalCount = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $TotalCount += $Row[1];
        push @Breakdown, {
            Priority    => $Row[0],
            Count       => $Row[1] || 0,
            AverageMTTR => int($Row[2] || 0),
        };
    }

    # Calculate percentages
    for my $Item (@Breakdown) {
        $Item->{Percentage} = $TotalCount > 0 ? sprintf("%.1f", ($Item->{Count} / $TotalCount) * 100) : 0;
    }

    return @Breakdown;
}

sub CalculateMTTRBySource {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # SQL to get MTTR broken down by source
    my $SQL = q{
        SELECT
            COALESCE(df_source.value_text, 'Unknown') as source,
            COUNT(*) as resolved_count,
            AVG(EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 27
                       AND th.state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
                    ),
                    t.change_time
                ) - t.create_time
            ))) as avg_mttr_seconds
        FROM ticket t
        LEFT JOIN dynamic_field_value df_source ON df_source.object_id = t.id
            AND df_source.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.ticket_state_id IN (SELECT id FROM ticket_state WHERE type_id = 3 AND name != 'cancelled')
        AND t.create_time >= ?
        AND t.create_time < ?
        GROUP BY df_source.value_text
        ORDER BY resolved_count DESC
    };

    return () if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my @Breakdown;
    my $TotalCount = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $TotalCount += $Row[1];
        push @Breakdown, {
            Source      => $Row[0],
            Count       => $Row[1] || 0,
            AverageMTTR => int($Row[2] || 0),
        };
    }

    # Calculate percentages
    for my $Item (@Breakdown) {
        $Item->{Percentage} = $TotalCount > 0 ? sprintf("%.1f", ($Item->{Count} / $TotalCount) * 100) : 0;
    }

    return @Breakdown;
}

sub GetIncidentTrends {
    my ( $Self, %Param ) = @_;

    # Implementation for incident trending patterns
    # This would analyze incident creation patterns over time

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');

    # Check required parameters
    for my $Needed (qw(StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "GetIncidentTrends: Need $Needed!",
            );
            return;
        }
    }

    # SQL to get incident counts by period
    my $SQL = q{
        SELECT
            DATE_TRUNC('day', t.create_time) as incident_date,
            COUNT(*) as incident_count,
            COUNT(CASE WHEN t.ticket_priority_id = (SELECT id FROM ticket_priority WHERE name = 'P1-Critical') THEN 1 END) as p1_count,
            COUNT(CASE WHEN t.ticket_priority_id = (SELECT id FROM ticket_priority WHERE name = 'P2-High') THEN 1 END) as p2_count,
            COUNT(CASE WHEN t.ticket_priority_id = (SELECT id FROM ticket_priority WHERE name = 'P3-Medium') THEN 1 END) as p3_count,
            COUNT(CASE WHEN t.ticket_priority_id = (SELECT id FROM ticket_priority WHERE name = 'P4-Low') THEN 1 END) as p4_count
        FROM ticket t
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.create_time >= ?
        AND t.create_time < ?
        GROUP BY DATE_TRUNC('day', t.create_time)
        ORDER BY incident_date
    };

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my @Trends;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Trends, {
            Date         => $Row[0],
            TotalCount   => $Row[1],
            PriorityBreakdown => {
                P1 => $Row[2] || 0,
                P2 => $Row[3] || 0,
                P3 => $Row[4] || 0,
                P4 => $Row[5] || 0,
            },
        };
    }

    return (
        Trends => \@Trends,
    );
}

sub GetMSIHandoverReport {
    my ( $Self, %Param ) = @_;

    # Implementation for MSI/ServiceNow handover statistics
    # This would analyze tickets that have been eBonded to ServiceNow

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $SQL = q{
        SELECT
            COUNT(*) as total_handovers,
            COUNT(CASE WHEN df_msi.value_text IS NOT NULL THEN 1 END) as successful_handovers,
            AVG(EXTRACT(EPOCH FROM (df_msi.create_time - t.create_time))) as avg_handover_time
        FROM ticket t
        LEFT JOIN dynamic_field_value df_msi ON df_msi.object_id = t.id
            AND df_msi.field_id = (SELECT id FROM dynamic_field WHERE name = 'MSITicketNumber')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
        AND t.create_time >= ?
        AND t.create_time < ?
    };

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Param{StartDate}, \$Param{EndDate} ],
    );

    my %Result;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Result{TotalHandovers}       = $Row[0] || 0;
        $Result{SuccessfulHandovers}  = $Row[1] || 0;
        $Result{AverageHandoverTime}  = $Row[2] || 0;
    }

    $Result{SuccessRate} = $Result{TotalHandovers} > 0
        ? ($Result{SuccessfulHandovers} / $Result{TotalHandovers}) * 100
        : 0;

    return %Result;
}

sub ExportToCSV {
    my ( $Self, %Param ) = @_;

    # Generate CSV content with UTF-8 BOM
    my $CSVContent = "\x{FEFF}";

    # Add headers based on report type
    if ( $Param{ReportType} eq 'mtrd' ) {
        $CSVContent .= "Period,Total Incidents,Avg MTRD (Hours),Priority\n";
    }
    elsif ( $Param{ReportType} eq 'mttr' ) {
        $CSVContent .= "Period,Total Resolved,Avg MTTR (Hours),Priority\n";
    }
    elsif ( $Param{ReportType} eq 'trends' ) {
        $CSVContent .= "Date,Total Incidents,P1-Critical,P2-High,P3-Medium,P4-Low\n";
    }

    # Add data rows
    if ( $Param{Data} && ref $Param{Data} eq 'HASH' ) {
        if ( $Param{ReportType} eq 'trends' && $Param{Data}->{Trends} ) {
            for my $Trend ( @{ $Param{Data}->{Trends} } ) {
                $CSVContent .= sprintf(
                    "%s,%d,%d,%d,%d,%d\n",
                    $Trend->{Date},
                    $Trend->{TotalCount},
                    $Trend->{PriorityBreakdown}->{P1},
                    $Trend->{PriorityBreakdown}->{P2},
                    $Trend->{PriorityBreakdown}->{P3},
                    $Trend->{PriorityBreakdown}->{P4},
                );
            }
        }
        # Add other report type handling...
    }

    return $CSVContent;
}

sub ExportToExcel {
    my ( $Self, %Param ) = @_;

    # This would require Excel::Writer::XLSX module
    # For now, return placeholder
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    $LogObject->Log(
        Priority => 'error',
        Message  => 'ExportToExcel: Excel export not yet implemented. Requires Excel::Writer::XLSX module.',
    );

    return;
}

sub _GetFromCacheTable {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $SQL = q{
        SELECT total_incidents, avg_mtrd_seconds, avg_mttr_seconds,
               assigned_count, unassigned_count, resolved_count
        FROM operational_kpis_cache
        WHERE report_type = ?
        AND aggregation_level = ?
        AND period_start >= ?
        AND period_end <= ?
        AND COALESCE(priority, '') = COALESCE(?, '')
        AND COALESCE(source, '') = COALESCE(?, '')
        ORDER BY created_time DESC
        LIMIT 1
    };

    my $ReportType = $Param{ReportType};
    my $AggregationLevel = $Param{AggregationLevel} || 'daily';
    my $StartDate = $Param{StartDate};
    my $EndDate = $Param{EndDate};
    my $Priority = $Param{Priority} || '';
    my $Source = $Param{Source} || '';

    my @Bind = (
        \$ReportType,
        \$AggregationLevel,
        \$StartDate,
        \$EndDate,
        \$Priority,
        \$Source,
    );

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my %Result;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Result{TotalIncidents} = $Row[0] || 0;
        $Result{AverageMTRD}    = $Row[1] || 0;
        $Result{AverageMTTR}    = $Row[2] || 0;
        $Result{AssignedCount}  = $Row[3] || 0;
        $Result{UnassignedCount}= $Row[4] || 0;
        $Result{ResolvedCount}  = $Row[5] || 0;
    }

    return %Result;
}

sub AggregateData {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');

    # Check required parameters
    for my $Needed (qw(ReportType StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "AggregateData: Need $Needed!",
            );
            return;
        }
    }

    # Calculate aggregations based on report type
    my %AggregatedData;
    if ( $Param{ReportType} eq 'mtrd' ) {
        %AggregatedData = $Self->_CalculateMTRDFromDatabase(%Param);
    }
    elsif ( $Param{ReportType} eq 'mttr' ) {
        %AggregatedData = $Self->_CalculateMTTRFromDatabase(%Param);
    }
    elsif ( $Param{ReportType} eq 'trends' ) {
        # Trends don't get cached, they're calculated on-demand
        # Just return success without storing anything
        return 1;
    }
    else {
        # Unknown report type - log error and return
        $LogObject->Log(
            Priority => 'error',
            Message  => "AggregateData: Unknown report type: " . ($Param{ReportType} || 'undef'),
        );
        return;
    }

    # Store in cache table
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $CurrentTime = $TimeObject->CurrentTimestamp();

    my $SQL = q{
        INSERT INTO operational_kpis_cache (
            report_type, aggregation_level, period_start, period_end,
            priority, source, product_cat_t2, product_cat_t3,
            total_incidents, avg_mtrd_seconds, avg_mttr_seconds,
            assigned_count, unassigned_count, resolved_count,
            created_time, create_time, create_by, change_time, change_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    };

    my $ReportType = $Param{ReportType};
    my $AggregationLevel = $Param{AggregationLevel} || 'daily';
    my $StartDate = $Param{StartDate};
    my $EndDate = $Param{EndDate};
    my $Priority = $Param{Priority} || '';
    my $Source = $Param{Source} || '';
    my $ProductCatT2 = $Param{ProductCatT2} || '';
    my $ProductCatT3 = $Param{ProductCatT3} || '';
    my $TotalIncidents = $AggregatedData{TotalIncidents} || 0;
    my $AverageMTRD = int($AggregatedData{AverageMTRD} || 0);  # Round to integer for database
    my $AverageMTTR = int($AggregatedData{AverageMTTR} || 0);  # Round to integer for database
    my $AssignedCount = $AggregatedData{AssignedCount} || 0;
    my $UnassignedCount = $AggregatedData{UnassignedCount} || 0;
    my $ResolvedCount = $AggregatedData{ResolvedCount} || 0;

    my @Bind = (
        \$ReportType,
        \$AggregationLevel,
        \$StartDate,
        \$EndDate,
        \$Priority,
        \$Source,
        \$ProductCatT2,
        \$ProductCatT3,
        \$TotalIncidents,
        \$AverageMTRD,
        \$AverageMTTR,
        \$AssignedCount,
        \$UnassignedCount,
        \$ResolvedCount,
        \$CurrentTime,
        \$CurrentTime,
        \1,
        \$CurrentTime,
        \1,
    );

    my $Success = $DBObject->Do(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    if ( !$Success ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'AggregateData: Failed to store aggregated data in cache table.',
        );
        return;
    }

    return 1;
}

=head2 AggregateAllData()

Main entry point called by Znuny daemon to aggregate all KPI data.
This method is automatically invoked by the SchedulerCronTaskManager.

    my $Success = $OperationalKPIsObject->AggregateAllData();

Returns:
    $Success = 1;       # or false in case of an error

=cut

sub AggregateAllData {
    my ( $Self, %Param ) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');

    # Check if module is enabled
    my $Enabled = $ConfigObject->Get('OperationalKPIs::Enabled');
    if ( !$Enabled ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'OperationalKPIs: Module is disabled, skipping aggregation.',
        );
        return 1;  # Return success to avoid error logs
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'OperationalKPIs: Starting automatic aggregation.',
    );

    # Calculate date ranges (default: last 7 days)
    my $Days = $Param{Days} || 7;
    my $CurrentTime = $TimeObject->SystemTime();
    my $EndDate = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $CurrentTime,
    );
    my $StartDate = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $CurrentTime - ( $Days * 24 * 3600 ),
    );

    # Debug: Print generated dates
    warn "=== AggregateAllData DEBUG ===\n";
    warn "StartDate: " . (defined($StartDate) ? "'$StartDate'" : "UNDEF") . "\n";
    warn "EndDate: " . (defined($EndDate) ? "'$EndDate'" : "UNDEF") . "\n";
    warn "==============================\n";

    my $HasErrors = 0;

    # Aggregate MTRD
    my $MTRDSuccess = $Self->AggregateData(
        ReportType => 'mtrd',
        StartDate  => $StartDate,
        EndDate    => $EndDate,
    );

    if ( !$MTRDSuccess ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'OperationalKPIs: Failed to aggregate MTRD data.',
        );
        $HasErrors = 1;
    }

    # Aggregate MTTR
    my $MTTRSuccess = $Self->AggregateData(
        ReportType => 'mttr',
        StartDate  => $StartDate,
        EndDate    => $EndDate,
    );

    if ( !$MTTRSuccess ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'OperationalKPIs: Failed to aggregate MTTR data.',
        );
        $HasErrors = 1;
    }

    # Note: Trends are calculated on-demand and not cached, so we don't aggregate them here

    if ($HasErrors) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'OperationalKPIs: Aggregation completed with errors. Check logs for details.',
        );
        return;
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'OperationalKPIs: Aggregation completed successfully.',
    );

    return 1;
}

# Chart Data Preparation Methods for D3/NVD3 Visualization

sub GetChartDataForDashboard {
    my ( $Self, %Param ) = @_;

    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $LogObject  = $Kernel::OM->Get('Kernel::System::Log');

    # Get current date
    my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
    my ($Year, $Month, $Day) = split /-/, $CurrentTimestamp;

    # Calculate 30 days ago
    my $StartTime = $TimeObject->TimeStamp2SystemTime(
        String => $CurrentTimestamp,
    ) - (30 * 86400);
    my $StartDateString = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $StartTime,
    );

    # Get trend data
    my %TrendData = $Self->GetIncidentTrends(
        StartDate => $StartDateString,
        EndDate   => $CurrentTimestamp,
    );

    # Prepare chart data structure
    my @ChartData;
    my $Total = 0;
    my @Values;

    if ( $TrendData{Trends} && ref $TrendData{Trends} eq 'ARRAY' ) {
        foreach my $Trend ( @{ $TrendData{Trends} } ) {
            my $count = $Trend->{TotalCount} || 0;
            push @Values, $count;
            $Total += $count;

            my %DataPoint = (
                date     => $Trend->{Date},
                count    => $count,
                p1       => $Trend->{PriorityBreakdown}->{P1} || 0,
                p2       => $Trend->{PriorityBreakdown}->{P2} || 0,
                p3       => $Trend->{PriorityBreakdown}->{P3} || 0,
                p4       => $Trend->{PriorityBreakdown}->{P4} || 0,
                isCurrent => 0,  # Will be set below
            );

            push @ChartData, \%DataPoint;
        }
    }

    # Calculate statistics
    my $average = @Values ? $Total / scalar(@Values) : 0;
    my $maxValue = @Values ? (sort { $b <=> $a } @Values)[0] : 0;

    # Identify current period (last 7 days) and anomalies
    my $currentPeriodStart = scalar(@ChartData) > 7 ? scalar(@ChartData) - 7 : 0;

    # Calculate standard deviation for anomaly detection
    my $stdDev = 0;
    if (@Values > 1) {
        my $sumSquares = 0;
        foreach my $val (@Values) {
            $sumSquares += ($val - $average) ** 2;
        }
        $stdDev = sqrt($sumSquares / scalar(@Values));
    }

    # Mark current period and anomalies
    for (my $i = 0; $i < scalar(@ChartData); $i++) {
        if ($i >= $currentPeriodStart) {
            $ChartData[$i]->{isCurrent} = 1;
        }

        # Detect anomalies (values > 2 standard deviations from mean)
        if ($stdDev > 0 && $ChartData[$i]->{count} > ($average + 2 * $stdDev)) {
            $ChartData[$i]->{isAnomaly} = 1;
            $ChartData[$i]->{anomalyLabel} = $ChartData[$i]->{count};
        }
    }

    return {
        data     => \@ChartData,
        average  => sprintf("%.1f", $average),
        maxValue => $maxValue,
        title    => "30-Day Incident Trends",
    };
}

sub GetPriorityBreakdownChartData {
    my ( $Self, %Param ) = @_;

    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # Get current month start/end timestamps
    my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
    my ($Year, $Month, $Day) = split /-/, $CurrentTimestamp;

    my $MonthStart = sprintf('%04d-%02d-01 00:00:00', $Year, $Month);
    my $MonthEnd = $CurrentTimestamp;

    # Count incidents by priority for current month
    my %PriorityCounts = (
        P1 => 0,
        P2 => 0,
        P3 => 0,
        P4 => 0,
    );

    # Map priority names to labels
    my %PriorityMap = (
        'P1-Critical' => 'P1',
        'P2-High'     => 'P2',
        'P3-Medium'   => 'P3',
        'P4-Low'      => 'P4',
    );

    # Search for incidents created in current month
    my @TicketIDs = $TicketObject->TicketSearch(
        Result           => 'ARRAY',
        TicketCreateTimeNewerDate => $MonthStart,
        TicketCreateTimeOlderDate => $MonthEnd,
        TypeIDs          => [2],  # Type 2 = Incident
        UserID           => 1,
    );

    # Count by priority
    foreach my $TicketID (@TicketIDs) {
        my %Ticket = $TicketObject->TicketGet(
            TicketID => $TicketID,
            UserID   => 1,
        );

        my $PriorityLabel = $PriorityMap{ $Ticket{Priority} } || 'P4';
        $PriorityCounts{$PriorityLabel}++;
    }

    # Prepare chart data
    my @ChartData;
    my $total = $PriorityCounts{P1} + $PriorityCounts{P2} + $PriorityCounts{P3} + $PriorityCounts{P4};

    # Create data point (single bar with stacked priorities)
    my %DataPoint = (
        label => "Current Month",
        p1    => $PriorityCounts{P1},
        p2    => $PriorityCounts{P2},
        p3    => $PriorityCounts{P3},
        p4    => $PriorityCounts{P4},
    );

    push @ChartData, \%DataPoint;

    return {
        data  => \@ChartData,
        total => $total,
        title => "Priority Breakdown - Current Month",
    };
}

sub GetMonthlyChartData {
    my ( $Self, %Param ) = @_;

    # For MTRD/MTTR monthly reports - weekly breakdown
    if ( !$Param{Year} || !$Param{Month} ) {
        return {};
    }

    my %MonthlyData = $Param{Type} eq 'MTTR'
        ? $Self->CalculateMTTRMonthly(
            Year  => $Param{Year},
            Month => $Param{Month},
        )
        : $Self->CalculateMTRDMonthly(
            Year  => $Param{Year},
            Month => $Param{Month},
        );

    my @ChartData;
    my @Values;
    my $Total = 0;

    if ( $MonthlyData{WeeklyBreakdown} ) {
        foreach my $Week ( @{ $MonthlyData{WeeklyBreakdown} } ) {
            my $avgValue = $Param{Type} eq 'MTTR'
                ? ($Week->{AverageMTTR} || 0)
                : ($Week->{AverageMTRD} || 0);

            my $avgHours = $avgValue / 3600;  # Convert seconds to hours
            push @Values, $avgHours;
            $Total += $avgHours;

            my %DataPoint = (
                date  => $Week->{WeekStart} || "Week " . $Week->{WeekNumber},
                count => sprintf("%.2f", $avgHours),
                label => "Week " . $Week->{WeekNumber},
            );

            push @ChartData, \%DataPoint;
        }
    }

    my $average = @Values ? $Total / scalar(@Values) : 0;
    my $maxValue = @Values ? (sort { $b <=> $a } @Values)[0] : 0;

    my $title = $Param{Type} eq 'MTTR'
        ? "MTTR Monthly Report - Weekly Breakdown"
        : "MTRD Monthly Report - Weekly Breakdown";

    return {
        data     => \@ChartData,
        average  => sprintf("%.2f", $average),
        maxValue => sprintf("%.2f", $maxValue),
        title    => $title,
    };
}

sub GetYearlyChartData {
    my ( $Self, %Param ) = @_;

    # For MTRD/MTTR yearly reports - monthly breakdown
    if ( !$Param{Year} ) {
        return {};
    }

    my %YearlyData = $Param{Type} eq 'MTTR'
        ? $Self->CalculateMTTRYearly(
            Year => $Param{Year},
        )
        : $Self->CalculateMTRDYearly(
            Year => $Param{Year},
        );

    my @ChartData;
    my @Values;
    my $Total = 0;
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
    my ($CurrentYear, $CurrentMonth) = split /-/, $CurrentTimestamp;

    my @MonthNames = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    if ( $YearlyData{MonthlyBreakdown} ) {
        foreach my $Month ( @{ $YearlyData{MonthlyBreakdown} } ) {
            my $avgValue = $Param{Type} eq 'MTTR'
                ? ($Month->{AverageMTTR} || 0)
                : ($Month->{AverageMTRD} || 0);

            my $avgHours = $avgValue / 3600;  # Convert seconds to hours
            push @Values, $avgHours;
            $Total += $avgHours;

            my $monthNum = $Month->{Month} || 0;
            my $isCurrent = ($Param{Year} == $CurrentYear && $monthNum == $CurrentMonth) ? 1 : 0;

            my %DataPoint = (
                date      => $Month->{MonthName} || $MonthNames[$monthNum - 1],
                count     => sprintf("%.2f", $avgHours),
                label     => $Month->{MonthName} || $MonthNames[$monthNum - 1],
                isCurrent => $isCurrent,
            );

            push @ChartData, \%DataPoint;
        }
    }

    my $average = @Values ? $Total / scalar(@Values) : 0;
    my $maxValue = @Values ? (sort { $b <=> $a } @Values)[0] : 0;

    my $title = $Param{Type} eq 'MTTR'
        ? "MTTR Yearly Report - Monthly Breakdown"
        : "MTRD Yearly Report - Monthly Breakdown";

    return {
        data     => \@ChartData,
        average  => sprintf("%.2f", $average),
        maxValue => sprintf("%.2f", $maxValue),
        title    => $title,
    };
}

=head2 GetActiveTicketsByAssignment()

Get active tickets grouped by priority and assignment state for a date range.

    my %Result = $OperationalKPIsObject->GetActiveTicketsByAssignment(
        StartDate => '2025-01-01 00:00:00',
        EndDate   => '2025-01-31 23:59:59',
    );

Returns hash with ByPriority and Summary data.

=cut

sub GetActiveTicketsByAssignment {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Validate required parameters
    for my $Needed (qw(StartDate EndDate)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "GetActiveTicketsByAssignment: Need $Needed!",
            );
            return {
                Error        => 1,
                ErrorMessage => "Missing required parameter: $Needed",
            };
        }
    }

    my $StartDate = $Param{StartDate};
    my $EndDate   = $Param{EndDate};

    # Query for active tickets grouped by priority and assignment state
    my $SQL = q{
        SELECT
            tp.name as priority,
            COUNT(CASE WHEN t.user_id IS NOT NULL AND t.user_id NOT IN (1, 99) THEN 1 END) as assigned,
            COUNT(CASE WHEN t.user_id IS NULL OR t.user_id IN (1, 99) THEN 1 END) as unassigned,
            COUNT(*) as total
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND t.ticket_state_id NOT IN (
              SELECT id FROM ticket_state WHERE type_id = 3
          )
          AND t.create_time >= ?
          AND t.create_time < ?
        GROUP BY tp.name, tp.id
        ORDER BY tp.id
    };

    my @Bind = ( \$StartDate, \$EndDate );

    my %ByPriority;
    my %Summary = (
        Total      => 0,
        Assigned   => 0,
        Unassigned => 0,
    );

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "GetActiveTicketsByAssignment: Database query failed",
        );
        return {
            Error        => 1,
            ErrorMessage => 'Database query failed',
        };
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $PriorityName = $Row[0];
        my $Assigned     = $Row[1] || 0;
        my $Unassigned   = $Row[2] || 0;
        my $Total        = $Row[3] || 0;

        # Calculate percentages
        my $AssignedPct   = $Total > 0 ? sprintf( "%.1f", ( $Assigned / $Total ) * 100 ) : 0;
        my $UnassignedPct = $Total > 0 ? sprintf( "%.1f", ( $Unassigned / $Total ) * 100 ) : 0;

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

    return {
        ByPriority => \%ByPriority,
        Summary    => \%Summary,
    };
}

=head2 GetAllActiveTicketsSummary()

Get all active tickets grouped by priority and assignment state (no date filter).

    my %Result = $OperationalKPIsObject->GetAllActiveTicketsSummary();

Returns hash with ByPriority, TotalAssigned, TotalUnassigned, GrandTotal.

=cut

sub GetAllActiveTicketsSummary {
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
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
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
            Message  => "GetAllActiveTicketsSummary: Database query failed",
        );
        return {
            Error        => 1,
            ErrorMessage => 'Database query failed',
        };
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $PriorityName = $Row[0];
        my $Assigned     = $Row[1] || 0;
        my $Unassigned   = $Row[2] || 0;
        my $Total        = $Row[3] || 0;

        # Calculate percentages
        my $AssignedPct   = $Total > 0 ? sprintf( "%.1f", ( $Assigned / $Total ) * 100 ) : 0;
        my $UnassignedPct = $Total > 0 ? sprintf( "%.1f", ( $Unassigned / $Total ) * 100 ) : 0;

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

    return {
        ByPriority      => \%ByPriority,
        TotalAssigned   => $Summary{Assigned},
        TotalUnassigned => $Summary{Unassigned},
        GrandTotal      => $Summary{Total},
    };
}

=head2 GetAverageBacklog()

Get average backlog age (days) for active tickets grouped by priority.

    my %Result = $OperationalKPIsObject->GetAverageBacklog();

Returns hash with ByPriority containing AvgDays and Count per priority.

=cut

sub GetAverageBacklog {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Query for average backlog (days since create_time) and count for active tickets grouped by priority
    my $SQL = q{
        SELECT
            tp.name as priority,
            ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - t.create_time)) / 86400)) as avg_days,
            COUNT(*) as ticket_count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND t.ticket_state_id NOT IN (
              SELECT id FROM ticket_state WHERE type_id = 3
          )
        GROUP BY tp.name, tp.id
        ORDER BY tp.id
    };

    my %ByPriority;
    my $TotalDays  = 0;
    my $TotalCount = 0;

    if ( !$DBObject->Prepare( SQL => $SQL ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "GetAverageBacklog: Database query failed",
        );
        return {
            Error        => 1,
            ErrorMessage => 'Database query failed',
        };
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $PriorityName = $Row[0];
        my $AvgDays      = $Row[1] || 0;
        my $Count        = $Row[2] || 0;

        $ByPriority{$PriorityName} = {
            AvgDays => $AvgDays,
            Count   => $Count,
        };

        # Accumulate for weighted average calculation
        $TotalDays  += $AvgDays * $Count;
        $TotalCount += $Count;
    }

    # Calculate overall weighted average
    my $OverallAvgDays = $TotalCount > 0 ? sprintf( "%.0f", $TotalDays / $TotalCount ) : 0;

    return {
        ByPriority     => \%ByPriority,
        OverallAvgDays => $OverallAvgDays,
        TotalCount     => $TotalCount,
    };
}

1;