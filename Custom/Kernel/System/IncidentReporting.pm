# --
# Copyright (C) 2025 MSST Lite
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::System::IncidentReporting;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Cache',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Ticket',
    'Kernel::Config',
);

=head1 NAME

Kernel::System::IncidentReporting - Incident reporting and analytics backend

=head1 DESCRIPTION

Provides reporting and analytics functionality for incidents including:
- Trending dashboards (daily/weekly/monthly/6-month views)
- Tabular reports with multi-dimensional filtering
- MSI handover analysis
- Export capabilities (CSV/Excel)

=head1 PUBLIC INTERFACE

=head2 new()

Create an object.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get configured cache TTL (default: 300 seconds = 5 minutes)
    $Self->{CacheTTL} = $Kernel::OM->Get('Kernel::Config')->Get('IncidentReporting::CacheTTL') || 300;

    # get configured page size (default: 100)
    $Self->{DefaultPageSize} = $Kernel::OM->Get('Kernel::Config')->Get('IncidentReporting::DefaultPageSize') || 100;

    return $Self;
}

=head2 GetTrendingData()

Get trending data for incidents based on time range.

    my $Result = $IncidentReportingObject->GetTrendingData(
        TimeRange => 'weekly',        # 'daily', 'weekly', 'monthly', '6months'
        StartDate => '2025-10-14',    # Optional for daily/weekly/monthly
        EndDate   => '2025-10-21',    # Optional
    );

Returns:
    {
        TimeRange => 'weekly',
        Total     => 342,
        Breakdown => [
            { Label => 'Monday', Count => 45, Percentage => 13.2 },
            { Label => 'Tuesday', Count => 52, Percentage => 15.2 },
            ...
        ],
        BySeverity => {
            P1 => 12,
            P2 => 89,
            P3 => 156,
            P4 => 85,
        },
        BySource => {
            LSMP   => 234,
            Manual => 108,
        },
    }

=cut

sub GetTrendingData {
    my ( $Self, %Param ) = @_;

    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    # check required parameters
    if ( !$Param{TimeRange} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Need TimeRange!',
        );
        return;
    }

    # validate time range
    my %ValidTimeRanges = (
        daily    => 1,
        weekly   => 1,
        monthly  => 1,
        '6months' => 1,
    );

    if ( !$ValidTimeRanges{ $Param{TimeRange} } ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Invalid TimeRange: $Param{TimeRange}",
        );
        return;
    }

    # generate cache key
    my $CacheKey = 'IncidentReporting::TrendingData::' . $Param{TimeRange};
    if ( $Param{StartDate} ) {
        $CacheKey .= '::' . $Param{StartDate};
    }
    if ( $Param{EndDate} ) {
        $CacheKey .= '::' . $Param{EndDate};
    }

    # check cache
    my $CachedData = $CacheObject->Get(
        Type => 'IncidentReporting',
        Key  => $CacheKey,
    );
    return $CachedData if $CachedData;

    # route to appropriate handler
    my $Result;
    if ( $Param{TimeRange} eq 'daily' ) {
        $Result = $Self->_GetDailyTrend(%Param);
    }
    elsif ( $Param{TimeRange} eq 'weekly' ) {
        $Result = $Self->_GetWeeklyTrend(%Param);
    }
    elsif ( $Param{TimeRange} eq 'monthly' ) {
        $Result = $Self->_GetMonthlyTrend(%Param);
    }
    elsif ( $Param{TimeRange} eq '6months' ) {
        $Result = $Self->_Get6MonthTrend(%Param);
    }

    return if !$Result;

    # cache the result
    $CacheObject->Set(
        Type  => 'IncidentReporting',
        Key   => $CacheKey,
        Value => $Result,
        TTL   => $Self->{CacheTTL},
    );

    return $Result;
}

=head2 GetTabularData()

Get tabular incident data with filtering and pagination.

    my $Result = $IncidentReportingObject->GetTabularData(
        StartDate => '2025-10-01',
        EndDate   => '2025-10-21',
        Filters   => {
            Severity => ['P1', 'P2'],
            Device   => '10.129.3.1',
            ProdCat  => 'T2',
            OpsCat   => 'Network',
            ResCat   => 'Hardware Failure',
            Source   => 'LSMP',           # 'LSMP' or 'Manual'
        },
        Page     => 1,
        PageSize => 100,
    );

Returns:
    {
        Tickets => [
            {
                TicketID        => 123,
                TicketNumber    => '2025102110000123',
                Title           => 'Network outage',
                Priority        => 'P1',
                Created         => '2025-10-21 10:30:00',
                Source          => 'LSMP',
                Device          => '10.129.3.1:MTS',
                ProdCat         => 'T2',
                OpsCat          => 'Network',
                ResCat          => 'Hardware Failure',
                MSITicketNumber => 'INC0012345',
            },
            ...
        ],
        TotalCount  => 1247,
        CurrentPage => 1,
        PageSize    => 100,
        TotalPages  => 13,
    }

=cut

sub GetTabularData {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # set defaults
    $Param{Page}      ||= 1;
    $Param{PageSize}  ||= $Self->{DefaultPageSize};
    $Param{TimeRange} ||= 'weekly';

    # build the query
    my ( $SQL, $CountSQL, @Bind ) = $Self->_BuildTabularQuery(%Param);

    return if !$SQL;

    # get total count first
    my $TotalCount = 0;
    return if !$DBObject->Prepare(
        SQL  => $CountSQL,
        Bind => \@Bind,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $TotalCount = $Row[0];
    }

    # calculate pagination
    my $Offset     = ( $Param{Page} - 1 ) * $Param{PageSize};
    my $TotalPages = int( ( $TotalCount + $Param{PageSize} - 1 ) / $Param{PageSize} );

    # add limit and offset to query
    $SQL .= " LIMIT ? OFFSET ?";
    push @Bind, \$Param{PageSize}, \$Offset;

    # execute main query
    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my @Tickets;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %Ticket = (
            TicketID        => $Row[0],
            TicketNumber    => $Row[1],
            Title           => $Row[2],
            Priority        => $Row[3],
            Created         => $Row[4],
            Source          => $Row[5] || 'Manual',
            Device          => $Row[6] || 'Unknown',
            ProdCat         => $Row[7] || '-',
            OpsCat          => $Row[8] || '-',
            ResCat          => $Row[9] || '-',
            MSITicketNumber => $Row[10] || '',
        );
        push @Tickets, \%Ticket;
    }

    return {
        Tickets     => \@Tickets,
        TotalCount  => $TotalCount,
        CurrentPage => $Param{Page},
        PageSize    => $Param{PageSize},
        TotalPages  => $TotalPages,
    };
}

=head2 GetMSIHandoverData()

Get MSI handover statistics and details.

    my $Result = $IncidentReportingObject->GetMSIHandoverData(
        StartDate => '2025-10-01',
        EndDate   => '2025-10-21',
        Filters   => {
            Priority => ['P1', 'P2'],
        },
    );

Returns:
    {
        TotalHandovers      => 45,
        PercentageOfTotal   => 13.2,
        ByPriority => {
            P1 => 5,
            P2 => 15,
            P3 => 20,
            P4 => 5,
        },
        ByCategory => {
            'Network'  => 20,
            'Hardware' => 15,
            ...
        },
        Details => [
            {
                TicketID         => 123,
                TicketNumber     => '2025102110000123',
                Priority         => 'P1',
                Category         => 'Network',
                EscalationDate   => '2025-10-21 10:30:00',
                TimeWithMSI      => 3600,  # seconds
                MSITicketNumber  => 'INC0012345',
            },
            ...
        ],
    }

=cut

sub GetMSIHandoverData {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # calculate date range from TimeRange
    my ( $StartDate, $EndDate ) = $Self->_CalculateDateRange( TimeRange => $Param{TimeRange} || 'weekly' );

    # build base query for MSI handovers - categories from dynamic fields
    # Calculate Time with MSI:
    # - For OPEN tickets (state_type_id != 3): NOW - escalation_time
    # - For CLOSED tickets (state_type_id = 3): close_time - escalation_time
    # Escalation time is when MSITicketNumber field was set (from ticket_history)
    my $SQL = "
        SELECT
            t.id,
            t.tn,
            p.name AS priority,
            df_prodcat.value_text AS prod_cat,
            df_opscat.value_text AS ops_cat,
            df_msi.value_text AS msi_ticket_number,
            COALESCE(log.create_time, escalation_hist.create_time) AS escalation_date,
            CASE
                WHEN ts.type_id = 3 THEN
                    EXTRACT(EPOCH FROM (close_hist.create_time - COALESCE(log.create_time, escalation_hist.create_time)))
                ELSE
                    EXTRACT(EPOCH FROM (NOW() - COALESCE(log.create_time, escalation_hist.create_time)))
            END AS time_with_msi,
            t.create_time
        FROM ticket t
        INNER JOIN ticket_priority p ON p.id = t.ticket_priority_id
        INNER JOIN ticket_state ts ON ts.id = t.ticket_state_id
        INNER JOIN dynamic_field_value df_msi
            ON df_msi.object_id = t.id
            AND df_msi.field_id = (SELECT id FROM dynamic_field WHERE name = 'MSITicketNumber')
        LEFT JOIN dynamic_field_value df_prodcat
            ON df_prodcat.object_id = t.id
            AND df_prodcat.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat2')
        LEFT JOIN dynamic_field_value df_opscat
            ON df_opscat.object_id = t.id
            AND df_opscat.field_id = (SELECT id FROM dynamic_field WHERE name = 'OperationalCat1')
        LEFT JOIN dynamic_field_value df_rescat
            ON df_rescat.object_id = t.id
            AND df_rescat.field_id = (SELECT id FROM dynamic_field WHERE name = 'ResolutionCat1')
        LEFT JOIN dynamic_field_value df_device
            ON df_device.object_id = t.id
            AND df_device.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        LEFT JOIN ebonding_api_log log
            ON log.incident_id = t.id
            AND log.action = 'CreateIncident'
        LEFT JOIN LATERAL (
            SELECT create_time
            FROM ticket_history
            WHERE ticket_id = t.id
                AND history_type_id = (SELECT id FROM ticket_history_type WHERE name = 'TicketDynamicFieldUpdate')
                AND name LIKE '%%FieldName%%MSITicketNumber%%Value%%'
            ORDER BY create_time ASC
            LIMIT 1
        ) escalation_hist ON true
        LEFT JOIN LATERAL (
            SELECT create_time
            FROM ticket_history
            WHERE ticket_id = t.id
                AND history_type_id = (SELECT id FROM ticket_history_type WHERE name = 'StateUpdate')
                AND state_id IN (SELECT id FROM ticket_state WHERE type_id = 3)
            ORDER BY create_time DESC
            LIMIT 1
        ) close_hist ON true
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND df_msi.value_text IS NOT NULL
            AND df_msi.value_text != ''
    ";

    my @Bind;

    # add date filters based on time range
    if ( $StartDate ) {
        $SQL .= " AND t.create_time >= ?";
        push @Bind, \$StartDate;
    }
    if ( $EndDate ) {
        my $EndDateTime = $EndDate . ' 23:59:59';
        $SQL .= " AND t.create_time <= ?";
        push @Bind, \$EndDateTime;
    }

    $SQL .= " ORDER BY t.create_time DESC";

    # execute query
    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my @Details;
    my %ByPriority;
    my %ByCategory;
    my $TotalHandovers = 0;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %Detail = (
            TicketID        => $Row[0],
            TicketNumber    => $Row[1],
            Priority        => $Row[2],
            ProdCat         => $Row[3] || '-',
            OpsCat          => $Row[4] || '-',
            MSITicketNumber => $Row[5],
            EscalationDate  => $Row[6] || $Row[8],  # Use escalation date or ticket create time as fallback
            TimeWithMSI     => defined $Row[7] ? $Row[7] : 0,  # Time in seconds
        );
        push @Details, \%Detail;

        # aggregate counts
        $TotalHandovers++;
        $ByPriority{ $Detail{Priority} }++;
        if ( $Detail{OpsCat} && $Detail{OpsCat} ne '-' ) {
            $ByCategory{ $Detail{OpsCat} }++;
        }
    }

    # get total incidents for percentage calculation
    my $TotalIncidents = $Self->_GetTotalIncidents(
        StartDate => $Param{StartDate},
        EndDate   => $Param{EndDate},
    );

    my $PercentageOfTotal = 0;
    if ( $TotalIncidents > 0 ) {
        $PercentageOfTotal = sprintf( "%.2f", ( $TotalHandovers / $TotalIncidents ) * 100 );
    }

    return {
        TotalHandovers    => $TotalHandovers,
        PercentageOfTotal => $PercentageOfTotal,
        ByPriority        => \%ByPriority,
        ByCategory        => \%ByCategory,
        Details           => \@Details,
    };
}

=head2 ExportToCSV()

Export tabular data to CSV format.

    my $CSV = $IncidentReportingObject->ExportToCSV(
        Data => $TabularData,
    );

=cut

sub ExportToCSV {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    if ( !$Param{Data} || !$Param{Data}->{Tickets} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Need Data with Tickets!',
        );
        return;
    }

    # CSV header
    my @Headers = (
        'Ticket Number',
        'Title',
        'Priority',
        'Created',
        'Source',
        'Device',
        'Product Category',
        'Operational Category',
        'Resolution Category',
        'MSI Ticket Number',
    );

    my $CSV = join( ',', map { qq{"$_"} } @Headers ) . "\n";

    # CSV rows
    for my $Ticket ( @{ $Param{Data}->{Tickets} } ) {
        my @Row = (
            $Ticket->{TicketNumber},
            $Ticket->{Title},
            $Ticket->{Priority},
            $Ticket->{Created},
            $Ticket->{Source},
            $Ticket->{Device},
            $Ticket->{ProdCat},
            $Ticket->{OpsCat},
            $Ticket->{ResCat},
            $Ticket->{MSITicketNumber} || '',
        );

        # escape quotes and wrap in quotes
        @Row = map {
            my $val = $_;
            $val =~ s/"/""/g;  # escape quotes
            qq{"$val"};
        } @Row;

        $CSV .= join( ',', @Row ) . "\n";
    }

    return $CSV;
}

=head2 GetTrendChartData()

Get trend chart data for D3.js visualization with priority breakdown.

    my $ChartData = $IncidentReportingObject->GetTrendChartData(
        TimeRange => 'weekly',  # 'daily', 'weekly', 'monthly', '6months'
    );

Returns:
    {
        Labels => ['Mon', 'Tue', 'Wed', ...],
        Series => {
            P1 => [5, 3, 7, ...],
            P2 => [15, 12, 18, ...],
            P3 => [25, 30, 22, ...],
            P4 => [10, 8, 12, ...],
        },
        Total => [55, 53, 59, ...],
    }

=cut

sub GetTrendChartData {
    my ( $Self, %Param ) = @_;

    # get trending data
    my $TrendData = $Self->GetTrendingData(%Param);
    return if !$TrendData;

    # extract labels from breakdown
    my @Labels = map { $_->{Label} } @{ $TrendData->{Breakdown} };

    # we need to get priority breakdown per time period
    # this requires a more detailed query
    my ( $StartDate, $EndDate ) = $Self->_CalculateDateRange( TimeRange => $Param{TimeRange} || 'weekly' );

    my %SeriesData = (
        P1 => [],
        P2 => [],
        P3 => [],
        P4 => [],
    );
    my @TotalData;

    # get data per period with priority breakdown
    my $TimeGroupBy = $Self->_GetTimeGroupByClause( $Param{TimeRange} );

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $SQL = "
        SELECT
            $TimeGroupBy AS period,
            p.name AS priority,
            COUNT(*) AS count
        FROM ticket t
        INNER JOIN ticket_priority p ON p.id = t.ticket_priority_id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
    ";

    my @Bind;
    if ( $StartDate ) {
        $SQL .= " AND t.create_time >= ?";
        push @Bind, \$StartDate;
    }
    if ( $EndDate ) {
        my $EndDateTime = $EndDate . ' 23:59:59';
        $SQL .= " AND t.create_time <= ?";
        push @Bind, \$EndDateTime;
    }

    $SQL .= " GROUP BY period, p.name ORDER BY period";

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my %PeriodData;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Period   = $Row[0];
        my $Priority = $Self->_NormalizePriority($Row[1]);
        my $Count    = $Row[2];

        $PeriodData{$Period} ||= { P1 => 0, P2 => 0, P3 => 0, P4 => 0 };
        $PeriodData{$Period}->{$Priority} = $Count if $Priority;
    }

    # build series arrays matching labels
    for my $i ( 0 .. $#Labels ) {
        my $Period = $Self->_GetPeriodKey( $Param{TimeRange}, $i );
        my $Data = $PeriodData{$Period} || { P1 => 0, P2 => 0, P3 => 0, P4 => 0 };

        push @{ $SeriesData{P1} }, $Data->{P1};
        push @{ $SeriesData{P2} }, $Data->{P2};
        push @{ $SeriesData{P3} }, $Data->{P3};
        push @{ $SeriesData{P4} }, $Data->{P4};
        push @TotalData, $Data->{P1} + $Data->{P2} + $Data->{P3} + $Data->{P4};
    }

    return {
        Labels => \@Labels,
        Series => \%SeriesData,
        Total  => \@TotalData,
    };
}

=head2 GetSourceChartData()

Get source distribution data for donut chart.

Returns:
    {
        Labels => ['Event Monitoring', 'Manual'],
        Values => [234, 108],
        Total  => 342,
    }

=cut

sub GetSourceChartData {
    my ( $Self, %Param ) = @_;

    my $SourceData = $Self->GetIncidentsBySource(%Param);
    return if !$SourceData;

    return {
        Labels => ['Event Monitoring', 'Manual'],
        Values => [$SourceData->{'Event Monitoring'} || 0, $SourceData->{Manual} || 0],
        Total  => $SourceData->{Total} || 0,
    };
}

=head2 GetStateChartData()

Get state distribution data for stacked bar chart.

Returns:
    {
        States => ['new', 'assigned', 'in progress', 'resolved', 'closed'],
        Counts => [45, 78, 92, 156, 89],
    }

=cut

sub GetStateChartData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my ( $StartDate, $EndDate ) = $Self->_CalculateDateRange( TimeRange => $Param{TimeRange} || 'weekly' );

    my $SQL = "
        SELECT
            ts.name AS state,
            COUNT(*) AS count
        FROM ticket t
        INNER JOIN ticket_state ts ON ts.id = t.ticket_state_id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
    ";

    my @Bind;
    if ( $StartDate ) {
        $SQL .= " AND t.create_time >= ?";
        push @Bind, \$StartDate;
    }
    if ( $EndDate ) {
        my $EndDateTime = $EndDate . ' 23:59:59';
        $SQL .= " AND t.create_time <= ?";
        push @Bind, \$EndDateTime;
    }

    $SQL .= " GROUP BY ts.name ORDER BY ts.name";

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my @States;
    my @Counts;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @States, $Row[0];
        push @Counts, $Row[1];
    }

    return {
        States => \@States,
        Counts => \@Counts,
    };
}

=head2 GetTopDevicesChartData()

Get top 10 devices/CIs by incident count for horizontal bar chart.

Returns:
    {
        Devices => ['10.129.3.1:MTS', '10.129.3.2:MTS', ...],
        Counts  => [45, 38, 32, ...],
    }

=cut

sub GetTopDevicesChartData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my ( $StartDate, $EndDate ) = $Self->_CalculateDateRange( TimeRange => $Param{TimeRange} || 'weekly' );

    my $SQL = "
        SELECT
            df_device.value_text AS device,
            COUNT(*) AS count
        FROM ticket t
        LEFT JOIN dynamic_field_value df_device
            ON df_device.object_id = t.id
            AND df_device.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND df_device.value_text IS NOT NULL
            AND df_device.value_text != ''
    ";

    my @Bind;
    if ( $StartDate ) {
        $SQL .= " AND t.create_time >= ?";
        push @Bind, \$StartDate;
    }
    if ( $EndDate ) {
        my $EndDateTime = $EndDate . ' 23:59:59';
        $SQL .= " AND t.create_time <= ?";
        push @Bind, \$EndDateTime;
    }

    $SQL .= " GROUP BY df_device.value_text ORDER BY count DESC LIMIT 10";

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my @Devices;
    my @Counts;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Devices, $Row[0];
        push @Counts, $Row[1];
    }

    return {
        Devices => \@Devices,
        Counts  => \@Counts,
    };
}

=head2 GetResolutionTimeHistogramData()

Get resolution time distribution for histogram chart.

Returns:
    {
        Buckets => ['0-1h', '1-4h', '4-24h', '1-3d', '3-7d', '>7d'],
        Counts  => [25, 45, 78, 92, 34, 12],
    }

=cut

sub GetResolutionTimeHistogramData {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my ( $StartDate, $EndDate ) = $Self->_CalculateDateRange( TimeRange => $Param{TimeRange} || 'weekly' );

    # Calculate resolution time = close_time - create_time for closed tickets
    my $SQL = "
        SELECT
            CASE
                WHEN EXTRACT(EPOCH FROM (close_hist.create_time - t.create_time)) <= 3600 THEN '0-1h'
                WHEN EXTRACT(EPOCH FROM (close_hist.create_time - t.create_time)) <= 14400 THEN '1-4h'
                WHEN EXTRACT(EPOCH FROM (close_hist.create_time - t.create_time)) <= 86400 THEN '4-24h'
                WHEN EXTRACT(EPOCH FROM (close_hist.create_time - t.create_time)) <= 259200 THEN '1-3d'
                WHEN EXTRACT(EPOCH FROM (close_hist.create_time - t.create_time)) <= 604800 THEN '3-7d'
                ELSE '>7d'
            END AS bucket,
            COUNT(*) AS count
        FROM ticket t
        INNER JOIN ticket_state ts ON ts.id = t.ticket_state_id
        LEFT JOIN LATERAL (
            SELECT create_time
            FROM ticket_history
            WHERE ticket_id = t.id
                AND history_type_id = (SELECT id FROM ticket_history_type WHERE name = 'StateUpdate')
                AND state_id IN (SELECT id FROM ticket_state WHERE type_id = 3)
            ORDER BY create_time DESC
            LIMIT 1
        ) close_hist ON true
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND ts.type_id = 3
            AND close_hist.create_time IS NOT NULL
    ";

    my @Bind;
    if ( $StartDate ) {
        $SQL .= " AND t.create_time >= ?";
        push @Bind, \$StartDate;
    }
    if ( $EndDate ) {
        my $EndDateTime = $EndDate . ' 23:59:59';
        $SQL .= " AND t.create_time <= ?";
        push @Bind, \$EndDateTime;
    }

    $SQL .= " GROUP BY bucket";

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my %BucketData;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $BucketData{ $Row[0] } = $Row[1];
    }

    # ensure all buckets are present in order
    my @BucketOrder = ('0-1h', '1-4h', '4-24h', '1-3d', '3-7d', '>7d');
    my @Counts;
    for my $Bucket ( @BucketOrder ) {
        push @Counts, $BucketData{$Bucket} || 0;
    }

    return {
        Buckets => \@BucketOrder,
        Counts  => \@Counts,
    };
}

=head2 GetIncidentsBySource()

Get incident counts broken down by source (LSMP vs Manual).

    my $Result = $IncidentReportingObject->GetIncidentsBySource(
        StartDate => '2025-10-01',
        EndDate   => '2025-10-21',
    );

Returns:
    {
        LSMP   => 234,
        Manual => 108,
        Total  => 342,
    }

=cut

sub GetIncidentsBySource {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $SQL = "
        SELECT
            COALESCE(df_source.value_text, 'Manual') AS source,
            COUNT(*) AS count
        FROM ticket t
        LEFT JOIN dynamic_field_value df_source
            ON df_source.object_id = t.id
            AND df_source.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
    ";

    my @Bind;

    if ( $Param{StartDate} ) {
        $SQL .= " AND t.create_time >= ?";
        push @Bind, \$Param{StartDate};
    }
    if ( $Param{EndDate} ) {
        my $EndDateTime = $Param{EndDate} . ' 23:59:59';
        $SQL .= " AND t.create_time <= ?";
        push @Bind, \$EndDateTime;
    }

    $SQL .= " GROUP BY source";

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my %Result = (
        LSMP   => 0,
        Manual => 0,
        Total  => 0,
    );

    my %SourceMapping;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Source = $Row[0] || 'Manual';
        my $Count  = $Row[1];

        # Map actual source values to "Manual" vs "Event Monitoring"
        # Zabbix → Event Monitoring
        # Event Monitoring → Event Monitoring
        # Direct Input → Manual
        my $MappedSource = 'Manual';
        if ( $Source eq 'Zabbix' || $Source eq 'Event Monitoring' ) {
            $MappedSource = 'Event Monitoring';
        }

        $SourceMapping{$MappedSource} ||= 0;
        $SourceMapping{$MappedSource} += $Count;
        $Result{Total} += $Count;
    }

    # Set results with the two expected keys
    $Result{Manual} = $SourceMapping{Manual} || 0;
    $Result{'Event Monitoring'} = $SourceMapping{'Event Monitoring'} || 0;

    # Also provide LSMP as alias for Event Monitoring for backwards compatibility
    $Result{LSMP} = $Result{'Event Monitoring'};

    return \%Result;
}

# =============================================================================
# PRIVATE METHODS
# =============================================================================

=begin Internal:

=head2 _GetDailyTrend()

Get daily trending data with hourly breakdown.

=cut

sub _GetDailyTrend {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # default to today if no date specified
    my $Date = $Param{StartDate} || $Self->_GetCurrentDate();

    my $SQL = "
        SELECT
            EXTRACT(HOUR FROM t.create_time) AS hour,
            COUNT(*) AS count,
            p.name AS priority
        FROM ticket t
        INNER JOIN ticket_priority p ON p.id = t.ticket_priority_id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND DATE(t.create_time) = ?
        GROUP BY hour, p.name
        ORDER BY hour
    ";

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$Date ],
    );

    my %HourlyData;
    my %BySeverity = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );
    my $Total = 0;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Hour     = $Row[0];
        my $Count    = $Row[1];
        my $Priority = $Row[2];

        # Normalize priority (P1-Critical -> P1)
        my $PriorityKey = $Self->_NormalizePriority($Priority);

        $HourlyData{$Hour} ||= 0;
        $HourlyData{$Hour} += $Count;
        $BySeverity{$PriorityKey} += $Count if $PriorityKey;
        $Total += $Count;
    }

    # build breakdown array (0-23 hours)
    my @Breakdown;
    for my $Hour ( 0 .. 23 ) {
        my $Count = $HourlyData{$Hour} || 0;
        my $Percentage = $Total > 0 ? sprintf( "%.2f", ( $Count / $Total ) * 100 ) : 0;
        push @Breakdown, {
            Label      => sprintf( "%02d:00", $Hour ),
            Count      => $Count,
            Percentage => $Percentage,
        };
    }

    # get source breakdown
    my $BySource = $Self->GetIncidentsBySource(
        StartDate => $Date,
        EndDate   => $Date,
    );

    return {
        TimeRange  => 'daily',
        Date       => $Date,
        Total      => $Total,
        Breakdown  => \@Breakdown,
        BySeverity => \%BySeverity,
        BySource   => $BySource,
    };
}

=head2 _GetWeeklyTrend()

Get weekly trending data with daily breakdown.

=cut

sub _GetWeeklyTrend {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # calculate week start and end
    my ( $WeekStart, $WeekEnd ) = $Self->_GetWeekRange( $Param{StartDate} );

    my $SQL = "
        SELECT
            TO_CHAR(t.create_time, 'Day') AS weekday,
            EXTRACT(DOW FROM t.create_time) AS dow,
            COUNT(*) AS count,
            p.name AS priority
        FROM ticket t
        INNER JOIN ticket_priority p ON p.id = t.ticket_priority_id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND t.create_time >= ?
            AND t.create_time < ?
        GROUP BY weekday, dow, p.name
        ORDER BY dow
    ";

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$WeekStart, \$WeekEnd ],
    );

    my %DailyData;
    my %BySeverity = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );
    my $Total = 0;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Weekday  = $Row[0];
        my $DOW      = $Row[1];
        my $Count    = $Row[2];
        my $Priority = $Row[3];

        # Normalize priority (P1-Critical -> P1)
        my $PriorityKey = $Self->_NormalizePriority($Priority);

        $Weekday =~ s/\s+$//;  # trim trailing spaces
        $DailyData{$DOW} ||= { Label => $Weekday, Count => 0 };
        $DailyData{$DOW}->{Count} += $Count;
        $BySeverity{$PriorityKey} += $Count if $PriorityKey;
        $Total += $Count;
    }

    # build breakdown array (0=Sunday, 1=Monday, ..., 6=Saturday)
    my @WeekdayLabels = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
    my @Breakdown;
    for my $DOW ( 0 .. 6 ) {
        my $Data = $DailyData{$DOW} || { Label => $WeekdayLabels[$DOW], Count => 0 };
        my $Percentage = $Total > 0 ? sprintf( "%.2f", ( $Data->{Count} / $Total ) * 100 ) : 0;
        push @Breakdown, {
            Label      => $Data->{Label},
            Count      => $Data->{Count},
            Percentage => $Percentage,
        };
    }

    # get source breakdown
    my $BySource = $Self->GetIncidentsBySource(
        StartDate => $WeekStart,
        EndDate   => $WeekEnd,
    );

    return {
        TimeRange  => 'weekly',
        WeekStart  => $WeekStart,
        WeekEnd    => $WeekEnd,
        Total      => $Total,
        Breakdown  => \@Breakdown,
        BySeverity => \%BySeverity,
        BySource   => $BySource,
    };
}

=head2 _GetMonthlyTrend()

Get monthly trending data with weekly breakdown.

=cut

sub _GetMonthlyTrend {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # calculate month start and end
    my ( $MonthStart, $MonthEnd ) = $Self->_GetMonthRange( $Param{StartDate} );

    my $SQL = "
        SELECT
            EXTRACT(WEEK FROM t.create_time) - EXTRACT(WEEK FROM ?::date) + 1 AS week_num,
            COUNT(*) AS count,
            p.name AS priority
        FROM ticket t
        INNER JOIN ticket_priority p ON p.id = t.ticket_priority_id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND t.create_time >= ?
            AND t.create_time < ?
        GROUP BY week_num, p.name
        ORDER BY week_num
    ";

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$MonthStart, \$MonthStart, \$MonthEnd ],
    );

    my %WeeklyData;
    my %BySeverity = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );
    my $Total = 0;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $WeekNum  = $Row[0];
        my $Count    = $Row[1];
        my $Priority = $Row[2];

        # Normalize priority (P1-Critical -> P1)
        my $PriorityKey = $Self->_NormalizePriority($Priority);

        $WeeklyData{$WeekNum} ||= 0;
        $WeeklyData{$WeekNum} += $Count;
        $BySeverity{$PriorityKey} += $Count if $PriorityKey;
        $Total += $Count;
    }

    # build breakdown array
    my @Breakdown;
    my $MaxWeek = ( sort { $b <=> $a } keys %WeeklyData )[0] || 4;
    for my $Week ( 1 .. $MaxWeek ) {
        my $Count = $WeeklyData{$Week} || 0;
        my $Percentage = $Total > 0 ? sprintf( "%.2f", ( $Count / $Total ) * 100 ) : 0;
        push @Breakdown, {
            Label      => "Week $Week",
            Count      => $Count,
            Percentage => $Percentage,
        };
    }

    # get source breakdown
    my $BySource = $Self->GetIncidentsBySource(
        StartDate => $MonthStart,
        EndDate   => $MonthEnd,
    );

    return {
        TimeRange  => 'monthly',
        MonthStart => $MonthStart,
        MonthEnd   => $MonthEnd,
        Total      => $Total,
        Breakdown  => \@Breakdown,
        BySeverity => \%BySeverity,
        BySource   => $BySource,
    };
}

=head2 _Get6MonthTrend()

Get 6-month trending data with monthly breakdown.

=cut

sub _Get6MonthTrend {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # calculate date range (last 6 months including current month)
    my $EndDate   = $Self->_GetCurrentDate();
    my $StartDate = $Self->_GetDateMinusMonths( 5 );  # 5 months ago + current = 6 months

    my $SQL = "
        SELECT
            TO_CHAR(t.create_time, 'YYYY-MM') AS month,
            COUNT(*) AS count,
            p.name AS priority
        FROM ticket t
        INNER JOIN ticket_priority p ON p.id = t.ticket_priority_id
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
            AND t.create_time >= ?
            AND t.create_time <= ?
        GROUP BY month, p.name
        ORDER BY month
    ";

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$StartDate, \$EndDate ],
    );

    my %MonthlyData;
    my %BySeverity = ( P1 => 0, P2 => 0, P3 => 0, P4 => 0 );
    my $Total = 0;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Month    = $Row[0];
        my $Count    = $Row[1];
        my $Priority = $Row[2];

        # Normalize priority (P1-Critical -> P1)
        my $PriorityKey = $Self->_NormalizePriority($Priority);

        $MonthlyData{$Month} ||= 0;
        $MonthlyData{$Month} += $Count;
        $BySeverity{$PriorityKey} += $Count if $PriorityKey;
        $Total += $Count;
    }

    # build breakdown array for last 6 months
    my @Breakdown;
    my @MonthLabels = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    for my $i ( 0 .. 5 ) {
        my $MonthDate = $Self->_GetDateMinusMonths( 5 - $i );
        my ($Year, $Month) = split /-/, $MonthDate;
        my $MonthKey = "$Year-$Month";
        my $Count = $MonthlyData{$MonthKey} || 0;
        my $Percentage = $Total > 0 ? sprintf( "%.2f", ( $Count / $Total ) * 100 ) : 0;

        push @Breakdown, {
            Label      => $MonthLabels[ $Month - 1 ] . " $Year",
            Count      => $Count,
            Percentage => $Percentage,
        };
    }

    # get source breakdown
    my $BySource = $Self->GetIncidentsBySource(
        StartDate => $StartDate,
        EndDate   => $EndDate,
    );

    return {
        TimeRange  => '6months',
        StartDate  => $StartDate,
        EndDate    => $EndDate,
        Total      => $Total,
        Breakdown  => \@Breakdown,
        BySeverity => \%BySeverity,
        BySource   => $BySource,
    };
}

=head2 _BuildTabularQuery()

Build SQL query for tabular data with filters.

=cut

sub _BuildTabularQuery {
    my ( $Self, %Param ) = @_;

    # calculate date range from TimeRange
    my ( $StartDate, $EndDate ) = $Self->_CalculateDateRange( TimeRange => $Param{TimeRange} || 'weekly' );

    # base query - categories from dynamic fields
    my $SQL = "
        SELECT
            t.id,
            t.tn,
            t.title,
            p.name AS priority,
            t.create_time,
            df_source.value_text AS source,
            df_device.value_text AS device,
            df_prodcat.value_text AS prod_cat,
            df_opscat.value_text AS ops_cat,
            df_rescat.value_text AS res_cat,
            df_msi.value_text AS msi_ticket_number
        FROM ticket t
        INNER JOIN ticket_priority p ON p.id = t.ticket_priority_id
        LEFT JOIN dynamic_field_value df_source
            ON df_source.object_id = t.id
            AND df_source.field_id = (SELECT id FROM dynamic_field WHERE name = 'IncidentSource')
        LEFT JOIN dynamic_field_value df_device
            ON df_device.object_id = t.id
            AND df_device.field_id = (SELECT id FROM dynamic_field WHERE name = 'CI')
        LEFT JOIN dynamic_field_value df_prodcat
            ON df_prodcat.object_id = t.id
            AND df_prodcat.field_id = (SELECT id FROM dynamic_field WHERE name = 'ProductCat2')
        LEFT JOIN dynamic_field_value df_opscat
            ON df_opscat.object_id = t.id
            AND df_opscat.field_id = (SELECT id FROM dynamic_field WHERE name = 'OperationalCat1')
        LEFT JOIN dynamic_field_value df_rescat
            ON df_rescat.object_id = t.id
            AND df_rescat.field_id = (SELECT id FROM dynamic_field WHERE name = 'ResolutionCat1')
        LEFT JOIN dynamic_field_value df_msi
            ON df_msi.object_id = t.id
            AND df_msi.field_id = (SELECT id FROM dynamic_field WHERE name = 'MSITicketNumber')
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
    ";

    my @Bind;

    # add date filters based on time range
    if ( $StartDate ) {
        $SQL .= " AND t.create_time >= ?";
        push @Bind, \$StartDate;
    }
    if ( $EndDate ) {
        my $EndDateTime = $EndDate . ' 23:59:59';
        $SQL .= " AND t.create_time <= ?";
        push @Bind, \$EndDateTime;
    }

    # order by
    $SQL .= " ORDER BY t.create_time DESC";

    # build count query - replace only the outermost SELECT
    my $CountSQL = $SQL;
    # Match only up to the first FROM at the main level (not in subqueries)
    $CountSQL =~ s/^(\s*)SELECT\s+.+?\s+FROM\s+ticket/$1SELECT COUNT(DISTINCT t.id) FROM ticket/s;
    $CountSQL =~ s/ORDER BY .+$//s;

    return ( $SQL, $CountSQL, @Bind );
}

=head2 _GetTotalIncidents()

Get total incident count for a date range.

=cut

sub _GetTotalIncidents {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $SQL = "
        SELECT COUNT(*)
        FROM ticket t
        WHERE t.type_id = (SELECT id FROM ticket_type WHERE name = 'Incident')
    ";

    my @Bind;

    if ( $Param{StartDate} ) {
        $SQL .= " AND t.create_time >= ?";
        push @Bind, \$Param{StartDate};
    }
    if ( $Param{EndDate} ) {
        my $EndDateTime = $Param{EndDate} . ' 23:59:59';
        $SQL .= " AND t.create_time <= ?";
        push @Bind, \$EndDateTime;
    }

    return 0 if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my $Count = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Count = $Row[0];
    }

    return $Count;
}

=head2 _GetCurrentDate()

Get current date in YYYY-MM-DD format.

=cut

sub _GetCurrentDate {
    my ( $Self, %Param ) = @_;

    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = localtime();
    $Year  += 1900;
    $Month += 1;

    return sprintf( "%04d-%02d-%02d", $Year, $Month, $Day );
}

=head2 _GetWeekRange()

Get week start and end dates.

=cut

sub _GetWeekRange {
    my ( $Self, $Date ) = @_;

    $Date ||= $Self->_GetCurrentDate();

    # calculate week start (Monday) and end (Sunday)
    # This is a simplified version; you may want to use DateTime module
    my $WeekStart = $Date;
    my $WeekEnd   = $Date;

    # For now, return the provided date as both start and end
    # TODO: Implement proper week calculation
    return ( $WeekStart, $WeekEnd );
}

=head2 _GetMonthRange()

Get month start and end dates.

=cut

sub _GetMonthRange {
    my ( $Self, $Date ) = @_;

    $Date ||= $Self->_GetCurrentDate();

    my ( $Year, $Month, $Day ) = split /-/, $Date;

    my $MonthStart = sprintf( "%04d-%02d-01", $Year, $Month );

    # calculate last day of month
    my @DaysInMonth = ( 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );

    # check for leap year
    if ( $Month == 2 && ( $Year % 4 == 0 && ( $Year % 100 != 0 || $Year % 400 == 0 ) ) ) {
        $DaysInMonth[1] = 29;
    }

    my $LastDay  = $DaysInMonth[ $Month - 1 ];
    my $MonthEnd = sprintf( "%04d-%02d-%02d", $Year, $Month, $LastDay );

    return ( $MonthStart, $MonthEnd );
}

=head2 _GetDateMinusMonths()

Get date N months ago.

=cut

sub _GetDateMinusMonths {
    my ( $Self, $MonthsAgo ) = @_;

    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = localtime();
    $Year  += 1900;
    $Month += 1;

    # subtract months
    $Month -= $MonthsAgo;
    while ( $Month <= 0 ) {
        $Month += 12;
        $Year--;
    }

    return sprintf( "%04d-%02d-01", $Year, $Month );
}

=head2 _CalculateDateRange()

Calculate start and end dates based on time range selection.

=cut

sub _CalculateDateRange {
    my ( $Self, %Param ) = @_;

    my $TimeRange = $Param{TimeRange} || 'weekly';

    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = localtime();
    $Year  += 1900;
    $Month += 1;

    my $Today = sprintf( "%04d-%02d-%02d", $Year, $Month, $Day );
    my $StartDate = $Today;
    my $EndDate = $Today;

    if ( $TimeRange eq 'daily' ) {
        # Today only
        $StartDate = $Today;
        $EndDate = $Today;
    }
    elsif ( $TimeRange eq 'weekly' ) {
        # Last 7 days
        my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = localtime( time - (7 * 24 * 60 * 60) );
        $Year  += 1900;
        $Month += 1;
        $StartDate = sprintf( "%04d-%02d-%02d", $Year, $Month, $Day );
        $EndDate = $Today;
    }
    elsif ( $TimeRange eq 'monthly' ) {
        # Current calendar month (from 1st to today)
        $StartDate = sprintf( "%04d-%02d-01", $Year, $Month );
        $EndDate = $Today;
    }
    elsif ( $TimeRange eq '6months' ) {
        # Last 6 months
        my $StartMonth = $Month - 6;
        my $StartYear = $Year;
        while ( $StartMonth <= 0 ) {
            $StartMonth += 12;
            $StartYear--;
        }
        $StartDate = sprintf( "%04d-%02d-01", $StartYear, $StartMonth );
        $EndDate = $Today;
    }

    return ( $StartDate, $EndDate );
}

=head2 _NormalizePriority()

Normalize priority name from "P1-Critical" to "P1".

=cut

sub _NormalizePriority {
    my ( $Self, $Priority ) = @_;

    return '' if !$Priority;

    # Extract P1 from "P1-Critical", P2 from "P2-High", etc.
    if ( $Priority =~ /^(P[1-4])/ ) {
        return $1;
    }

    return '';
}

=head2 _GetTimeGroupByClause()

Get SQL GROUP BY clause for different time ranges.

=cut

sub _GetTimeGroupByClause {
    my ( $Self, $TimeRange ) = @_;

    $TimeRange ||= 'weekly';

    my %GroupByClauses = (
        daily    => "EXTRACT(HOUR FROM t.create_time)",
        weekly   => "EXTRACT(DOW FROM t.create_time)",
        monthly  => "EXTRACT(WEEK FROM t.create_time) - EXTRACT(WEEK FROM DATE_TRUNC('month', t.create_time)) + 1",
        '6months' => "TO_CHAR(t.create_time, 'YYYY-MM')",
    );

    return $GroupByClauses{$TimeRange} || $GroupByClauses{weekly};
}

=head2 _GetPeriodKey()

Get period key for mapping chart data to labels.

=cut

sub _GetPeriodKey {
    my ( $Self, $TimeRange, $Index ) = @_;

    $TimeRange ||= 'weekly';

    if ( $TimeRange eq 'daily' ) {
        # 0-23 hours
        return $Index;
    }
    elsif ( $TimeRange eq 'weekly' ) {
        # 0-6 days of week (0=Sunday)
        return $Index;
    }
    elsif ( $TimeRange eq 'monthly' ) {
        # Week 1-5
        return $Index + 1;
    }
    elsif ( $TimeRange eq '6months' ) {
        # YYYY-MM format
        my $MonthDate = $Self->_GetDateMinusMonths( 5 - $Index );
        my ($Year, $Month) = split /-/, $MonthDate;
        return "$Year-$Month";
    }

    return $Index;
}

=end Internal:

=cut

1;
