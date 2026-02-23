# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentEventReportsZabbix;

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
    'Kernel::System::ZabbixDB',
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
    for my $Param (qw(Subaction Tab Date Week Month Year StartYear EndYear StartMonth EndMonth Section)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Handle AJAX requests for submission tab data
    if ( $GetParam{Subaction} eq 'GetSubmissionTabData' ) {
        return $Self->_GetSubmissionTabDataJSON(%GetParam);
    }

    # Handle AJAX requests for top entity tab data
    if ( $GetParam{Subaction} eq 'GetTopEntityTabData' ) {
        return $Self->_GetTopEntityTabDataJSON(%GetParam);
    }

    # Determine which section to show
    my $Section = $GetParam{Section} || 'IncidentCreation';

    # Choose template based on section
    my $TemplateFile = 'AgentEventReportsZabbix';
    if ( $Section eq 'TopEntity' ) {
        $TemplateFile = 'AgentEventReportsZabbixTopEntity';
    }

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Event Management',
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

    my $ZabbixDBObject = $Kernel::OM->Get('Kernel::System::ZabbixDB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Parse date parameter (YYYY-MM-DD)
    my $Date = $Param{Date} || '';
    if ( !$Date ) {
        my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
        ($Date) = split / /, $CurrentTimestamp;
    }

    # Initialize data structure for 24 hours
    my %HourData;
    my %GrandTotal = ( WithTicket => 0, WithoutTicket => 0 );

    # Parse date to get Unix timestamps for start/end of day
    my ($Year, $Month, $Day) = split /-/, $Date;
    my $DayStartEpoch = mktime(0, 0, 0, $Day, $Month - 1, $Year - 1900);

    for my $hour (0..23) {
        my $HourStart = sprintf("%s %02d:00:00", $Date, $hour);
        my $HourEnd = sprintf("%s %02d:59:59", $Date, $hour);
        my $HourStartEpoch = $DayStartEpoch + ($hour * 3600);
        my $HourEndEpoch   = $HourStartEpoch + 3599;
        $HourData{$hour} = {
            Label => sprintf("%02d:00", $hour),
            WithTicket => 0,
            WithoutTicket => 0,
            StartDate => $HourStart,
            EndDate => $HourEnd,
            StartEpoch => $HourStartEpoch,
            EndEpoch   => $HourEndEpoch,
        };
    }

    # Connect to Zabbix DB
    my $ConnectResult = $ZabbixDBObject->Connect();
    if (!$ConnectResult->{Success}) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetHourlySubmissionData: Failed to connect to Zabbix DB: " . ($ConnectResult->{ErrorMessage} || ''),
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    my $StartEpoch = $DayStartEpoch;
    my $EndEpoch = mktime(59, 59, 23, $Day, $Month - 1, $Year - 1900);

    # Query Zabbix problem table grouped by hour
    # LEFT JOIN problem_tag to detect events with znuny_ticket_nr
    my $SQL = qq{
        SELECT
            EXTRACT(HOUR FROM to_timestamp(p.clock)) as hour,
            COUNT(CASE WHEN pt.eventid IS NOT NULL THEN 1 END) as with_ticket,
            COUNT(CASE WHEN pt.eventid IS NULL THEN 1 END) as without_ticket
        FROM problem p
        LEFT JOIN (
            SELECT DISTINCT eventid
            FROM problem_tag
            WHERE tag = 'znuny_ticket_nr'
        ) pt ON pt.eventid = p.eventid
        WHERE p.source = 0
          AND p.clock >= $StartEpoch
          AND p.clock <= $EndEpoch
          AND p.severity >= 2
        GROUP BY EXTRACT(HOUR FROM to_timestamp(p.clock))
        ORDER BY hour
    };

    my $STH = $ZabbixDBObject->{DBH}->prepare($SQL);
    if (!$STH || !$STH->execute()) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetHourlySubmissionData: Zabbix query failed: " . ($ZabbixDBObject->{DBH}->errstr || ''),
        );
        $ZabbixDBObject->Disconnect();
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $STH->fetchrow_array() ) {
        my $Hour = int($Row[0]);
        my $WithTicket = $Row[1] || 0;
        my $WithoutTicket = $Row[2] || 0;

        if ( exists $HourData{$Hour} ) {
            $HourData{$Hour}{WithTicket} = $WithTicket;
            $HourData{$Hour}{WithoutTicket} = $WithoutTicket;
            $GrandTotal{WithTicket} += $WithTicket;
            $GrandTotal{WithoutTicket} += $WithoutTicket;
        }
    }
    $STH->finish();
    $ZabbixDBObject->Disconnect();

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

    my $ZabbixDBObject = $Kernel::OM->Get('Kernel::System::ZabbixDB');
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
    my %GrandTotal = ( WithTicket => 0, WithoutTicket => 0 );

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

        my $DayStartEpoch = mktime(0, 0, 0, $mday, $mon, $year);
        my $DayEndEpoch   = $DayStartEpoch + 86399;

        $DayData{$DayKey} = {
            Label => $Label,
            WithTicket => 0,
            WithoutTicket => 0,
            StartDate => $DayStart,
            EndDate => $DayEnd,
            StartEpoch => $DayStartEpoch,
            EndEpoch   => $DayEndEpoch,
            SortKey => $DayKey,
        };
    }

    # Connect to Zabbix DB
    my $ConnectResult = $ZabbixDBObject->Connect();
    if (!$ConnectResult->{Success}) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetDailySubmissionData: Failed to connect to Zabbix DB",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    # Calculate epoch times
    my $StartEpoch = mktime(0, 0, 0, $SD, $SM - 1, $SY - 1900);
    my $EndEpoch = $StartEpoch + (7 * 24 * 60 * 60) - 1;

    # Query Zabbix problem table grouped by date
    # LEFT JOIN problem_tag to detect events with znuny_ticket_nr
    my $SQL = qq{
        SELECT
            DATE(to_timestamp(p.clock)) as problem_date,
            COUNT(CASE WHEN pt.eventid IS NOT NULL THEN 1 END) as with_ticket,
            COUNT(CASE WHEN pt.eventid IS NULL THEN 1 END) as without_ticket
        FROM problem p
        LEFT JOIN (
            SELECT DISTINCT eventid
            FROM problem_tag
            WHERE tag = 'znuny_ticket_nr'
        ) pt ON pt.eventid = p.eventid
        WHERE p.source = 0
          AND p.clock >= $StartEpoch
          AND p.clock <= $EndEpoch
          AND p.severity >= 2
        GROUP BY DATE(to_timestamp(p.clock))
        ORDER BY problem_date
    };

    my $STH = $ZabbixDBObject->{DBH}->prepare($SQL);
    if (!$STH || !$STH->execute()) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetDailySubmissionData: Zabbix query failed",
        );
        $ZabbixDBObject->Disconnect();
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $STH->fetchrow_array() ) {
        my $ProblemDate = $Row[0] || '';
        # Handle date format from DB (may include time)
        ($ProblemDate) = split / /, $ProblemDate;
        my $WithTicket = $Row[1] || 0;
        my $WithoutTicket = $Row[2] || 0;

        if ( exists $DayData{$ProblemDate} ) {
            $DayData{$ProblemDate}{WithTicket} = $WithTicket;
            $DayData{$ProblemDate}{WithoutTicket} = $WithoutTicket;
            $GrandTotal{WithTicket} += $WithTicket;
            $GrandTotal{WithoutTicket} += $WithoutTicket;
        }
    }
    $STH->finish();
    $ZabbixDBObject->Disconnect();

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

    my $ZabbixDBObject = $Kernel::OM->Get('Kernel::System::ZabbixDB');
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
    my %GrandTotal = ( WithTicket => 0, WithoutTicket => 0 );

    for my $WeekInfo (@Weeks) {
        my $WeekKey = $WeekInfo->{Week};
        my ($SY, $SM, $SD) = split /-/, $WeekInfo->{StartDate};
        my ($EY, $EM, $ED) = split /-/, $WeekInfo->{EndDate};
        my $WStartEpoch = mktime(0, 0, 0, $SD, $SM - 1, $SY - 1900);
        my $WEndEpoch   = mktime(59, 59, 23, $ED, $EM - 1, $EY - 1900);

        $WeekData{$WeekKey} = {
            Label => "Week $WeekInfo->{WeekNum}",
            WithTicket => 0,
            WithoutTicket => 0,
            StartDate => "$WeekInfo->{StartDate} 00:00:00",
            EndDate => "$WeekInfo->{EndDate} 23:59:59",
            StartEpoch => $WStartEpoch,
            EndEpoch   => $WEndEpoch,
            SortKey => $WeekKey,
        };
    }

    # Connect to Zabbix DB
    my $ConnectResult = $ZabbixDBObject->Connect();
    if (!$ConnectResult->{Success}) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetWeeklySubmissionData: Failed to connect to Zabbix DB",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    # Query for each week
    for my $WeekInfo (@Weeks) {
        my ($SY, $SM, $SD) = split /-/, $WeekInfo->{StartDate};
        my ($EY, $EM, $ED) = split /-/, $WeekInfo->{EndDate};

        my $StartEpoch = mktime(0, 0, 0, $SD, $SM - 1, $SY - 1900);
        my $EndEpoch = mktime(59, 59, 23, $ED, $EM - 1, $EY - 1900);

        my $SQL = qq{
            SELECT
                COUNT(CASE WHEN pt.eventid IS NOT NULL THEN 1 END) as with_ticket,
                COUNT(CASE WHEN pt.eventid IS NULL THEN 1 END) as without_ticket
            FROM problem p
            LEFT JOIN (
                SELECT DISTINCT eventid
                FROM problem_tag
                WHERE tag = 'znuny_ticket_nr'
            ) pt ON pt.eventid = p.eventid
            WHERE p.source = 0
              AND p.clock >= $StartEpoch
              AND p.clock <= $EndEpoch
              AND p.severity >= 2
        };

        my $STH = $ZabbixDBObject->{DBH}->prepare($SQL);
        next if (!$STH || !$STH->execute());

        while ( my @Row = $STH->fetchrow_array() ) {
            my $WithTicket = $Row[0] || 0;
            my $WithoutTicket = $Row[1] || 0;

            my $WeekKey = $WeekInfo->{Week};
            $WeekData{$WeekKey}{WithTicket} = $WithTicket;
            $WeekData{$WeekKey}{WithoutTicket} = $WithoutTicket;
            $GrandTotal{WithTicket} += $WithTicket;
            $GrandTotal{WithoutTicket} += $WithoutTicket;
        }
        $STH->finish();
    }

    $ZabbixDBObject->Disconnect();

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

    my $ZabbixDBObject = $Kernel::OM->Get('Kernel::System::ZabbixDB');
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
    my %GrandTotal = ( WithTicket => 0, WithoutTicket => 0 );
    my @MonthNames = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    for my $year ($StartYear..$EndYear) {
        for my $month (1..12) {
            my $MonthKey = sprintf("%04d-%02d", $year, $month);
            my $LastDay = $Self->_GetLastDayOfMonth($year, $month);

            my $MStartEpoch = mktime(0, 0, 0, 1, $month - 1, $year - 1900);
            my $MEndEpoch   = mktime(59, 59, 23, $LastDay, $month - 1, $year - 1900);

            $MonthData{$MonthKey} = {
                Label => sprintf("%s %d", $MonthNames[$month-1], $year),
                WithTicket => 0,
                WithoutTicket => 0,
                StartDate => sprintf("%04d-%02d-01 00:00:00", $year, $month),
                EndDate => sprintf("%04d-%02d-%02d 23:59:59", $year, $month, $LastDay),
                StartEpoch => $MStartEpoch,
                EndEpoch   => $MEndEpoch,
                SortKey => $MonthKey,
            };
        }
    }

    # Connect to Zabbix DB
    my $ConnectResult = $ZabbixDBObject->Connect();
    if (!$ConnectResult->{Success}) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetMonthlySubmissionData: Failed to connect to Zabbix DB",
        );
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    # Calculate epoch range
    my $StartEpoch = mktime(0, 0, 0, 1, 0, $StartYear - 1900);
    my $EndEpoch = mktime(59, 59, 23, 31, 11, $EndYear - 1900);

    # Query Zabbix problem table grouped by month
    # LEFT JOIN problem_tag to detect events with znuny_ticket_nr
    my $SQL = qq{
        SELECT
            EXTRACT(YEAR FROM to_timestamp(p.clock)) as year,
            EXTRACT(MONTH FROM to_timestamp(p.clock)) as month,
            COUNT(CASE WHEN pt.eventid IS NOT NULL THEN 1 END) as with_ticket,
            COUNT(CASE WHEN pt.eventid IS NULL THEN 1 END) as without_ticket
        FROM problem p
        LEFT JOIN (
            SELECT DISTINCT eventid
            FROM problem_tag
            WHERE tag = 'znuny_ticket_nr'
        ) pt ON pt.eventid = p.eventid
        WHERE p.source = 0
          AND p.clock >= $StartEpoch
          AND p.clock <= $EndEpoch
          AND p.severity >= 2
        GROUP BY EXTRACT(YEAR FROM to_timestamp(p.clock)), EXTRACT(MONTH FROM to_timestamp(p.clock))
        ORDER BY year, month
    };

    my $STH = $ZabbixDBObject->{DBH}->prepare($SQL);
    if (!$STH || !$STH->execute()) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetMonthlySubmissionData: Zabbix query failed",
        );
        $ZabbixDBObject->Disconnect();
        return (
            Rows => [],
            GrandTotal => \%GrandTotal,
        );
    }

    while ( my @Row = $STH->fetchrow_array() ) {
        my $Year = int($Row[0]);
        my $Month = int($Row[1]);
        my $MonthKey = sprintf("%04d-%02d", $Year, $Month);
        my $WithTicket = $Row[2] || 0;
        my $WithoutTicket = $Row[3] || 0;

        if ( exists $MonthData{$MonthKey} ) {
            $MonthData{$MonthKey}{WithTicket} = $WithTicket;
            $MonthData{$MonthKey}{WithoutTicket} = $WithoutTicket;
            $GrandTotal{WithTicket} += $WithTicket;
            $GrandTotal{WithoutTicket} += $WithoutTicket;
        }
    }
    $STH->finish();
    $ZabbixDBObject->Disconnect();

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

# ==========================================
# Top 10 Impacted CI (Entity) methods
# ==========================================

sub _GetTopEntityTabDataJSON {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    my $Tab = $Param{Tab} || 'hourly';

    my %Data;
    if ( $Tab eq 'hourly' ) {
        %Data = $Self->_GetHourlyTopEntityData(%Param);
    }
    elsif ( $Tab eq 'daily' ) {
        %Data = $Self->_GetDailyTopEntityData(%Param);
    }
    elsif ( $Tab eq 'weekly' ) {
        %Data = $Self->_GetWeeklyTopEntityData(%Param);
    }
    elsif ( $Tab eq 'monthly' ) {
        %Data = $Self->_GetMonthlyTopEntityData(%Param);
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

sub _GetTopEntitySQL {
    my ( $Self, %Param ) = @_;

    my $StartEpoch = $Param{StartEpoch};
    my $EndEpoch   = $Param{EndEpoch};

    # Single query: get top 10 entities with WithTicket/WithoutTicket breakdown
    # Entity = COALESCE(snmp_component extracted from history_log, hosts.name)
    # DISTINCT ON (p.eventid) prevents duplicates from triggers with multiple functions/items
    my $SQL = qq{
        SELECT
            entity,
            SUM(CASE WHEN has_ticket = 1 THEN 1 ELSE 0 END) as with_ticket,
            SUM(CASE WHEN has_ticket = 0 THEN 1 ELSE 0 END) as without_ticket,
            COUNT(*) as total
        FROM (
            SELECT DISTINCT ON (p.eventid)
                p.eventid,
                COALESCE(
                    (SELECT substring(hl.value FROM 'enterprises\\.161\\.3\\.10\\.105\\.6\\.0 = "([^"]*)"')
                     FROM history_log hl
                     WHERE hl.itemid = i.itemid AND hl.clock <= p.clock
                     ORDER BY hl.clock DESC LIMIT 1),
                    h.name
                ) AS entity,
                CASE WHEN pt.eventid IS NOT NULL THEN 1 ELSE 0 END as has_ticket
            FROM problem p
            JOIN triggers tr ON tr.triggerid = p.objectid
            JOIN functions f ON f.triggerid = tr.triggerid
            JOIN items i ON i.itemid = f.itemid
            JOIN hosts h ON h.hostid = i.hostid
            LEFT JOIN (
                SELECT DISTINCT eventid FROM problem_tag WHERE tag = 'znuny_ticket_nr'
            ) pt ON pt.eventid = p.eventid
            WHERE p.source = 0
              AND p.clock >= $StartEpoch
              AND p.clock <= $EndEpoch
              AND p.severity >= 2
            ORDER BY p.eventid
        ) sub
        GROUP BY entity
        ORDER BY total DESC
        LIMIT 10
    };

    return $SQL;
}

sub _ExecuteTopEntityQuery {
    my ( $Self, %Param ) = @_;

    my $ZabbixDBObject = $Kernel::OM->Get('Kernel::System::ZabbixDB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $StartEpoch = $Param{StartEpoch};
    my $EndEpoch   = $Param{EndEpoch};
    my $FilterDescription = $Param{FilterDescription} || '';

    my @Categories;
    my %BreakdownData;
    my %CategoryTotals;
    my %GrandTotal = ( WithTicket => 0, WithoutTicket => 0, Total => 0 );

    # Connect to Zabbix DB
    my $ConnectResult = $ZabbixDBObject->Connect();
    if (!$ConnectResult->{Success}) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_ExecuteTopEntityQuery: Failed to connect to Zabbix DB: " . ($ConnectResult->{ErrorMessage} || ''),
        );
        return (
            Categories        => \@Categories,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            GrandTotal        => \%GrandTotal,
            FilterDescription => $FilterDescription,
        );
    }

    my $SQL = $Self->_GetTopEntitySQL(
        StartEpoch => $StartEpoch,
        EndEpoch   => $EndEpoch,
    );

    my $STH = $ZabbixDBObject->{DBH}->prepare($SQL);
    if (!$STH || !$STH->execute()) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_ExecuteTopEntityQuery: Zabbix query failed: " . ($ZabbixDBObject->{DBH}->errstr || ''),
        );
        $ZabbixDBObject->Disconnect();
        return (
            Categories        => \@Categories,
            BreakdownData     => \%BreakdownData,
            CategoryTotals    => \%CategoryTotals,
            GrandTotal        => \%GrandTotal,
            FilterDescription => $FilterDescription,
        );
    }

    while ( my @Row = $STH->fetchrow_array() ) {
        my $Entity      = $Row[0] || 'Unknown';
        my $WithTicket   = $Row[1] || 0;
        my $WithoutTicket = $Row[2] || 0;
        my $Total        = $Row[3] || 0;

        push @Categories, $Entity;
        $BreakdownData{$Entity} = {
            WithTicket    => $WithTicket,
            WithoutTicket => $WithoutTicket,
        };
        $CategoryTotals{$Entity} = $Total;
        $GrandTotal{WithTicket}    += $WithTicket;
        $GrandTotal{WithoutTicket} += $WithoutTicket;
        $GrandTotal{Total}         += $Total;
    }
    $STH->finish();
    $ZabbixDBObject->Disconnect();

    return (
        Categories        => \@Categories,
        BreakdownData     => \%BreakdownData,
        CategoryTotals    => \%CategoryTotals,
        GrandTotal        => \%GrandTotal,
        FilterDescription => $FilterDescription,
        StartEpoch        => $StartEpoch,
        EndEpoch          => $EndEpoch,
    );
}

sub _GetHourlyTopEntityData {
    my ( $Self, %Param ) = @_;

    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Parse date parameter (YYYY-MM-DD)
    my $Date = $Param{Date} || '';
    if ( !$Date ) {
        my $CurrentTimestamp = $TimeObject->CurrentTimestamp();
        ($Date) = split / /, $CurrentTimestamp;
    }

    my ($Year, $Month, $Day) = split /-/, $Date;
    my $StartEpoch = mktime(0, 0, 0, $Day, $Month - 1, $Year - 1900);
    my $EndEpoch = mktime(59, 59, 23, $Day, $Month - 1, $Year - 1900);

    my @MonthNames = qw(January February March April May June July August September October November December);
    my $FilterDescription = sprintf("%s %d, %d (00:00 - 23:59)", $MonthNames[$Month - 1], $Day, $Year);

    return $Self->_ExecuteTopEntityQuery(
        StartEpoch        => $StartEpoch,
        EndEpoch          => $EndEpoch,
        FilterDescription => $FilterDescription,
    );
}

sub _GetDailyTopEntityData {
    my ( $Self, %Param ) = @_;

    # Parse week parameter (YYYY-WNN)
    my $Week = $Param{Week} || '';
    my ($Year, $WeekNum);

    if ( $Week =~ /^(\d{4})-W(\d{2})$/ ) {
        $Year = $1;
        $WeekNum = $2;
    }
    else {
        my @Now = localtime();
        $Year = $Now[5] + 1900;
        $WeekNum = strftime("%V", @Now);
    }

    my ($StartDate, $EndDate) = $Self->_GetWeekDateRange($Year, $WeekNum);

    my ($SY, $SM, $SD) = split /-/, $StartDate;
    my ($EY, $EM, $ED) = split /-/, $EndDate;

    my $StartEpoch = mktime(0, 0, 0, $SD, $SM - 1, $SY - 1900);
    my $EndEpoch = mktime(59, 59, 23, $ED, $EM - 1, $EY - 1900);

    my $FilterDescription = "Week $WeekNum, $Year ($StartDate to $EndDate)";

    return $Self->_ExecuteTopEntityQuery(
        StartEpoch        => $StartEpoch,
        EndEpoch          => $EndEpoch,
        FilterDescription => $FilterDescription,
    );
}

sub _GetWeeklyTopEntityData {
    my ( $Self, %Param ) = @_;

    # Parse month parameter (YYYY-MM)
    my $Month = $Param{Month} || '';
    my ($Year, $MonthNum);

    if ( $Month =~ /^(\d{4})-(\d{2})$/ ) {
        $Year = $1;
        $MonthNum = $2;
    }
    else {
        my @Now = localtime();
        $Year = $Now[5] + 1900;
        $MonthNum = sprintf("%02d", $Now[4] + 1);
    }

    my $LastDay = $Self->_GetLastDayOfMonth($Year, $MonthNum);
    my $StartEpoch = mktime(0, 0, 0, 1, $MonthNum - 1, $Year - 1900);
    my $EndEpoch = mktime(59, 59, 23, $LastDay, $MonthNum - 1, $Year - 1900);

    my @MonthNames = qw(January February March April May June July August September October November December);
    my $FilterDescription = "$MonthNames[$MonthNum - 1] $Year";

    return $Self->_ExecuteTopEntityQuery(
        StartEpoch        => $StartEpoch,
        EndEpoch          => $EndEpoch,
        FilterDescription => $FilterDescription,
    );
}

sub _GetMonthlyTopEntityData {
    my ( $Self, %Param ) = @_;

    # Get year range
    my $StartYear = $Param{StartYear} || '';
    my $EndYear = $Param{EndYear} || '';
    my $StartMonth = $Param{StartMonth} || 1;
    my $EndMonth = $Param{EndMonth} || 12;

    if (!$StartYear || !$EndYear) {
        my @Now = localtime();
        my $CurrentYear = $Now[5] + 1900;
        $StartYear ||= $CurrentYear;
        $EndYear ||= $CurrentYear;
    }

    my $LastDay = $Self->_GetLastDayOfMonth($EndYear, $EndMonth);
    my $StartEpoch = mktime(0, 0, 0, 1, $StartMonth - 1, $StartYear - 1900);
    my $EndEpoch = mktime(59, 59, 23, $LastDay, $EndMonth - 1, $EndYear - 1900);

    my @MonthNames = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my $FilterDescription = "$MonthNames[$StartMonth - 1] $StartYear - $MonthNames[$EndMonth - 1] $EndYear";

    return $Self->_ExecuteTopEntityQuery(
        StartEpoch        => $StartEpoch,
        EndEpoch          => $EndEpoch,
        FilterDescription => $FilterDescription,
    );
}

# Helper methods

sub _GetWeekDateRange {
    my ( $Self, $Year, $WeekNum ) = @_;

    # ISO 8601: Week 1 is the week containing January 4th.
    # Find the Monday on or before January 4th.
    my $Jan4 = mktime(0, 0, 12, 4, 0, $Year - 1900);
    my @Jan4Info = localtime($Jan4);
    my $Jan4Wday = $Jan4Info[6];  # 0=Sun, 1=Mon, ...
    my $DaysFromMonday = ($Jan4Wday == 0) ? 6 : $Jan4Wday - 1;
    my $Week1Monday = $Jan4 - ($DaysFromMonday * 86400);

    # Add weeks
    my $TargetMonday = $Week1Monday + (($WeekNum - 1) * 7 * 86400);
    my $TargetSunday = $TargetMonday + (6 * 86400);

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

1;
