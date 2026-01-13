# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentIncidentReports;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::IncidentKPIs',
    'Kernel::System::Time',
    'Kernel::System::Log',
    'Kernel::System::JSON',
    'Kernel::System::Group',
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
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');

    # Get parameters
    my %GetParam;
    for my $Param (qw(Subaction Tab Date Week Month Year Quarter StartYear EndYear StartMonth EndMonth Section)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Handle AJAX requests for tab data (Creation)
    if ( $GetParam{Subaction} eq 'GetTabData' ) {
        return $Self->_GetTabDataJSON(%GetParam);
    }

    # Handle AJAX requests for closure tab data
    if ( $GetParam{Subaction} eq 'GetClosureTabData' ) {
        return $Self->_GetClosureTabDataJSON(%GetParam);
    }

    # Handle AJAX requests for closure by ProductCat3 tab data
    if ( $GetParam{Subaction} eq 'GetClosureByProductCat3TabData' ) {
        return $Self->_GetClosureByProductCat3TabDataJSON(%GetParam);
    }

    # Handle AJAX requests for closure by CI tab data
    if ( $GetParam{Subaction} eq 'GetClosureByCITabData' ) {
        return $Self->_GetClosureByCITabDataJSON(%GetParam);
    }

    # Determine which section to show
    my $Section = $GetParam{Section} || 'TicketsCreation';

    # Select template based on section
    my $TemplateFile = 'AgentIncidentReports';
    if ( $Section eq 'TicketsClosure' ) {
        $TemplateFile = 'AgentIncidentReportsClosure';
    }
    elsif ( $Section eq 'TicketsClosureByProductCat3' ) {
        $TemplateFile = 'AgentIncidentReportsClosureByProductCat3';
    }
    elsif ( $Section eq 'TicketsClosureByCI' ) {
        $TemplateFile = 'AgentIncidentReportsClosureByCI';
    }

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Incident Reports',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => $TemplateFile,
        Data         => {
            Section => $Section,
        },
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetTabDataJSON {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    my $Tab = $Param{Tab} || 'hourly';

    # Route to appropriate tab handler
    my %Data;
    if ( $Tab eq 'hourly' ) {
        %Data = $Self->_GetHourlyData(%Param);
    }
    elsif ( $Tab eq 'daily' ) {
        %Data = $Self->_GetDailyData(%Param);
    }
    elsif ( $Tab eq 'weekly' ) {
        %Data = $Self->_GetWeeklyData(%Param);
    }
    elsif ( $Tab eq 'monthly' ) {
        %Data = $Self->_GetMonthlyData(%Param);
    }
    elsif ( $Tab eq 'quarterly' ) {
        %Data = $Self->_GetQuarterlyData(%Param);
    }
    elsif ( $Tab eq 'yearly' ) {
        %Data = $Self->_GetYearlyData(%Param);
    }
    else {
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=utf-8',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    ErrorMessage => "Invalid tab: $Tab",
                }
            ),
        );
    }

    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success => 1,
                Data    => \%Data,
            }
        ),
    );
}

sub _GetClosureTabDataJSON {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    my $Tab = $Param{Tab} || 'hourly';

    # Route to appropriate closure tab handler
    my %Data;
    if ( $Tab eq 'hourly' ) {
        %Data = $Self->_GetHourlyClosureData(%Param);
    }
    elsif ( $Tab eq 'daily' ) {
        %Data = $Self->_GetDailyClosureData(%Param);
    }
    elsif ( $Tab eq 'weekly' ) {
        %Data = $Self->_GetWeeklyClosureData(%Param);
    }
    elsif ( $Tab eq 'monthly' ) {
        %Data = $Self->_GetMonthlyClosureData(%Param);
    }
    elsif ( $Tab eq 'quarterly' ) {
        %Data = $Self->_GetQuarterlyClosureData(%Param);
    }
    elsif ( $Tab eq 'yearly' ) {
        %Data = $Self->_GetYearlyClosureData(%Param);
    }
    else {
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=utf-8',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    ErrorMessage => "Invalid tab: $Tab",
                }
            ),
        );
    }

    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success => 1,
                Data    => \%Data,
            }
        ),
    );
}

sub _GetClosureByProductCat3TabDataJSON {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    my $Tab = $Param{Tab} || 'hourly';

    # Route to appropriate closure by ProductCat3 tab handler
    my %Data;
    if ( $Tab eq 'hourly' ) {
        %Data = $Self->_GetHourlyClosureByProductCat3Data(%Param);
    }
    elsif ( $Tab eq 'daily' ) {
        %Data = $Self->_GetDailyClosureByProductCat3Data(%Param);
    }
    elsif ( $Tab eq 'weekly' ) {
        %Data = $Self->_GetWeeklyClosureByProductCat3Data(%Param);
    }
    elsif ( $Tab eq 'monthly' ) {
        %Data = $Self->_GetMonthlyClosureByProductCat3Data(%Param);
    }
    elsif ( $Tab eq 'quarterly' ) {
        %Data = $Self->_GetQuarterlyClosureByProductCat3Data(%Param);
    }
    elsif ( $Tab eq 'yearly' ) {
        %Data = $Self->_GetYearlyClosureByProductCat3Data(%Param);
    }
    else {
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=utf-8',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    ErrorMessage => "Invalid tab: $Tab",
                }
            ),
        );
    }

    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success => 1,
                Data    => \%Data,
            }
        ),
    );
}

sub _GetHourlyData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Parse date parameter (YYYY-MM-DD)
    my $Date = $Param{Date} || '';
    if ( !$Date ) {
        my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
        ($Date) = split / /, $CurrentTimestamp;
    }

    my $StartDate = "$Date 00:00:00";
    my $EndDate = "$Date 23:59:59";

    # Query tickets created, grouped by hour and priority
    my $SQL = q{
        SELECT
            EXTRACT(HOUR FROM t.create_time) as hour,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(HOUR FROM t.create_time), tp.name, tp.id
        ORDER BY hour, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    # Initialize data structure for 24 hours
    my %HourData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    for my $hour (0..23) {
        my $HourStart = sprintf("%s %02d:00:00", $Date, $hour);
        my $HourEnd = sprintf("%s %02d:59:59", $Date, $hour);
        $HourData{$hour} = {
            Label => sprintf("%02d:00", $hour),
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => $HourStart,
            EndDate => $HourEnd,
        };
    }

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetHourlyData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Hour = int($Row[0]);
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        # Map priority to P1/P2/P3/P4
        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $HourData{$Hour} ) {
            $HourData{$Hour}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    # Convert to array
    my @Rows;
    for my $hour (sort { $a <=> $b } keys %HourData) {
        push @Rows, $HourData{$hour};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetDailyData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse week parameter (YYYY-WNN)
    my $Week = $Param{Week} || '';
    if ( !$Week || $Week !~ /^(\d{4})-W(\d+)$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my ($Year, $WeekNum) = ($1, $2);

    # Calculate date range for the week (Monday to Sunday)
    use POSIX qw(mktime);
    my $jan4 = mktime(0, 0, 0, 4, 0, $Year - 1900);
    my @jan4_date = localtime($jan4);
    my $jan4_dow = ($jan4_date[6] + 6) % 7;
    my $first_monday = $jan4 - ($jan4_dow * 86400);
    my $week_start = $first_monday + (($WeekNum - 1) * 7 * 86400);
    my $week_end = $week_start + (6 * 86400) + 86399;

    my @start_date = localtime($week_start);
    my @end_date = localtime($week_end);

    my $StartDate = sprintf("%04d-%02d-%02d 00:00:00",
        $start_date[5] + 1900, $start_date[4] + 1, $start_date[3]);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $end_date[5] + 1900, $end_date[4] + 1, $end_date[3]);

    # Query tickets created, grouped by date and priority
    my $SQL = q{
        SELECT
            DATE(t.create_time) as day,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY DATE(t.create_time), tp.name, tp.id
        ORDER BY day, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %DayData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    # Initialize 7 days
    for my $i (0..6) {
        my $day_epoch = $week_start + ($i * 86400);
        my @day_parts = localtime($day_epoch);
        my $day_str = sprintf("%04d-%02d-%02d",
            $day_parts[5] + 1900, $day_parts[4] + 1, $day_parts[3]);
        $DayData{$day_str} = {
            Label => $day_str,
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => "$day_str 00:00:00",
            EndDate => "$day_str 23:59:59",
        };
    }

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetDailyData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Day = $Row[0];
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $DayData{$Day} ) {
            $DayData{$Day}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $day (sort keys %DayData) {
        push @Rows, $DayData{$day};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetWeeklyData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse month parameter (YYYY-MM)
    my $Month = $Param{Month} || '';
    if ( !$Month || $Month !~ /^(\d{4})-(\d{2})$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my ($Year, $MonthNum) = ($1, $2);

    my $StartDate = "$Year-$MonthNum-01 00:00:00";

    # Calculate last day of month
    use POSIX qw(mktime);
    my $next_month = mktime(0, 0, 0, 1, $MonthNum, $Year - 1900);
    my @last_day = localtime($next_month - 86400);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $last_day[5] + 1900, $last_day[4] + 1, $last_day[3]);

    # Query tickets created, grouped by week and priority
    my $SQL = q{
        SELECT
            TO_CHAR(t.create_time, 'IYYY-"W"IW') as week,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY TO_CHAR(t.create_time, 'IYYY-"W"IW'), tp.name, tp.id
        ORDER BY week, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %WeekData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetWeeklyData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Week = $Row[0];
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( !exists $WeekData{$Week} ) {
            # Calculate week start/end from IYYY-WIW format
            my ($WeekStartDate, $WeekEndDate) = $Self->_GetWeekDateRange($Week);
            $WeekData{$Week} = {
                Label => $Week,
                P1 => 0,
                P2 => 0,
                P3 => 0,
                P4 => 0,
                StartDate => $WeekStartDate,
                EndDate => $WeekEndDate,
            };
        }

        if ( $PriorityKey ) {
            $WeekData{$Week}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $week (sort keys %WeekData) {
        push @Rows, $WeekData{$week};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetMonthlyData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $Year = $Param{Year} || '';
    my $StartMonth = $Param{StartMonth} || 1;
    my $EndMonth = $Param{EndMonth} || 12;

    if ( !$Year || $Year !~ /^\d{4}$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my $StartDate = sprintf("%04d-%02d-01 00:00:00", $Year, $StartMonth);

    # Calculate end date
    use POSIX qw(mktime);
    my $next_month = mktime(0, 0, 0, 1, $EndMonth, $Year - 1900);
    my @last_day = localtime($next_month - 86400);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $last_day[5] + 1900, $last_day[4] + 1, $last_day[3]);

    # Query tickets created, grouped by month and priority
    my $SQL = q{
        SELECT
            TO_CHAR(t.create_time, 'YYYY-MM') as month,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY TO_CHAR(t.create_time, 'YYYY-MM'), tp.name, tp.id
        ORDER BY month, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %MonthData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetMonthlyData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Month = $Row[0];
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( !exists $MonthData{$Month} ) {
            # Calculate month start/end from YYYY-MM format
            my ($MonthStartDate, $MonthEndDate) = $Self->_GetMonthDateRange($Month);
            $MonthData{$Month} = {
                Label => $Month,
                P1 => 0,
                P2 => 0,
                P3 => 0,
                P4 => 0,
                StartDate => $MonthStartDate,
                EndDate => $MonthEndDate,
            };
        }

        if ( $PriorityKey ) {
            $MonthData{$Month}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $month (sort keys %MonthData) {
        push @Rows, $MonthData{$month};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetQuarterlyData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $Year = $Param{Year} || '';
    if ( !$Year || $Year !~ /^\d{4}$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my $StartDate = "$Year-01-01 00:00:00";
    my $EndDate = "$Year-12-31 23:59:59";

    # Query tickets created, grouped by quarter and priority
    my $SQL = q{
        SELECT
            'Q' || EXTRACT(QUARTER FROM t.create_time) as quarter,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(QUARTER FROM t.create_time), tp.name, tp.id
        ORDER BY quarter, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %QuarterData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    # Initialize quarters with date ranges
    my %QuarterDates = (
        1 => { start => "$Year-01-01 00:00:00", end => "$Year-03-31 23:59:59" },
        2 => { start => "$Year-04-01 00:00:00", end => "$Year-06-30 23:59:59" },
        3 => { start => "$Year-07-01 00:00:00", end => "$Year-09-30 23:59:59" },
        4 => { start => "$Year-10-01 00:00:00", end => "$Year-12-31 23:59:59" },
    );
    for my $q (1..4) {
        $QuarterData{"Q$q"} = {
            Label => "Q$q",
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => $QuarterDates{$q}{start},
            EndDate => $QuarterDates{$q}{end},
        };
    }

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetQuarterlyData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Quarter = $Row[0];
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $QuarterData{$Quarter} ) {
            $QuarterData{$Quarter}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $quarter (sort keys %QuarterData) {
        push @Rows, $QuarterData{$quarter};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetYearlyData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $StartYear = $Param{StartYear} || '';
    my $EndYear = $Param{EndYear} || '';

    if ( !$StartYear || !$EndYear || $StartYear !~ /^\d{4}$/ || $EndYear !~ /^\d{4}$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my $StartDate = "$StartYear-01-01 00:00:00";
    my $EndDate = "$EndYear-12-31 23:59:59";

    # Query tickets created, grouped by year and priority
    my $SQL = q{
        SELECT
            EXTRACT(YEAR FROM t.create_time) as year,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(YEAR FROM t.create_time), tp.name, tp.id
        ORDER BY year, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %YearData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    # Initialize years with date ranges
    for my $y ($StartYear..$EndYear) {
        $YearData{$y} = {
            Label => "$y",
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => "$y-01-01 00:00:00",
            EndDate => "$y-12-31 23:59:59",
        };
    }

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetYearlyData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Year = int($Row[0]);
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $YearData{$Year} ) {
            $YearData{$Year}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $year (sort { $a <=> $b } keys %YearData) {
        push @Rows, $YearData{$year};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

# ============================================================================
# CLOSURE METHODS - Count tickets CLOSED (not cancelled)
# ============================================================================

sub _GetHourlyClosureData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Parse date parameter (YYYY-MM-DD)
    my $Date = $Param{Date} || '';
    if ( !$Date ) {
        my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
        ($Date) = split / /, $CurrentTimestamp;
    }

    my $StartDate = "$Date 00:00:00";
    my $EndDate = "$Date 23:59:59";

    # Query tickets CLOSED (resolved/closed but not cancelled), grouped by hour and priority
    # Uses ticket_history with state_id to find transitions to closed state type
    # Also checks that ticket is CURRENTLY in closed state (not reopened)
    my $SQL = q{
        SELECT
            EXTRACT(HOUR FROM th.create_time) as hour,
            tp.name as priority,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY EXTRACT(HOUR FROM th.create_time), tp.name, tp.id
        ORDER BY hour, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    # Initialize data structure for 24 hours
    my %HourData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    for my $hour (0..23) {
        my $HourStart = sprintf("%s %02d:00:00", $Date, $hour);
        my $HourEnd = sprintf("%s %02d:59:59", $Date, $hour);
        $HourData{$hour} = {
            Label => sprintf("%02d:00", $hour),
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => $HourStart,
            EndDate => $HourEnd,
        };
    }

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetHourlyClosureData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Hour = int($Row[0]);
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $HourData{$Hour} ) {
            $HourData{$Hour}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $hour (sort { $a <=> $b } keys %HourData) {
        push @Rows, $HourData{$hour};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetDailyClosureData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse week parameter (YYYY-WNN)
    my $Week = $Param{Week} || '';
    if ( !$Week || $Week !~ /^(\d{4})-W(\d+)$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my ($Year, $WeekNum) = ($1, $2);

    # Calculate date range for the week (Monday to Sunday)
    use POSIX qw(mktime);
    my $jan4 = mktime(0, 0, 0, 4, 0, $Year - 1900);
    my @jan4_date = localtime($jan4);
    my $jan4_dow = ($jan4_date[6] + 6) % 7;
    my $first_monday = $jan4 - ($jan4_dow * 86400);
    my $week_start = $first_monday + (($WeekNum - 1) * 7 * 86400);
    my $week_end = $week_start + (6 * 86400) + 86399;

    my @start_date = localtime($week_start);
    my @end_date = localtime($week_end);

    my $StartDate = sprintf("%04d-%02d-%02d 00:00:00",
        $start_date[5] + 1900, $start_date[4] + 1, $start_date[3]);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $end_date[5] + 1900, $end_date[4] + 1, $end_date[3]);

    # Query tickets CLOSED (resolved/closed but not cancelled), grouped by date and priority
    # Uses ticket_history with state_id to find transitions to closed state type
    my $SQL = q{
        SELECT
            DATE(th.create_time) as day,
            tp.name as priority,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY DATE(th.create_time), tp.name, tp.id
        ORDER BY day, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %DayData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    # Initialize 7 days
    for my $i (0..6) {
        my $day_epoch = $week_start + ($i * 86400);
        my @day_parts = localtime($day_epoch);
        my $day_str = sprintf("%04d-%02d-%02d",
            $day_parts[5] + 1900, $day_parts[4] + 1, $day_parts[3]);
        $DayData{$day_str} = {
            Label => $day_str,
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => "$day_str 00:00:00",
            EndDate => "$day_str 23:59:59",
        };
    }

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetDailyClosureData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Day = $Row[0];
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $DayData{$Day} ) {
            $DayData{$Day}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $day (sort keys %DayData) {
        push @Rows, $DayData{$day};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetWeeklyClosureData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse month parameter (YYYY-MM)
    my $Month = $Param{Month} || '';
    if ( !$Month || $Month !~ /^(\d{4})-(\d{2})$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my ($Year, $MonthNum) = ($1, $2);

    my $StartDate = "$Year-$MonthNum-01 00:00:00";

    # Calculate last day of month
    use POSIX qw(mktime);
    my $next_month = mktime(0, 0, 0, 1, $MonthNum, $Year - 1900);
    my @last_day = localtime($next_month - 86400);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $last_day[5] + 1900, $last_day[4] + 1, $last_day[3]);

    # Query tickets CLOSED (resolved/closed but not cancelled), grouped by week and priority
    # Uses ticket_history with state_id to find transitions to closed state type
    my $SQL = q{
        SELECT
            TO_CHAR(th.create_time, 'IYYY-"W"IW') as week,
            tp.name as priority,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY TO_CHAR(th.create_time, 'IYYY-"W"IW'), tp.name, tp.id
        ORDER BY week, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %WeekData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetWeeklyClosureData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Week = $Row[0];
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( !exists $WeekData{$Week} ) {
            my ($WeekStartDate, $WeekEndDate) = $Self->_GetWeekDateRange($Week);
            $WeekData{$Week} = {
                Label => $Week,
                P1 => 0,
                P2 => 0,
                P3 => 0,
                P4 => 0,
                StartDate => $WeekStartDate,
                EndDate => $WeekEndDate,
            };
        }

        if ( $PriorityKey ) {
            $WeekData{$Week}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $week (sort keys %WeekData) {
        push @Rows, $WeekData{$week};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetMonthlyClosureData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $Year = $Param{Year} || '';
    my $StartMonth = $Param{StartMonth} || 1;
    my $EndMonth = $Param{EndMonth} || 12;

    if ( !$Year || $Year !~ /^\d{4}$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my $StartDate = sprintf("%04d-%02d-01 00:00:00", $Year, $StartMonth);

    # Calculate end date
    use POSIX qw(mktime);
    my $next_month = mktime(0, 0, 0, 1, $EndMonth, $Year - 1900);
    my @last_day = localtime($next_month - 86400);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $last_day[5] + 1900, $last_day[4] + 1, $last_day[3]);

    # Query tickets CLOSED (resolved/closed but not cancelled), grouped by month and priority
    # Uses ticket_history with state_id to find transitions to closed state type
    my $SQL = q{
        SELECT
            TO_CHAR(th.create_time, 'YYYY-MM') as month,
            tp.name as priority,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY TO_CHAR(th.create_time, 'YYYY-MM'), tp.name, tp.id
        ORDER BY month, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %MonthData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    # Pre-initialize all months in the range
    for my $m ($StartMonth..$EndMonth) {
        my $MonthStr = sprintf("%04d-%02d", $Year, $m);
        my ($MonthStartDate, $MonthEndDate) = $Self->_GetMonthDateRange($MonthStr);
        $MonthData{$MonthStr} = {
            Label => $MonthStr,
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => $MonthStartDate,
            EndDate => $MonthEndDate,
        };
    }

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetMonthlyClosureData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Month = $Row[0];
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $MonthData{$Month} ) {
            $MonthData{$Month}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $month (sort keys %MonthData) {
        push @Rows, $MonthData{$month};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetQuarterlyClosureData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $Year = $Param{Year} || '';
    if ( !$Year || $Year !~ /^\d{4}$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my $StartDate = "$Year-01-01 00:00:00";
    my $EndDate = "$Year-12-31 23:59:59";

    # Query tickets CLOSED (resolved/closed but not cancelled), grouped by quarter and priority
    # Uses ticket_history with state_id to find transitions to closed state type
    my $SQL = q{
        SELECT
            'Q' || EXTRACT(QUARTER FROM th.create_time) as quarter,
            tp.name as priority,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY EXTRACT(QUARTER FROM th.create_time), tp.name, tp.id
        ORDER BY quarter, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %QuarterData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    # Initialize quarters with date ranges
    my %QuarterDates = (
        1 => { start => "$Year-01-01 00:00:00", end => "$Year-03-31 23:59:59" },
        2 => { start => "$Year-04-01 00:00:00", end => "$Year-06-30 23:59:59" },
        3 => { start => "$Year-07-01 00:00:00", end => "$Year-09-30 23:59:59" },
        4 => { start => "$Year-10-01 00:00:00", end => "$Year-12-31 23:59:59" },
    );
    for my $q (1..4) {
        $QuarterData{"Q$q"} = {
            Label => "Q$q",
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => $QuarterDates{$q}{start},
            EndDate => $QuarterDates{$q}{end},
        };
    }

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetQuarterlyClosureData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Quarter = $Row[0];
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $QuarterData{$Quarter} ) {
            $QuarterData{$Quarter}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $quarter (sort keys %QuarterData) {
        push @Rows, $QuarterData{$quarter};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetYearlyClosureData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $StartYear = $Param{StartYear} || '';
    my $EndYear = $Param{EndYear} || '';

    if ( !$StartYear || !$EndYear || $StartYear !~ /^\d{4}$/ || $EndYear !~ /^\d{4}$/ ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my $StartDate = "$StartYear-01-01 00:00:00";
    my $EndDate = "$EndYear-12-31 23:59:59";

    # Query tickets CLOSED (resolved/closed but not cancelled), grouped by year and priority
    # Uses ticket_history with state_id to find transitions to closed state type
    my $SQL = q{
        SELECT
            EXTRACT(YEAR FROM th.create_time) as year,
            tp.name as priority,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY EXTRACT(YEAR FROM th.create_time), tp.name, tp.id
        ORDER BY year, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    my %YearData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    # Initialize years with date ranges
    for my $y ($StartYear..$EndYear) {
        $YearData{$y} = {
            Label => "$y",
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => "$y-01-01 00:00:00",
            EndDate => "$y-12-31 23:59:59",
        };
    }

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetYearlyClosureData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Year = int($Row[0]);
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $YearData{$Year} ) {
            $YearData{$Year}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    my @Rows;
    for my $year (sort { $a <=> $b } keys %YearData) {
        push @Rows, $YearData{$year};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

# ============================================================================
# CLOSURE BY PRODUCTCAT3 METHODS - Count tickets CLOSED grouped by ProductCat3
# ============================================================================

sub _GetHourlyClosureByProductCat3Data {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Parse date parameter (YYYY-MM-DD)
    my $Date = $Param{Date} || '';
    if ( !$Date ) {
        my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
        ($Date) = split / /, $CurrentTimestamp;
    }

    my $StartDate = "$Date 00:00:00";
    my $EndDate = "$Date 23:59:59";

    # Format date for display (e.g., "December 9, 2025")
    my @DateParts = split /-/, $Date;
    my @MonthNames = qw(January February March April May June July August September October November December);
    my $FilterDescription = sprintf("%s %d, %d (00:00 - 23:59)",
        $MonthNames[$DateParts[1] - 1], int($DateParts[2]), $DateParts[0]);

    # Build time periods (24 hours)
    my @TimePeriods;
    my %TimePeriodRanges;
    for my $Hour (0..23) {
        my $PeriodKey = sprintf("%02d", $Hour);
        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => sprintf("%s %02d:00:00", $Date, $Hour),
            EndDate   => sprintf("%s %02d:59:59", $Date, $Hour),
        };
    }

    # First query: Get top 10 categories by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetHourlyClosureByProductCat3Data: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $ProductCat3;
        $CategoryTotals{$ProductCat3} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by category AND hour
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            EXTRACT(HOUR FROM th.create_time)::int as hour,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(HOUR FROM th.create_time)
        ORDER BY dfv.value_text, hour
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetHourlyClosureByProductCat3Data: Breakdown query failed",
        );
        # Return with totals only
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $Hour = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$ProductCat3};

        my $PeriodKey = sprintf("%02d", $Hour);
        $BreakdownData{$ProductCat3}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetDailyClosureByProductCat3Data {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse week parameter (YYYY-WNN)
    my $Week = $Param{Week} || '';
    if ( !$Week || $Week !~ /^(\d{4})-W(\d+)$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid week',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my ($Year, $WeekNum) = ($1, $2);

    # Calculate date range for the week (Monday to Sunday)
    use POSIX qw(mktime strftime);
    my $jan4 = mktime(0, 0, 0, 4, 0, $Year - 1900);
    my @jan4_date = localtime($jan4);
    my $jan4_dow = ($jan4_date[6] + 6) % 7;
    my $first_monday = $jan4 - ($jan4_dow * 86400);
    my $week_start = $first_monday + (($WeekNum - 1) * 7 * 86400);
    my $week_end = $week_start + (6 * 86400) + 86399;

    my @start_date = localtime($week_start);
    my @end_date = localtime($week_end);

    my $StartDate = sprintf("%04d-%02d-%02d 00:00:00",
        $start_date[5] + 1900, $start_date[4] + 1, $start_date[3]);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $end_date[5] + 1900, $end_date[4] + 1, $end_date[3]);

    # Format filter description (e.g., "Week 50, 2025 (Dec 9 - Dec 15)")
    my @MonthAbbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my $FilterDescription = sprintf("Week %d, %d (%s %d - %s %d)",
        $WeekNum, $Year,
        $MonthAbbr[$start_date[4]], $start_date[3],
        $MonthAbbr[$end_date[4]], $end_date[3]);

    # Build time periods (7 days with actual dates)
    my @TimePeriods;
    my %TimePeriodRanges;
    my %DateToKey;  # Map date string to period key

    for my $DayOffset (0..6) {
        my $DayEpoch = $week_start + ($DayOffset * 86400);
        my @DayDate = localtime($DayEpoch);
        my $DateStr = sprintf("%04d-%02d-%02d",
            $DayDate[5] + 1900, $DayDate[4] + 1, $DayDate[3]);
        my $PeriodKey = sprintf("%s %d", $MonthAbbr[$DayDate[4]], $DayDate[3]);

        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => "$DateStr 00:00:00",
            EndDate   => "$DateStr 23:59:59",
        };
        $DateToKey{$DateStr} = $PeriodKey;
    }

    # First query: Get top 10 categories by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetDailyClosureByProductCat3Data: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $ProductCat3;
        $CategoryTotals{$ProductCat3} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by category AND date
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            DATE(th.create_time)::text as close_date,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, DATE(th.create_time)
        ORDER BY dfv.value_text, close_date
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetDailyClosureByProductCat3Data: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $DateStr = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$ProductCat3};

        # Map date to period key
        my $PeriodKey = $DateToKey{$DateStr};
        next if !$PeriodKey;

        $BreakdownData{$ProductCat3}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetWeeklyClosureByProductCat3Data {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse month parameter (YYYY-MM)
    my $Month = $Param{Month} || '';
    if ( !$Month || $Month !~ /^(\d{4})-(\d{2})$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid month',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my ($Year, $MonthNum) = ($1, $2);

    my $StartDate = "$Year-$MonthNum-01 00:00:00";

    # Calculate last day of month
    use POSIX qw(mktime);
    my $next_month = mktime(0, 0, 0, 1, $MonthNum, $Year - 1900);
    my @last_day = localtime($next_month - 86400);
    my $LastDay = $last_day[3];
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59", $Year, $MonthNum, $LastDay);

    # Format filter description (e.g., "December 2025")
    my @MonthNames = qw(January February March April May June July August September October November December);
    my $FilterDescription = sprintf("%s %d", $MonthNames[$MonthNum - 1], $Year);

    # Build time periods using actual ISO week numbers
    my @TimePeriods;
    my %TimePeriodRanges;
    my %SeenWeeks;  # Track unique ISO weeks

    # Iterate through all days in the month to find ISO week numbers
    for my $Day (1..$LastDay) {
        my $DayEpoch = mktime(0, 0, 12, $Day, $MonthNum - 1, $Year - 1900);
        my @DayDate = localtime($DayEpoch);

        # Calculate ISO week number
        # Using strftime %V for ISO week number
        my $ISOWeek = POSIX::strftime("%V", @DayDate);
        $ISOWeek = int($ISOWeek);  # Remove leading zero

        next if $SeenWeeks{$ISOWeek};  # Skip if we've already processed this week
        $SeenWeeks{$ISOWeek} = 1;

        my $PeriodKey = "Week $ISOWeek";

        # Calculate the start and end of this ISO week within the month
        # Find first day of this week in the month
        my $WeekStartDay = $Day;
        for my $d (1..$Day-1) {
            my $de = mktime(0, 0, 12, $d, $MonthNum - 1, $Year - 1900);
            my @dd = localtime($de);
            my $dw = int(POSIX::strftime("%V", @dd));
            if ($dw == $ISOWeek && $d < $WeekStartDay) {
                $WeekStartDay = $d;
            }
        }

        # Find last day of this week in the month
        my $WeekEndDay = $Day;
        for my $d ($Day..$LastDay) {
            my $de = mktime(0, 0, 12, $d, $MonthNum - 1, $Year - 1900);
            my @dd = localtime($de);
            my $dw = int(POSIX::strftime("%V", @dd));
            if ($dw == $ISOWeek) {
                $WeekEndDay = $d;
            }
        }

        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => sprintf("%04d-%02d-%02d 00:00:00", $Year, $MonthNum, $WeekStartDay),
            EndDate   => sprintf("%04d-%02d-%02d 23:59:59", $Year, $MonthNum, $WeekEndDay),
        };
    }

    # Sort TimePeriods by week number
    @TimePeriods = sort {
        my ($a_num) = $a =~ /Week (\d+)/;
        my ($b_num) = $b =~ /Week (\d+)/;
        $a_num <=> $b_num;
    } @TimePeriods;

    # First query: Get top 10 categories by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetWeeklyClosureByProductCat3Data: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $ProductCat3;
        $CategoryTotals{$ProductCat3} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by category AND ISO week number
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            EXTRACT(WEEK FROM th.create_time)::int as week_num,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(WEEK FROM th.create_time)
        ORDER BY dfv.value_text, week_num
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetWeeklyClosureByProductCat3Data: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $WeekNum = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$ProductCat3};

        my $PeriodKey = "Week $WeekNum";
        next if !exists $TimePeriodRanges{$PeriodKey};

        $BreakdownData{$ProductCat3}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetMonthlyClosureByProductCat3Data {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $Year = $Param{Year} || '';
    my $StartMonth = $Param{StartMonth} || 1;
    my $EndMonth = $Param{EndMonth} || 12;

    if ( !$Year || $Year !~ /^\d{4}$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid year',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my $StartDate = sprintf("%04d-%02d-01 00:00:00", $Year, $StartMonth);

    # Calculate end date
    use POSIX qw(mktime);
    my $next_month = mktime(0, 0, 0, 1, $EndMonth, $Year - 1900);
    my @last_day = localtime($next_month - 86400);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $last_day[5] + 1900, $last_day[4] + 1, $last_day[3]);

    # Format filter description (e.g., "Jan - Dec 2025" or "Mar - Jun 2025")
    my @MonthAbbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my $FilterDescription = sprintf("%s - %s %d",
        $MonthAbbr[$StartMonth - 1], $MonthAbbr[$EndMonth - 1], $Year);

    # Build time periods (months in the range)
    my @TimePeriods;
    my %TimePeriodRanges;

    for my $MonthNum ($StartMonth..$EndMonth) {
        my $PeriodKey = $MonthAbbr[$MonthNum - 1];

        # Calculate last day of this month
        my $month_next = mktime(0, 0, 0, 1, $MonthNum, $Year - 1900);
        my @month_last = localtime($month_next - 86400);
        my $LastDayOfMonth = $month_last[3];

        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => sprintf("%04d-%02d-01 00:00:00", $Year, $MonthNum),
            EndDate   => sprintf("%04d-%02d-%02d 23:59:59", $Year, $MonthNum, $LastDayOfMonth),
        };
    }

    # First query: Get top 10 categories by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetMonthlyClosureByProductCat3Data: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $ProductCat3;
        $CategoryTotals{$ProductCat3} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by category AND month
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            EXTRACT(MONTH FROM th.create_time)::int as month_num,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(MONTH FROM th.create_time)
        ORDER BY dfv.value_text, month_num
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetMonthlyClosureByProductCat3Data: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $MonthNum = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$ProductCat3};

        my $PeriodKey = $MonthAbbr[$MonthNum - 1];
        next if !exists $TimePeriodRanges{$PeriodKey};

        $BreakdownData{$ProductCat3}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetQuarterlyClosureByProductCat3Data {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $Year = $Param{Year} || '';
    if ( !$Year || $Year !~ /^\d{4}$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid year',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my $StartDate = "$Year-01-01 00:00:00";
    my $EndDate = "$Year-12-31 23:59:59";

    # Format filter description (e.g., "Year 2025")
    my $FilterDescription = "Year $Year";

    # Build time periods (4 quarters)
    my @TimePeriods = ('Q1', 'Q2', 'Q3', 'Q4');
    my %TimePeriodRanges = (
        'Q1' => { StartDate => "$Year-01-01 00:00:00", EndDate => "$Year-03-31 23:59:59" },
        'Q2' => { StartDate => "$Year-04-01 00:00:00", EndDate => "$Year-06-30 23:59:59" },
        'Q3' => { StartDate => "$Year-07-01 00:00:00", EndDate => "$Year-09-30 23:59:59" },
        'Q4' => { StartDate => "$Year-10-01 00:00:00", EndDate => "$Year-12-31 23:59:59" },
    );

    # First query: Get top 10 categories by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetQuarterlyClosureByProductCat3Data: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $ProductCat3;
        $CategoryTotals{$ProductCat3} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by category AND quarter
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            EXTRACT(QUARTER FROM th.create_time)::int as quarter,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(QUARTER FROM th.create_time)
        ORDER BY dfv.value_text, quarter
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetQuarterlyClosureByProductCat3Data: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $Quarter = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$ProductCat3};

        my $PeriodKey = "Q$Quarter";
        next if !exists $TimePeriodRanges{$PeriodKey};

        $BreakdownData{$ProductCat3}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetYearlyClosureByProductCat3Data {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $StartYear = $Param{StartYear} || '';
    my $EndYear = $Param{EndYear} || '';

    if ( !$StartYear || !$EndYear || $StartYear !~ /^\d{4}$/ || $EndYear !~ /^\d{4}$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid year range',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my $StartDate = "$StartYear-01-01 00:00:00";
    my $EndDate = "$EndYear-12-31 23:59:59";

    # Format filter description (e.g., "2020 - 2025")
    my $FilterDescription = "$StartYear - $EndYear";

    # Build time periods (years in the range)
    my @TimePeriods;
    my %TimePeriodRanges;

    for my $YearNum ($StartYear..$EndYear) {
        my $PeriodKey = "$YearNum";
        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => "$YearNum-01-01 00:00:00",
            EndDate   => "$YearNum-12-31 23:59:59",
        };
    }

    # First query: Get top 10 categories by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetYearlyClosureByProductCat3Data: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $ProductCat3;
        $CategoryTotals{$ProductCat3} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by category AND year
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as product_cat3,
            EXTRACT(YEAR FROM th.create_time)::int as year,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat3')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(YEAR FROM th.create_time)
        ORDER BY dfv.value_text, year
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetYearlyClosureByProductCat3Data: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $ProductCat3 = $Row[0] || 'Unknown';
        my $YearNum = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$ProductCat3};

        my $PeriodKey = "$YearNum";
        next if !exists $TimePeriodRanges{$PeriodKey};

        $BreakdownData{$ProductCat3}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

# ============================================================================
# CLOSURE BY CI METHODS - Count tickets CLOSED grouped by CI
# ============================================================================

sub _GetClosureByCITabDataJSON {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    my $Tab = $Param{Tab} || 'hourly';

    # Route to appropriate closure by CI tab handler
    my %Data;
    if ( $Tab eq 'hourly' ) {
        %Data = $Self->_GetHourlyClosureByCIData(%Param);
    }
    elsif ( $Tab eq 'daily' ) {
        %Data = $Self->_GetDailyClosureByCIData(%Param);
    }
    elsif ( $Tab eq 'weekly' ) {
        %Data = $Self->_GetWeeklyClosureByCIData(%Param);
    }
    elsif ( $Tab eq 'monthly' ) {
        %Data = $Self->_GetMonthlyClosureByCIData(%Param);
    }
    elsif ( $Tab eq 'quarterly' ) {
        %Data = $Self->_GetQuarterlyClosureByCIData(%Param);
    }
    elsif ( $Tab eq 'yearly' ) {
        %Data = $Self->_GetYearlyClosureByCIData(%Param);
    }
    else {
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=utf-8',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    ErrorMessage => "Invalid tab: $Tab",
                }
            ),
        );
    }

    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success => 1,
                Data    => \%Data,
            }
        ),
    );
}

sub _GetHourlyClosureByCIData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Parse date parameter (YYYY-MM-DD)
    my $Date = $Param{Date} || '';
    if ( !$Date ) {
        my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
        ($Date) = split / /, $CurrentTimestamp;
    }

    my $StartDate = "$Date 00:00:00";
    my $EndDate = "$Date 23:59:59";

    # Format date for display (e.g., "December 9, 2025")
    my @DateParts = split /-/, $Date;
    my @MonthNames = qw(January February March April May June July August September October November December);
    my $FilterDescription = sprintf("%s %d, %d (00:00 - 23:59)",
        $MonthNames[$DateParts[1] - 1], int($DateParts[2]), $DateParts[0]);

    # Build time periods (24 hours)
    my @TimePeriods;
    my %TimePeriodRanges;
    for my $Hour (0..23) {
        my $PeriodKey = sprintf("%02d", $Hour);
        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => sprintf("%s %02d:00:00", $Date, $Hour),
            EndDate   => sprintf("%s %02d:59:59", $Date, $Hour),
        };
    }

    # First query: Get top 10 CIs by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetHourlyClosureByCIData: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $CI;
        $CategoryTotals{$CI} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by CI AND hour
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            EXTRACT(HOUR FROM th.create_time)::int as hour,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(HOUR FROM th.create_time)
        ORDER BY dfv.value_text, hour
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetHourlyClosureByCIData: Breakdown query failed",
        );
        # Return with totals only
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $Hour = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$CI};

        my $PeriodKey = sprintf("%02d", $Hour);
        $BreakdownData{$CI}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetDailyClosureByCIData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse week parameter (YYYY-WNN)
    my $Week = $Param{Week} || '';
    if ( !$Week || $Week !~ /^(\d{4})-W(\d+)$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid week',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my ($Year, $WeekNum) = ($1, $2);

    # Calculate date range for the week (Monday to Sunday)
    use POSIX qw(mktime strftime);
    my $jan4 = mktime(0, 0, 0, 4, 0, $Year - 1900);
    my @jan4_date = localtime($jan4);
    my $jan4_dow = ($jan4_date[6] + 6) % 7;
    my $first_monday = $jan4 - ($jan4_dow * 86400);
    my $week_start = $first_monday + (($WeekNum - 1) * 7 * 86400);
    my $week_end = $week_start + (6 * 86400) + 86399;

    my @start_date = localtime($week_start);
    my @end_date = localtime($week_end);

    my $StartDate = sprintf("%04d-%02d-%02d 00:00:00",
        $start_date[5] + 1900, $start_date[4] + 1, $start_date[3]);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $end_date[5] + 1900, $end_date[4] + 1, $end_date[3]);

    # Format filter description (e.g., "Week 50, 2025 (Dec 9 - Dec 15)")
    my @MonthAbbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my $FilterDescription = sprintf("Week %d, %d (%s %d - %s %d)",
        $WeekNum, $Year,
        $MonthAbbr[$start_date[4]], $start_date[3],
        $MonthAbbr[$end_date[4]], $end_date[3]);

    # Build time periods (7 days with actual dates)
    my @TimePeriods;
    my %TimePeriodRanges;
    my %DateToKey;  # Map date string to period key

    for my $DayOffset (0..6) {
        my $DayEpoch = $week_start + ($DayOffset * 86400);
        my @DayDate = localtime($DayEpoch);
        my $DateStr = sprintf("%04d-%02d-%02d",
            $DayDate[5] + 1900, $DayDate[4] + 1, $DayDate[3]);
        my $PeriodKey = sprintf("%s %d", $MonthAbbr[$DayDate[4]], $DayDate[3]);

        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => "$DateStr 00:00:00",
            EndDate   => "$DateStr 23:59:59",
        };
        $DateToKey{$DateStr} = $PeriodKey;
    }

    # First query: Get top 10 CIs by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetDailyClosureByCIData: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $CI;
        $CategoryTotals{$CI} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by CI AND date
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            DATE(th.create_time)::text as close_date,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, DATE(th.create_time)
        ORDER BY dfv.value_text, close_date
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetDailyClosureByCIData: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $DateStr = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$CI};

        # Map date to period key
        my $PeriodKey = $DateToKey{$DateStr};
        next if !$PeriodKey;

        $BreakdownData{$CI}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetWeeklyClosureByCIData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse month parameter (YYYY-MM)
    my $Month = $Param{Month} || '';
    if ( !$Month || $Month !~ /^(\d{4})-(\d{2})$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid month',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my ($Year, $MonthNum) = ($1, $2);

    my $StartDate = "$Year-$MonthNum-01 00:00:00";

    # Calculate last day of month
    use POSIX qw(mktime);
    my $next_month = mktime(0, 0, 0, 1, $MonthNum, $Year - 1900);
    my @last_day = localtime($next_month - 86400);
    my $LastDay = $last_day[3];
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59", $Year, $MonthNum, $LastDay);

    # Format filter description (e.g., "December 2025")
    my @MonthNames = qw(January February March April May June July August September October November December);
    my $FilterDescription = sprintf("%s %d", $MonthNames[$MonthNum - 1], $Year);

    # Build time periods using actual ISO week numbers
    my @TimePeriods;
    my %TimePeriodRanges;
    my %SeenWeeks;  # Track unique ISO weeks

    # Iterate through all days in the month to find ISO week numbers
    for my $Day (1..$LastDay) {
        my $DayEpoch = mktime(0, 0, 12, $Day, $MonthNum - 1, $Year - 1900);
        my @DayDate = localtime($DayEpoch);

        # Calculate ISO week number using strftime %V
        my $ISOWeek = POSIX::strftime("%V", @DayDate);
        $ISOWeek = int($ISOWeek);  # Remove leading zero

        next if $SeenWeeks{$ISOWeek};  # Skip if we've already processed this week
        $SeenWeeks{$ISOWeek} = 1;

        my $PeriodKey = "Week $ISOWeek";

        # Calculate the start and end of this ISO week within the month
        my $WeekStartDay = $Day;
        for my $d (1..$Day-1) {
            my $de = mktime(0, 0, 12, $d, $MonthNum - 1, $Year - 1900);
            my @dd = localtime($de);
            my $dw = int(POSIX::strftime("%V", @dd));
            if ($dw == $ISOWeek && $d < $WeekStartDay) {
                $WeekStartDay = $d;
            }
        }

        my $WeekEndDay = $Day;
        for my $d ($Day..$LastDay) {
            my $de = mktime(0, 0, 12, $d, $MonthNum - 1, $Year - 1900);
            my @dd = localtime($de);
            my $dw = int(POSIX::strftime("%V", @dd));
            if ($dw == $ISOWeek) {
                $WeekEndDay = $d;
            }
        }

        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => sprintf("%04d-%02d-%02d 00:00:00", $Year, $MonthNum, $WeekStartDay),
            EndDate   => sprintf("%04d-%02d-%02d 23:59:59", $Year, $MonthNum, $WeekEndDay),
        };
    }

    # Sort TimePeriods by week number
    @TimePeriods = sort {
        my ($a_num) = $a =~ /Week (\d+)/;
        my ($b_num) = $b =~ /Week (\d+)/;
        $a_num <=> $b_num;
    } @TimePeriods;

    # First query: Get top 10 CIs by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetWeeklyClosureByCIData: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $CI;
        $CategoryTotals{$CI} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by CI AND ISO week number
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            EXTRACT(WEEK FROM th.create_time)::int as week_num,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(WEEK FROM th.create_time)
        ORDER BY dfv.value_text, week_num
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetWeeklyClosureByCIData: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $WeekNum = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$CI};

        my $PeriodKey = "Week $WeekNum";
        next if !exists $TimePeriodRanges{$PeriodKey};

        $BreakdownData{$CI}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetMonthlyClosureByCIData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $Year = $Param{Year} || '';
    my $StartMonth = $Param{StartMonth} || 1;
    my $EndMonth = $Param{EndMonth} || 12;

    if ( !$Year || $Year !~ /^\d{4}$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid year',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my $StartDate = sprintf("%04d-%02d-01 00:00:00", $Year, $StartMonth);

    # Calculate end date
    use POSIX qw(mktime);
    my $next_month = mktime(0, 0, 0, 1, $EndMonth, $Year - 1900);
    my @last_day = localtime($next_month - 86400);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $last_day[5] + 1900, $last_day[4] + 1, $last_day[3]);

    # Format filter description (e.g., "Jan - Dec 2025" or "Mar - Jun 2025")
    my @MonthAbbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my $FilterDescription = sprintf("%s - %s %d",
        $MonthAbbr[$StartMonth - 1], $MonthAbbr[$EndMonth - 1], $Year);

    # Build time periods (months in the range)
    my @TimePeriods;
    my %TimePeriodRanges;

    for my $MonthNum ($StartMonth..$EndMonth) {
        my $PeriodKey = $MonthAbbr[$MonthNum - 1];

        # Calculate last day of this month
        my $month_next = mktime(0, 0, 0, 1, $MonthNum, $Year - 1900);
        my @month_last = localtime($month_next - 86400);
        my $LastDayOfMonth = $month_last[3];

        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => sprintf("%04d-%02d-01 00:00:00", $Year, $MonthNum),
            EndDate   => sprintf("%04d-%02d-%02d 23:59:59", $Year, $MonthNum, $LastDayOfMonth),
        };
    }

    # First query: Get top 10 CIs by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetMonthlyClosureByCIData: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $CI;
        $CategoryTotals{$CI} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by CI AND month
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            EXTRACT(MONTH FROM th.create_time)::int as month_num,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(MONTH FROM th.create_time)
        ORDER BY dfv.value_text, month_num
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetMonthlyClosureByCIData: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $MonthNum = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$CI};

        my $PeriodKey = $MonthAbbr[$MonthNum - 1];
        next if !exists $TimePeriodRanges{$PeriodKey};

        $BreakdownData{$CI}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetQuarterlyClosureByCIData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $Year = $Param{Year} || '';
    if ( !$Year || $Year !~ /^\d{4}$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid year',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my $StartDate = "$Year-01-01 00:00:00";
    my $EndDate = "$Year-12-31 23:59:59";

    # Format filter description (e.g., "Year 2025")
    my $FilterDescription = "Year $Year";

    # Build time periods (4 quarters)
    my @TimePeriods = ('Q1', 'Q2', 'Q3', 'Q4');
    my %TimePeriodRanges = (
        'Q1' => { StartDate => "$Year-01-01 00:00:00", EndDate => "$Year-03-31 23:59:59" },
        'Q2' => { StartDate => "$Year-04-01 00:00:00", EndDate => "$Year-06-30 23:59:59" },
        'Q3' => { StartDate => "$Year-07-01 00:00:00", EndDate => "$Year-09-30 23:59:59" },
        'Q4' => { StartDate => "$Year-10-01 00:00:00", EndDate => "$Year-12-31 23:59:59" },
    );

    # First query: Get top 10 CIs by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetQuarterlyClosureByCIData: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $CI;
        $CategoryTotals{$CI} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by CI AND quarter
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            EXTRACT(QUARTER FROM th.create_time)::int as quarter,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(QUARTER FROM th.create_time)
        ORDER BY dfv.value_text, quarter
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetQuarterlyClosureByCIData: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $Quarter = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$CI};

        my $PeriodKey = "Q$Quarter";
        next if !exists $TimePeriodRanges{$PeriodKey};

        $BreakdownData{$CI}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

sub _GetYearlyClosureByCIData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $StartYear = $Param{StartYear} || '';
    my $EndYear = $Param{EndYear} || '';

    if ( !$StartYear || !$EndYear || $StartYear !~ /^\d{4}$/ || $EndYear !~ /^\d{4}$/ ) {
        return (
            Categories        => [],
            TimePeriods       => [],
            TimePeriodRanges  => {},
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => 'Invalid year range',
            StartDate         => '',
            EndDate           => '',
        );
    }

    my $StartDate = "$StartYear-01-01 00:00:00";
    my $EndDate = "$EndYear-12-31 23:59:59";

    # Format filter description (e.g., "2020 - 2025")
    my $FilterDescription = "$StartYear - $EndYear";

    # Build time periods (years in the range)
    my @TimePeriods;
    my %TimePeriodRanges;

    for my $YearNum ($StartYear..$EndYear) {
        my $PeriodKey = "$YearNum";
        push @TimePeriods, $PeriodKey;
        $TimePeriodRanges{$PeriodKey} = {
            StartDate => "$YearNum-01-01 00:00:00",
            EndDate   => "$YearNum-12-31 23:59:59",
        };
    }

    # First query: Get top 10 CIs by total count
    my $TopCatSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text
        ORDER BY count DESC
        LIMIT 10
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $TopCatSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetYearlyClosureByCIData: Top categories query failed",
        );
        return (
            Categories        => [],
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => {},
            CategoryTotals    => {},
            PeriodTotals      => {},
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    my @Categories;
    my %CategoryTotals;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $Count = $Row[1] || 0;
        push @Categories, $CI;
        $CategoryTotals{$CI} = $Count;
    }

    # Initialize breakdown data structure
    my %BreakdownData;
    my %PeriodTotals;
    for my $Cat (@Categories) {
        for my $Period (@TimePeriods) {
            $BreakdownData{$Cat}{$Period} = 0;
        }
    }
    for my $Period (@TimePeriods) {
        $PeriodTotals{$Period} = 0;
    }

    # Return early if no categories
    if (!@Categories) {
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => 0,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Second query: Get breakdown by CI AND year
    my $BreakdownSQL = q{
        SELECT
            COALESCE(dfv.value_text, 'Unknown') as ci,
            EXTRACT(YEAR FROM th.create_time)::int as year,
            COUNT(DISTINCT t.id) as count
        FROM ticket t
        JOIN ticket_history th ON th.ticket_id = t.id
        JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
        JOIN ticket_state ts_current ON t.ticket_state_id = ts_current.id
        LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND th.history_type_id = 27
          AND ts_hist.name = 'closed'
          AND ts_current.name = 'closed'
          AND th.create_time >= ?
          AND th.create_time <= ?
        GROUP BY dfv.value_text, EXTRACT(YEAR FROM th.create_time)
        ORDER BY dfv.value_text, year
    };

    if ( !$DBObject->Prepare( SQL => $BreakdownSQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetYearlyClosureByCIData: Breakdown query failed",
        );
        my $GrandTotal = 0;
        $GrandTotal += $_ for values %CategoryTotals;
        return (
            Categories        => \@Categories,
            TimePeriods       => \@TimePeriods,
            TimePeriodRanges  => \%TimePeriodRanges,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            PeriodTotals      => \%PeriodTotals,
            GrandTotal        => $GrandTotal,
            FilterDescription => $FilterDescription,
            StartDate         => $StartDate,
            EndDate           => $EndDate,
        );
    }

    # Process breakdown results
    my %CatLookup = map { $_ => 1 } @Categories;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CI = $Row[0] || 'Unknown';
        my $YearNum = $Row[1];
        my $Count = $Row[2] || 0;

        # Only include top 10 categories
        next if !$CatLookup{$CI};

        my $PeriodKey = "$YearNum";
        next if !exists $TimePeriodRanges{$PeriodKey};

        $BreakdownData{$CI}{$PeriodKey} = $Count;
        $PeriodTotals{$PeriodKey} += $Count;
    }

    # Calculate grand total
    my $GrandTotal = 0;
    $GrandTotal += $_ for values %CategoryTotals;

    return (
        Categories        => \@Categories,
        TimePeriods       => \@TimePeriods,
        TimePeriodRanges  => \%TimePeriodRanges,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        PeriodTotals      => \%PeriodTotals,
        GrandTotal        => $GrandTotal,
        FilterDescription => $FilterDescription,
        StartDate         => $StartDate,
        EndDate           => $EndDate,
    );
}

# ============================================================================
# HELPER METHODS
# ============================================================================

sub _GetWeekDateRange {
    my ( $Self, $WeekStr ) = @_;

    # Parse IYYY-WIW format (e.g., "2025-W48")
    if ( $WeekStr =~ /^(\d{4})-W(\d{2})$/ ) {
        my ($Year, $WeekNum) = ($1, $2);

        use POSIX qw(mktime);
        # Calculate week start (Monday)
        my $jan4 = mktime(0, 0, 0, 4, 0, $Year - 1900);
        my @jan4_date = localtime($jan4);
        my $jan4_dow = ($jan4_date[6] + 6) % 7;
        my $first_monday = $jan4 - ($jan4_dow * 86400);
        my $week_start = $first_monday + (($WeekNum - 1) * 7 * 86400);
        my $week_end = $week_start + (6 * 86400);

        my @start_date = localtime($week_start);
        my @end_date = localtime($week_end);

        my $StartDate = sprintf("%04d-%02d-%02d 00:00:00",
            $start_date[5] + 1900, $start_date[4] + 1, $start_date[3]);
        my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
            $end_date[5] + 1900, $end_date[4] + 1, $end_date[3]);

        return ($StartDate, $EndDate);
    }

    return ('', '');
}

sub _GetMonthDateRange {
    my ( $Self, $MonthStr ) = @_;

    # Parse YYYY-MM format
    if ( $MonthStr =~ /^(\d{4})-(\d{2})$/ ) {
        my ($Year, $MonthNum) = ($1, $2);

        use POSIX qw(mktime);
        # First day of month
        my $StartDate = "$Year-$MonthNum-01 00:00:00";

        # Last day of month
        my $next_month = mktime(0, 0, 0, 1, $MonthNum, $Year - 1900);
        my @last_day = localtime($next_month - 86400);
        my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
            $last_day[5] + 1900, $last_day[4] + 1, $last_day[3]);

        return ($StartDate, $EndDate);
    }

    return ('', '');
}

sub _MapPriorityToKey {
    my ( $Self, $Priority ) = @_;

    return '' if !$Priority;

    if ( $Priority =~ /P1/i || $Priority =~ /Critical/i ) {
        return 'P1';
    }
    elsif ( $Priority =~ /P2/i || $Priority =~ /High/i ) {
        return 'P2';
    }
    elsif ( $Priority =~ /P3/i || $Priority =~ /Medium/i ) {
        return 'P3';
    }
    elsif ( $Priority =~ /P4/i || $Priority =~ /Low/i ) {
        return 'P4';
    }

    return '';
}

1;
