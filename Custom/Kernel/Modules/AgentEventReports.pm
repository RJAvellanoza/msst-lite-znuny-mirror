# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentEventReports;

use strict;
use warnings;

use POSIX qw(strftime mktime ceil);

our @ObjectDependencies = (
    'Kernel::Config',
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
    for my $Param (qw(Subaction Tab Date Week Month Year Quarter StartYear EndYear StartMonth EndMonth Section)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Handle AJAX requests for submission tab data
    if ( $GetParam{Subaction} eq 'GetSubmissionTabData' ) {
        return $Self->_GetSubmissionTabDataJSON(%GetParam);
    }

    # Determine which section to show (for future expansion)
    my $Section = $GetParam{Section} || 'EventSubmission';

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Event Reports',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentEventReports',
        Data         => {
            Section => $Section,
        },
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetSubmissionTabDataJSON {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    my $Tab = $Param{Tab} || 'hourly';

    # Route to appropriate tab handler
    my %Data;
    if ( $Tab eq 'hourly' ) {
        %Data = $Self->_GetHourlySubmissionData(%Param);
    }
    elsif ( $Tab eq 'daily' ) {
        %Data = $Self->_GetDailySubmissionData(%Param);
    }
    elsif ( $Tab eq 'weekly' ) {
        %Data = $Self->_GetWeeklySubmissionData(%Param);
    }
    elsif ( $Tab eq 'monthly' ) {
        %Data = $Self->_GetMonthlySubmissionData(%Param);
    }
    elsif ( $Tab eq 'quarterly' ) {
        %Data = $Self->_GetQuarterlySubmissionData(%Param);
    }
    elsif ( $Tab eq 'yearly' ) {
        %Data = $Self->_GetYearlySubmissionData(%Param);
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

sub _GetHourlySubmissionData {
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

    # Query tickets created from Event Monitoring source, grouped by hour and priority
    my $SQL = q{
        SELECT
            EXTRACT(HOUR FROM t.create_time) as hour,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND dfv.value_text = 'Event Monitoring'
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(HOUR FROM t.create_time), tp.name, tp.id
        ORDER BY hour, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetHourlySubmissionData: Database query failed",
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

    # Convert to array sorted by hour
    my @Rows;
    for my $hour (sort { $a <=> $b } keys %HourData) {
        push @Rows, $HourData{$hour};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetDailySubmissionData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse week parameter (YYYY-WNN)
    my $Week = $Param{Week} || '';
    my ($Year, $WeekNum);

    if ( $Week =~ /^(\d{4})-W(\d{2})$/ ) {
        $Year = $1;
        $WeekNum = $2;
    }
    else {
        # Default to current week
        my @Now = localtime();
        $Year = $Now[5] + 1900;
        $WeekNum = strftime("%V", @Now);
    }

    # Get date range for week
    my ($StartDate, $EndDate) = $Self->_GetWeekDateRange($Year, $WeekNum);

    # Initialize data structure for 7 days
    my %DayData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    my @DayNames = qw(Sun Mon Tue Wed Thu Fri Sat);

    # Parse start date and create 7 days
    my ($SY, $SM, $SD) = split /-/, $StartDate;
    for my $dayOffset (0..6) {
        my $Time = mktime(0, 0, 12, $SD + $dayOffset, $SM - 1, $SY - 1900);
        my ($sec, $min, $hour, $mday, $mon, $year, $wday) = localtime($Time);

        my $DayKey = sprintf("%04d-%02d-%02d", $year + 1900, $mon + 1, $mday);
        my $DayStart = "$DayKey 00:00:00";
        my $DayEnd = "$DayKey 23:59:59";
        my $Label = sprintf("%s %02d/%02d", $DayNames[$wday], $mon + 1, $mday);

        $DayData{$DayKey} = {
            Label => $Label,
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => $DayStart,
            EndDate => $DayEnd,
            SortKey => $DayKey,
        };
    }

    # Query tickets created from Event Monitoring source, grouped by date and priority
    my $SQL = q{
        SELECT
            DATE(t.create_time) as create_date,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND dfv.value_text = 'Event Monitoring'
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY DATE(t.create_time), tp.name, tp.id
        ORDER BY create_date, tp.id
    };

    my $StartDateTime = "$StartDate 00:00:00";
    my $EndDateTime = "$EndDate 23:59:59";
    my @Bind = (\$StartDateTime, \$EndDateTime);

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetDailySubmissionData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $CreateDate = $Row[0] || '';
        # Handle date format from DB (may include time)
        ($CreateDate) = split / /, $CreateDate;
        my $Priority = $Row[1];
        my $Count = $Row[2] || 0;

        # Map priority to P1/P2/P3/P4
        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $DayData{$CreateDate} ) {
            $DayData{$CreateDate}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    # Convert to array sorted by date
    my @Rows;
    for my $key (sort { $a cmp $b } keys %DayData) {
        push @Rows, $DayData{$key};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetWeeklySubmissionData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Parse month parameter (YYYY-MM)
    my $Month = $Param{Month} || '';
    my ($Year, $MonthNum);

    if ( $Month =~ /^(\d{4})-(\d{2})$/ ) {
        $Year = $1;
        $MonthNum = $2;
    }
    else {
        # Default to current month
        my @Now = localtime();
        $Year = $Now[5] + 1900;
        $MonthNum = sprintf("%02d", $Now[4] + 1);
    }

    # Get all weeks in month
    my @Weeks = $Self->_GetWeeksInMonth($Year, $MonthNum);

    my %WeekData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    for my $WeekInfo (@Weeks) {
        my $WeekKey = $WeekInfo->{Week};
        $WeekData{$WeekKey} = {
            Label => "Week $WeekInfo->{WeekNum}",
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => "$WeekInfo->{StartDate} 00:00:00",
            EndDate => "$WeekInfo->{EndDate} 23:59:59",
            SortKey => $WeekKey,
        };
    }

    # Query for each week
    for my $WeekInfo (@Weeks) {
        my $StartDate = "$WeekInfo->{StartDate} 00:00:00";
        my $EndDate = "$WeekInfo->{EndDate} 23:59:59";

        my $SQL = q{
            SELECT
                tp.name as priority,
                COUNT(*) as count
            FROM ticket t
            JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
            JOIN dynamic_field_value dfv ON dfv.object_id = t.id
                AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
            WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
              AND dfv.value_text = 'Event Monitoring'
              AND t.create_time >= ?
              AND t.create_time <= ?
            GROUP BY tp.name, tp.id
            ORDER BY tp.id
        };

        my @Bind = (\$StartDate, \$EndDate);

        if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
            next;
        }

        while ( my @Row = $DBObject->FetchrowArray() ) {
            my $Priority = $Row[0];
            my $Count = $Row[1] || 0;

            # Map priority to P1/P2/P3/P4
            my $PriorityKey = $Self->_MapPriorityToKey($Priority);

            if ($PriorityKey) {
                my $WeekKey = $WeekInfo->{Week};
                $WeekData{$WeekKey}{$PriorityKey} = $Count;
                $GrandTotal{$PriorityKey} += $Count;
            }
        }
    }

    # Convert to array sorted by week
    my @Rows;
    for my $key (sort { $a cmp $b } keys %WeekData) {
        push @Rows, $WeekData{$key};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetMonthlySubmissionData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Get year range
    my $StartYear = $Param{StartYear} || '';
    my $EndYear = $Param{EndYear} || '';

    if (!$StartYear || !$EndYear) {
        my @Now = localtime();
        my $CurrentYear = $Now[5] + 1900;
        $StartYear ||= $CurrentYear;
        $EndYear ||= $CurrentYear;
    }

    # Initialize months for the year range
    my %MonthData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );
    my @MonthNames = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    for my $year ($StartYear..$EndYear) {
        for my $month (1..12) {
            my $MonthKey = sprintf("%04d-%02d", $year, $month);
            my $LastDay = $Self->_GetLastDayOfMonth($year, $month);

            $MonthData{$MonthKey} = {
                Label => sprintf("%s %d", $MonthNames[$month-1], $year),
                P1 => 0,
                P2 => 0,
                P3 => 0,
                P4 => 0,
                StartDate => sprintf("%04d-%02d-01 00:00:00", $year, $month),
                EndDate => sprintf("%04d-%02d-%02d 23:59:59", $year, $month, $LastDay),
                SortKey => $MonthKey,
            };
        }
    }

    # Query tickets created from Event Monitoring source, grouped by month and priority
    my $StartDate = sprintf("%04d-01-01 00:00:00", $StartYear);
    my $EndDate = sprintf("%04d-12-31 23:59:59", $EndYear);

    my $SQL = q{
        SELECT
            EXTRACT(YEAR FROM t.create_time) as year,
            EXTRACT(MONTH FROM t.create_time) as month,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND dfv.value_text = 'Event Monitoring'
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(YEAR FROM t.create_time), EXTRACT(MONTH FROM t.create_time), tp.name, tp.id
        ORDER BY year, month, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetMonthlySubmissionData: Database query failed",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Year = int($Row[0]);
        my $Month = int($Row[1]);
        my $MonthKey = sprintf("%04d-%02d", $Year, $Month);
        my $Priority = $Row[2];
        my $Count = $Row[3] || 0;

        # Map priority to P1/P2/P3/P4
        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $MonthData{$MonthKey} ) {
            $MonthData{$MonthKey}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    # Convert to array sorted by month
    my @Rows;
    for my $key (sort { $a cmp $b } keys %MonthData) {
        push @Rows, $MonthData{$key};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetQuarterlySubmissionData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Get year
    my $Year = $Param{Year} || '';
    if (!$Year) {
        my @Now = localtime();
        $Year = $Now[5] + 1900;
    }

    # Initialize quarters
    my %QuarterData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    my @QuarterInfo = (
        { Name => 'Q1', StartMonth => 1,  EndMonth => 3 },
        { Name => 'Q2', StartMonth => 4,  EndMonth => 6 },
        { Name => 'Q3', StartMonth => 7,  EndMonth => 9 },
        { Name => 'Q4', StartMonth => 10, EndMonth => 12 },
    );

    for my $Q (@QuarterInfo) {
        my $LastDay = $Self->_GetLastDayOfMonth($Year, $Q->{EndMonth});
        my $QuarterKey = "$Year-$Q->{Name}";

        $QuarterData{$QuarterKey} = {
            Label => "$Q->{Name} $Year",
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => sprintf("%04d-%02d-01 00:00:00", $Year, $Q->{StartMonth}),
            EndDate => sprintf("%04d-%02d-%02d 23:59:59", $Year, $Q->{EndMonth}, $LastDay),
            SortKey => $QuarterKey,
        };
    }

    # Query for each quarter
    for my $Q (@QuarterInfo) {
        my $LastDay = $Self->_GetLastDayOfMonth($Year, $Q->{EndMonth});
        my $StartDate = sprintf("%04d-%02d-01 00:00:00", $Year, $Q->{StartMonth});
        my $EndDate = sprintf("%04d-%02d-%02d 23:59:59", $Year, $Q->{EndMonth}, $LastDay);

        my $SQL = q{
            SELECT
                tp.name as priority,
                COUNT(*) as count
            FROM ticket t
            JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
            JOIN dynamic_field_value dfv ON dfv.object_id = t.id
                AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
            WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
              AND dfv.value_text = 'Event Monitoring'
              AND t.create_time >= ?
              AND t.create_time <= ?
            GROUP BY tp.name, tp.id
            ORDER BY tp.id
        };

        my @Bind = (\$StartDate, \$EndDate);

        if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
            next;
        }

        while ( my @Row = $DBObject->FetchrowArray() ) {
            my $Priority = $Row[0];
            my $Count = $Row[1] || 0;

            # Map priority to P1/P2/P3/P4
            my $PriorityKey = $Self->_MapPriorityToKey($Priority);

            if ($PriorityKey) {
                my $QuarterKey = "$Year-$Q->{Name}";
                $QuarterData{$QuarterKey}{$PriorityKey} = $Count;
                $GrandTotal{$PriorityKey} += $Count;
            }
        }
    }

    # Convert to array sorted by quarter
    my @Rows;
    for my $key (sort { $a cmp $b } keys %QuarterData) {
        push @Rows, $QuarterData{$key};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

sub _GetYearlySubmissionData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Get year range
    my $StartYear = $Param{StartYear} || '';
    my $EndYear = $Param{EndYear} || '';

    if (!$StartYear || !$EndYear) {
        my @Now = localtime();
        my $CurrentYear = $Now[5] + 1900;
        $StartYear ||= $CurrentYear - 2;
        $EndYear ||= $CurrentYear;
    }

    # Initialize years
    my %YearData;
    my %GrandTotal = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );

    for my $year ($StartYear..$EndYear) {
        $YearData{$year} = {
            Label => "$year",
            P1 => 0,
            P2 => 0,
            P3 => 0,
            P4 => 0,
            StartDate => "$year-01-01 00:00:00",
            EndDate => "$year-12-31 23:59:59",
            SortKey => $year,
        };
    }

    # Query tickets created from Event Monitoring source, grouped by year and priority
    my $StartDate = "$StartYear-01-01 00:00:00";
    my $EndDate = "$EndYear-12-31 23:59:59";

    my $SQL = q{
        SELECT
            EXTRACT(YEAR FROM t.create_time) as year,
            tp.name as priority,
            COUNT(*) as count
        FROM ticket t
        JOIN ticket_priority tp ON t.ticket_priority_id = tp.id
        JOIN dynamic_field_value dfv ON dfv.object_id = t.id
            AND dfv.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
          AND dfv.value_text = 'Event Monitoring'
          AND t.create_time >= ?
          AND t.create_time <= ?
        GROUP BY EXTRACT(YEAR FROM t.create_time), tp.name, tp.id
        ORDER BY year, tp.id
    };

    my @Bind = (\$StartDate, \$EndDate);

    if ( !$DBObject->Prepare( SQL => $SQL, Bind => \@Bind ) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetYearlySubmissionData: Database query failed",
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

        # Map priority to P1/P2/P3/P4
        my $PriorityKey = $Self->_MapPriorityToKey($Priority);

        if ( $PriorityKey && exists $YearData{$Year} ) {
            $YearData{$Year}{$PriorityKey} = $Count;
            $GrandTotal{$PriorityKey} += $Count;
        }
    }

    # Convert to array sorted by year
    my @Rows;
    for my $key (sort { $a <=> $b } keys %YearData) {
        push @Rows, $YearData{$key};
    }

    return (
        Rows => \@Rows,
        GrandTotal => \%GrandTotal,
    );
}

# Helper methods

sub _GetWeekDateRange {
    my ( $Self, $Year, $WeekNum ) = @_;

    # Get the first day of the year
    my $Jan1 = mktime(0, 0, 12, 1, 0, $Year - 1900);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = localtime($Jan1);

    # Calculate the first Monday of week 1
    my $DaysToMonday = (8 - $wday) % 7;
    $DaysToMonday = 0 if $wday == 1; # Already Monday
    $DaysToMonday -= 7 if $wday == 0; # Sunday, go back

    my $Week1Monday = mktime(0, 0, 12, 1 + $DaysToMonday, 0, $Year - 1900);

    # Add weeks
    my $TargetMonday = $Week1Monday + (($WeekNum - 1) * 7 * 24 * 60 * 60);
    my $TargetSunday = $TargetMonday + (6 * 24 * 60 * 60);

    my $StartDate = strftime("%Y-%m-%d", localtime($TargetMonday));
    my $EndDate = strftime("%Y-%m-%d", localtime($TargetSunday));

    return ($StartDate, $EndDate);
}

sub _GetWeeksInMonth {
    my ( $Self, $Year, $Month ) = @_;

    my @Weeks;
    my $FirstDay = mktime(0, 0, 12, 1, $Month - 1, $Year - 1900);
    my $LastDay = $Self->_GetLastDayOfMonth($Year, $Month);
    my $LastDayTime = mktime(0, 0, 12, $LastDay, $Month - 1, $Year - 1900);

    my $CurrentDay = $FirstDay;
    my $WeekCount = 0;

    while ($CurrentDay <= $LastDayTime) {
        my ($sec, $min, $hour, $mday, $mon, $year, $wday) = localtime($CurrentDay);

        # Get ISO week number
        my $WeekNum = strftime("%V", localtime($CurrentDay));
        my $WeekYear = strftime("%G", localtime($CurrentDay));

        # Find week start (Monday)
        my $DaysFromMonday = ($wday == 0) ? 6 : $wday - 1;
        my $WeekStart = $CurrentDay - ($DaysFromMonday * 24 * 60 * 60);
        my $WeekEnd = $WeekStart + (6 * 24 * 60 * 60);

        my $WeekKey = sprintf("%04d-W%02d", $WeekYear, $WeekNum);

        push @Weeks, {
            Week => $WeekKey,
            WeekNum => $WeekNum,
            StartDate => strftime("%Y-%m-%d", localtime($WeekStart)),
            EndDate => strftime("%Y-%m-%d", localtime($WeekEnd)),
        };

        # Move to next week
        $CurrentDay = $WeekEnd + (24 * 60 * 60);
        $WeekCount++;

        last if $WeekCount > 6; # Safety limit
    }

    return @Weeks;
}

sub _GetLastDayOfMonth {
    my ( $Self, $Year, $Month ) = @_;

    my @DaysInMonth = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

    # Leap year check
    if ($Month == 2) {
        if (($Year % 4 == 0 && $Year % 100 != 0) || ($Year % 400 == 0)) {
            return 29;
        }
    }

    return $DaysInMonth[$Month - 1];
}

sub _MapPriorityToKey {
    my ( $Self, $PriorityName ) = @_;

    return '' unless $PriorityName;

    if ( $PriorityName =~ /P1|Critical/i ) { return 'P1'; }
    if ( $PriorityName =~ /P2|High/i )     { return 'P2'; }
    if ( $PriorityName =~ /P3|Medium/i )   { return 'P3'; }
    if ( $PriorityName =~ /P4|Low/i )      { return 'P4'; }

    return '';
}

1;
