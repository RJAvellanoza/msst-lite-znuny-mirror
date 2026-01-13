# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentHistoricalTrends;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Time',
    'Kernel::System::Log',
    'Kernel::System::JSON',
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
    for my $Param (qw(Subaction Tab Date Week Month Year Quarter StartYear EndYear StartMonth EndMonth)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Handle AJAX requests for tab data
    if ( $GetParam{Subaction} eq 'GetTabData' ) {
        return $Self->_GetTabDataJSON(%GetParam);
    }

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Historical Trends',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentHistoricalTrends',
        Data         => \%GetParam,
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

    # Query tickets grouped by hour and priority
    my $SQL = q{
        SELECT
            EXTRACT(HOUR FROM t.create_time) as hour,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = 2
          AND t.ticket_state_id NOT IN (
              SELECT id FROM ticket_state WHERE type_id = 3
          )
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
        $HourData{$hour} = {
            Label => sprintf("%02d:00", $hour),
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
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
        my $PriorityKey;
        if ( $Priority =~ /P1/i ) {
            $PriorityKey = 'P1';
        }
        elsif ( $Priority =~ /P2/i ) {
            $PriorityKey = 'P2';
        }
        elsif ( $Priority =~ /P3/i ) {
            $PriorityKey = 'P3';
        }
        elsif ( $Priority =~ /P4/i ) {
            $PriorityKey = 'P4';
        }

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

    # Query tickets grouped by date and priority
    my $SQL = q{
        SELECT
            DATE(t.create_time) as day,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = 2
          AND t.ticket_state_id NOT IN (
              SELECT id FROM ticket_state WHERE type_id = 3
          )
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY DATE(t.create_time), tp.name, tp.id
        ORDER BY day, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    # Initialize data structure for 7 days
    my %DayData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    for my $i (0..6) {
        my $day_time = $week_start + ($i * 86400);
        my @day = localtime($day_time);
        my $date_str = sprintf("%04d-%02d-%02d", $day[5] + 1900, $day[4] + 1, $day[3]);
        $DayData{$date_str} = {
            Label => $date_str,
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
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

        my $PriorityKey;
        if ( $Priority =~ /P1/i ) {
            $PriorityKey = 'P1';
        }
        elsif ( $Priority =~ /P2/i ) {
            $PriorityKey = 'P2';
        }
        elsif ( $Priority =~ /P3/i ) {
            $PriorityKey = 'P3';
        }
        elsif ( $Priority =~ /P4/i ) {
            $PriorityKey = 'P4';
        }

        if ( $PriorityKey && exists $DayData{$Day} ) {
            $DayData{$Day}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    # Convert to array
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

    # Calculate first and last day of month
    use POSIX qw(mktime);
    my $month_start = mktime(0, 0, 0, 1, $MonthNum - 1, $Year - 1900);
    my @month_start_date = localtime($month_start);

    # Get last day of month
    my $next_month = mktime(0, 0, 0, 1, $MonthNum, $Year - 1900);
    my $month_end = $next_month - 1;
    my @month_end_date = localtime($month_end);

    my $StartDate = sprintf("%04d-%02d-%02d 00:00:00",
        $month_start_date[5] + 1900, $month_start_date[4] + 1, $month_start_date[3]);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $month_end_date[5] + 1900, $month_end_date[4] + 1, $month_end_date[3]);

    # Query tickets grouped by week and priority
    my $SQL = q{
        SELECT
            EXTRACT(WEEK FROM t.create_time) as week,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = 2
          AND t.ticket_state_id NOT IN (
              SELECT id FROM ticket_state WHERE type_id = 3
          )
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(WEEK FROM t.create_time), tp.name, tp.id
        ORDER BY week, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    # Get all weeks that overlap with this month
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
        my $Week = int($Row[0]);
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        if ( !exists $WeekData{$Week} ) {
            $WeekData{$Week} = {
                Label => "Week $Week",
                P1 => 0,
                P2 => 0,
                P3 => 0,
                P4 => 0,
            };
        }

        my $PriorityKey;
        if ( $Priority =~ /P1/i ) {
            $PriorityKey = 'P1';
        }
        elsif ( $Priority =~ /P2/i ) {
            $PriorityKey = 'P2';
        }
        elsif ( $Priority =~ /P3/i ) {
            $PriorityKey = 'P3';
        }
        elsif ( $Priority =~ /P4/i ) {
            $PriorityKey = 'P4';
        }

        if ( $PriorityKey ) {
            $WeekData{$Week}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    # Convert to array
    my @Rows;
    for my $week (sort { $a <=> $b } keys %WeekData) {
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
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Parse parameters: StartMonth, EndMonth, Year
    my $Year = $Param{Year} || '';
    my $StartMonth = $Param{StartMonth} || '';
    my $EndMonth = $Param{EndMonth} || '';

    # Default to current year if not specified
    if ( !$Year ) {
        my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
        ($Year) = split /-/, $CurrentTimestamp;
    }

    # Default to full year (Jan-Dec) if not specified
    $StartMonth = 1 if !$StartMonth || $StartMonth !~ /^\d+$/ || $StartMonth < 1 || $StartMonth > 12;
    $EndMonth = 12 if !$EndMonth || $EndMonth !~ /^\d+$/ || $EndMonth < 1 || $EndMonth > 12;

    # Swap if start > end
    if ( $StartMonth > $EndMonth ) {
        ($StartMonth, $EndMonth) = ($EndMonth, $StartMonth);
    }

    my $StartDate = sprintf("%04d-%02d-01 00:00:00", $Year, $StartMonth);

    # Calculate last day of end month
    use POSIX qw(mktime);
    my $next_month_time = mktime(0, 0, 0, 1, $EndMonth, $Year - 1900);
    my $last_day_time = $next_month_time - 1;
    my @last_day = localtime($last_day_time);
    my $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
        $last_day[5] + 1900, $last_day[4] + 1, $last_day[3]);

    # Query tickets grouped by month and priority
    my $SQL = q{
        SELECT
            EXTRACT(MONTH FROM t.create_time) as month,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = 2
          AND t.ticket_state_id NOT IN (
              SELECT id FROM ticket_state WHERE type_id = 3
          )
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(MONTH FROM t.create_time), tp.name, tp.id
        ORDER BY month, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    # Initialize data structure for selected months
    my %MonthData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );
    my @MonthNames = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    for my $month ($StartMonth..$EndMonth) {
        $MonthData{$month} = {
            Label => $MonthNames[$month - 1],
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
        };
    }

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
        my $Month = int($Row[0]);
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey;
        if ( $Priority =~ /P1/i ) {
            $PriorityKey = 'P1';
        }
        elsif ( $Priority =~ /P2/i ) {
            $PriorityKey = 'P2';
        }
        elsif ( $Priority =~ /P3/i ) {
            $PriorityKey = 'P3';
        }
        elsif ( $Priority =~ /P4/i ) {
            $PriorityKey = 'P4';
        }

        if ( $PriorityKey && exists $MonthData{$Month} ) {
            $MonthData{$Month}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    # Convert to array
    my @Rows;
    for my $month (sort { $a <=> $b } keys %MonthData) {
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
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Parse year parameter
    my $Year = $Param{Year} || '';
    if ( !$Year || $Year !~ /^\d{4}$/ ) {
        my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
        ($Year) = split /-/, $CurrentTimestamp;
    }

    my $StartDate = sprintf("%04d-01-01 00:00:00", $Year);
    my $EndDate = sprintf("%04d-12-31 23:59:59", $Year);

    # Query tickets grouped by quarter and priority
    my $SQL = q{
        SELECT
            EXTRACT(QUARTER FROM t.create_time) as quarter,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = 2
          AND t.ticket_state_id NOT IN (
              SELECT id FROM ticket_state WHERE type_id = 3
          )
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(QUARTER FROM t.create_time), tp.name, tp.id
        ORDER BY quarter, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    # Initialize data structure for 4 quarters
    my %QuarterData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    for my $quarter (1..4) {
        $QuarterData{$quarter} = {
            Label => "Q$quarter",
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
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
        my $Quarter = int($Row[0]);
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        my $PriorityKey;
        if ( $Priority =~ /P1/i ) {
            $PriorityKey = 'P1';
        }
        elsif ( $Priority =~ /P2/i ) {
            $PriorityKey = 'P2';
        }
        elsif ( $Priority =~ /P3/i ) {
            $PriorityKey = 'P3';
        }
        elsif ( $Priority =~ /P4/i ) {
            $PriorityKey = 'P4';
        }

        if ( $PriorityKey && exists $QuarterData{$Quarter} ) {
            $QuarterData{$Quarter}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    # Convert to array
    my @Rows;
    for my $quarter (sort { $a <=> $b } keys %QuarterData) {
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
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Parse year range parameters
    my $StartYear = $Param{StartYear} || '';
    my $EndYear = $Param{EndYear} || '';

    # Default to last 5 years if not specified
    if ( !$StartYear || !$EndYear ) {
        my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
        my ($CurrentYear) = split /-/, $CurrentTimestamp;
        $EndYear = $CurrentYear;
        $StartYear = $CurrentYear - 4;
    }

    # Validate years
    if ( $StartYear !~ /^\d{4}$/ || $EndYear !~ /^\d{4}$/ || $StartYear > $EndYear ) {
        return (
            Rows => [],
            GrandTotal => { P1 => 0, P2 => 0, P3 => 0, P4 => 0 },
        );
    }

    my $StartDate = sprintf("%04d-01-01 00:00:00", $StartYear);
    my $EndDate = sprintf("%04d-12-31 23:59:59", $EndYear);

    # Query tickets grouped by year and priority
    my $SQL = q{
        SELECT
            EXTRACT(YEAR FROM t.create_time) as year,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        WHERE t.type_id = 2
          AND t.ticket_state_id NOT IN (
              SELECT id FROM ticket_state WHERE type_id = 3
          )
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(YEAR FROM t.create_time), tp.name, tp.id
        ORDER BY year, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    # Initialize data structure for year range
    my %YearData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    for my $year ($StartYear..$EndYear) {
        $YearData{$year} = {
            Label => "$year",
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
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

        my $PriorityKey;
        if ( $Priority =~ /P1/i ) {
            $PriorityKey = 'P1';
        }
        elsif ( $Priority =~ /P2/i ) {
            $PriorityKey = 'P2';
        }
        elsif ( $Priority =~ /P3/i ) {
            $PriorityKey = 'P3';
        }
        elsif ( $Priority =~ /P4/i ) {
            $PriorityKey = 'P4';
        }

        if ( $PriorityKey && exists $YearData{$Year} ) {
            $YearData{$Year}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    # Convert to array
    my @Rows;
    for my $year (sort { $a <=> $b } keys %YearData) {
        push @Rows, $YearData{$year};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

1;
