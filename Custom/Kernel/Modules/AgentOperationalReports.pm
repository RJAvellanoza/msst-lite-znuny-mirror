# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentOperationalReports;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::OperationalKPIs',
    'Kernel::System::Time',
    'Kernel::System::Log',
    'Kernel::System::JSON',
    'Kernel::System::DB',
    'Kernel::System::Group',
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
    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check group permissions (stats group required)
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');

    # Get required groups from frontend module config
    my $ModuleConfig = $ConfigObject->Get('Frontend::Module')->{AgentOperationalReports};
    my @RequiredGroups = @{ $ModuleConfig->{Group} || [] };

    my $HasAccess = 0;
    for my $Group (@RequiredGroups) {
        my $GroupID = $GroupObject->GroupLookup( Group => $Group );
        next if !$GroupID;

        my %Groups = $GroupObject->PermissionUserGet(
            UserID => $Self->{UserID},
            Type   => 'ro',
        );

        if ( $Groups{$GroupID} ) {
            $HasAccess = 1;
            last;
        }
    }

    if ( !$HasAccess && @RequiredGroups ) {
        return $LayoutObject->NoPermission(
            Message    => 'You need stats group access to view operational reports.',
            WithHeader => 'yes',
        );
    }

    # Get parameters
    my %GetParam;
    for my $Param (qw(Section View SelectedDate StartDate EndDate Year Month Quarter TimeFilter Subaction FilterType SelectedWeek SelectedMonth SelectedYear)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Validate date parameters
    my %DateValidations = (
        SelectedDate  => 'date',
        StartDate     => 'date',
        EndDate       => 'date',
        Year          => 'year',
        SelectedYear  => 'year',
        Month         => 'month',
        SelectedMonth => 'month',
        Quarter       => 'quarter',
        SelectedWeek  => 'week',
    );

    for my $ParamName ( keys %DateValidations ) {
        if ( $GetParam{$ParamName} && !$Self->_ValidateDateParam(
            Value => $GetParam{$ParamName},
            Type  => $DateValidations{$ParamName},
        ) ) {
            return $LayoutObject->ErrorScreen(
                Message => "Invalid $ParamName parameter format.",
            );
        }
    }

    # Default to AllActiveTickets section
    $GetParam{Section} ||= 'AllActiveTickets';

    # Handle AJAX requests for Active Tickets Assignment
    if ( $GetParam{Subaction} eq 'GetActiveTicketsData' ) {
        return $Self->_GetActiveTicketsDataJSON(%GetParam);
    }

    # Prepare template data
    my %Data = (
        Section => $GetParam{Section},
        TimeFilter => $GetParam{TimeFilter} || 'week',
    );

    # Route to appropriate section handler
    my $Result;
    if ( $GetParam{Section} eq 'ActiveTicketsAssignment' ) {
        $Result = $Self->_ShowActiveTicketsAssignment(%GetParam);
    }
    elsif ( $GetParam{Section} eq 'AllActiveTickets' || !$GetParam{Section} ) {
        # Default to AllActiveTickets
        $Result = $Self->_ShowAllActiveTickets(%GetParam);
    }
    elsif ( $GetParam{Section} eq 'AverageBacklog' ) {
        $Result = $Self->_ShowAverageBacklog(%GetParam);
    }
    elsif ( $GetParam{Section} eq 'MTRD' ) {
        $Result = $Self->_ShowMTRD(%GetParam);
    }
    elsif ( $GetParam{Section} eq 'MTTR' ) {
        $Result = $Self->_ShowMTTR(%GetParam);
    }
    elsif ( $GetParam{Section} eq 'Dashboard' ) {
        $Result = $Self->_ShowDashboard(%GetParam);
    }
    else {
        # Fallback to AllActiveTickets
        $Result = $Self->_ShowAllActiveTickets(%GetParam);
    }

    # If result is a string (CSV export), return it directly
    return $Result if !ref($Result);

    # Otherwise merge the hash
    %Data = ( %Data, %{ $Result } );

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Operational Reports',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentOperationalReports',
        Data         => \%Data,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _ShowDashboard {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my %Data = ();

    # Get current month and year for dashboard
    my $DateTimeString = $TimeObject->CurrentTimestamp();
    my ($Year, $Month, $Day) = split /-/, $DateTimeString;
    my $Quarter = int(($Month - 1) / 3) + 1;

    # Get current month MTRD and MTTR averages
    my %MTRDMonthly = $OperationalKPIsObject->CalculateMTRDMonthly(
        Year  => $Year,
        Month => $Month,
    );

    my %MTTRMonthly = $OperationalKPIsObject->CalculateMTTRMonthly(
        Year  => $Year,
        Month => $Month,
    );

    # Get unassigned incidents
    my @UnassignedIncidents = $OperationalKPIsObject->GetLiveUnassignedDashboard();

    # Log KPI calculation results for debugging
    $LogObject->Log(
        Priority => 'debug',
        Message  => sprintf(
            "Dashboard KPIs for %04d-%02d: MTRD Total=%d Avg=%d, MTTR Total=%d Avg=%d",
            $Year, $Month,
            $MTRDMonthly{Summary} ? ($MTRDMonthly{Summary}{Total} || 0) : 0,
            $MTRDMonthly{Summary} ? ($MTRDMonthly{Summary}{AverageMTRD} || 0) : 0,
            $MTTRMonthly{Summary} ? ($MTTRMonthly{Summary}{Total} || 0) : 0,
            $MTTRMonthly{Summary} ? ($MTTRMonthly{Summary}{AverageMTTR} || 0) : 0,
        ),
    );

    # Format MTRD/MTTR for display with null-safe access
    my $AvgMTRD = $Self->_FormatSeconds(
        ($MTRDMonthly{Summary} && $MTRDMonthly{Summary}{AverageMTRD}) ? $MTRDMonthly{Summary}{AverageMTRD} : 0
    );
    my $AvgMTTR = $Self->_FormatSeconds(
        ($MTTRMonthly{Summary} && $MTTRMonthly{Summary}{AverageMTTR}) ? $MTTRMonthly{Summary}{AverageMTTR} : 0
    );

    # Get 30-day trend data
    # Calculate start date (30 days ago)
    my $StartTime = $TimeObject->TimeStamp2SystemTime(
        String => $DateTimeString,
    ) - (30 * 86400);  # 30 days in seconds
    my $StartDateString = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $StartTime,
    );

    my %TrendData = $OperationalKPIsObject->GetIncidentTrends(
        StartDate => $StartDateString,
        EndDate   => $DateTimeString,
    );

    # Get priority breakdowns for current month
    my %MTRDByPriority = $OperationalKPIsObject->CalculateMTRDByPriority(
        Year  => $Year,
        Month => $Month,
    );

    my %MTTRByPriority = $OperationalKPIsObject->CalculateMTTRByPriority(
        Year  => $Year,
        Month => $Month,
    );

    # Build dashboard data with null-safe access
    $Data{TotalIncidents} = ($MTRDMonthly{Summary} && defined $MTRDMonthly{Summary}{Total})
        ? $MTRDMonthly{Summary}{Total} : 0;
    $Data{AvgMTRD} = $AvgMTRD;
    $Data{AvgMTTR} = $AvgMTTR;
    $Data{UnassignedCount} = scalar(@UnassignedIncidents);
    $Data{UnassignedIncidents} = \@UnassignedIncidents;

    # Warn if no incident data found
    if (!$Data{TotalIncidents}) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => sprintf(
                "Dashboard: No incidents found for %04d-%02d. MTRD Summary may be empty.",
                $Year, $Month,
            ),
        );
    }

    # Format trend data for display
    if ( $TrendData{Trends} && ref $TrendData{Trends} eq 'ARRAY' ) {
        my @FormattedTrends;
        for my $Trend ( @{ $TrendData{Trends} } ) {
            my %TrendRow = (
                Date                => $Trend->{Date},
                TotalCount          => $Trend->{TotalCount},
                PriorityBreakdown   => $Trend->{PriorityBreakdown},
            );
            push @FormattedTrends, \%TrendRow;
        }
        $Data{TrendData} = \@FormattedTrends;
    }

    # Add priority breakdowns
    if ( %MTRDByPriority ) {
        $Data{MTRDByPriority} = \%MTRDByPriority;
    }

    if ( %MTTRByPriority ) {
        $Data{MTTRByPriority} = \%MTTRByPriority;
    }

    # Prepare chart data for D3/NVD3 visualization
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');

    # Get chart data from OperationalKPIs
    my %TrendChartData = %{ $OperationalKPIsObject->GetChartDataForDashboard() };
    my %PriorityChartData = %{ $OperationalKPIsObject->GetPriorityBreakdownChartData() };

    # Prepare JavaScript data object
    my %ChartData = (
        TrendChart    => \%TrendChartData,
        PriorityChart => \%PriorityChartData,
    );

    # Convert to JSON and add to page
    my $ChartDataJSON = $JSONObject->Encode(
        Data => \%ChartData,
    );

    # Add chart data as JavaScript variable
    $LayoutObject->AddJSOnDocumentComplete(
        Code => "window.OperationalReportsChartData = $ChartDataJSON;",
    );

    return \%Data;
}

sub _ShowMTRD {
    my ( $Self, %Param ) = @_;

    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    # Get View parameter (Live, Daily, Weekly, Monthly, Quarterly, Yearly, Tabular)
    my $View = $Param{View} || 'Live';

    # Handle CSV Export
    if ( $ParamObject->GetParam( Param => 'Export' ) ) {
        return $Self->_ExportToCSV(%Param);
    }

    # Initialize data hash
    my %Data = (
        View => $View,
    );

    # Route to appropriate MTRD view
    if ( $View eq 'Live' ) {
        %Data = ( %Data, %{ $Self->_GetMTRDLiveDashboard() } );
    }
    elsif ( $View eq 'Daily' && $Param{SelectedDate} ) {
        %Data = ( %Data, %{ $Self->_GetMTRDDailyReport(%Param) } );
    }
    elsif ( $View eq 'Weekly' && $Param{StartDate} && $Param{EndDate} ) {
        %Data = ( %Data, %{ $Self->_GetMTRDWeeklyReport(%Param) } );
    }
    elsif ( $View eq 'Monthly' && $Param{Year} && $Param{Month} ) {
        %Data = ( %Data, %{ $Self->_GetMTRDMonthlyReport(%Param) } );
    }
    elsif ( $View eq 'Quarterly' && $Param{Year} && $Param{Quarter} ) {
        %Data = ( %Data, %{ $Self->_GetMTRDQuarterlyReport(%Param) } );
    }
    elsif ( $View eq 'Yearly' && $Param{Year} ) {
        %Data = ( %Data, %{ $Self->_GetMTRDYearlyReport(%Param) } );
    }
    elsif ( $View eq 'Tabular' && $Param{StartDate} && $Param{EndDate} ) {
        %Data = ( %Data, %{ $Self->_GetMTRDTabularReport(%Param) } );
    }

    return \%Data;
}

sub _GetMTRDLiveDashboard {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my @UnassignedTickets = $OperationalKPIsObject->GetLiveUnassignedDashboard();

    return {
        UnassignedTickets => \@UnassignedTickets,
        TotalUnassigned   => scalar(@UnassignedTickets),
    };
}

sub _GetMTRDDailyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %DailyData = $OperationalKPIsObject->CalculateMTRDDaily(
        SelectedDate => $Param{SelectedDate},
    );

    # Format hourly breakdown for display
    if ( $DailyData{HourlyBreakdown} ) {
        for my $Hour ( @{ $DailyData{HourlyBreakdown} } ) {
            $Hour->{AverageMTRDFormatted} = $Self->_FormatSeconds( $Hour->{AverageMTRD} );
        }
    }

    # Format summary
    if ( $DailyData{Summary} ) {
        $DailyData{Summary}{AverageMTRDFormatted} = $Self->_FormatSeconds( $DailyData{Summary}{AverageMTRD} );
    }

    return {
        %DailyData,
        SelectedDate => $Param{SelectedDate},
    };
}

sub _GetMTRDWeeklyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %WeeklyData = $OperationalKPIsObject->CalculateMTRDWeekly(
        StartDate => $Param{StartDate},
        EndDate   => $Param{EndDate},
    );

    # Format daily breakdown
    if ( $WeeklyData{DailyBreakdown} ) {
        for my $Day ( @{ $WeeklyData{DailyBreakdown} } ) {
            $Day->{AverageMTRDFormatted} = $Self->_FormatSeconds( $Day->{AverageMTRD} );
            # Trim weekday name (PostgreSQL returns padded strings)
            $Day->{Weekday} =~ s/\s+$//;
        }
    }

    # Format summary
    if ( $WeeklyData{Summary} ) {
        $WeeklyData{Summary}{AverageMTRDFormatted} = $Self->_FormatSeconds( $WeeklyData{Summary}{AverageMTRD} );
    }

    return {
        %WeeklyData,
    };
}

sub _GetMTRDMonthlyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %MonthlyData = $OperationalKPIsObject->CalculateMTRDMonthly(
        Year  => $Param{Year},
        Month => $Param{Month},
    );

    # Format weekly breakdown
    if ( $MonthlyData{WeeklyBreakdown} ) {
        for my $Week ( @{ $MonthlyData{WeeklyBreakdown} } ) {
            $Week->{AverageMTRDFormatted} = $Self->_FormatSeconds( $Week->{AverageMTRD} );
        }
    }

    # Format summary
    if ( $MonthlyData{Summary} ) {
        $MonthlyData{Summary}{AverageMTRDFormatted} = $Self->_FormatSeconds( $MonthlyData{Summary}{AverageMTRD} );
    }

    return {
        %MonthlyData,
    };
}

sub _GetMTRDQuarterlyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %QuarterlyData = $OperationalKPIsObject->CalculateMTRDQuarterly(
        Year    => $Param{Year},
        Quarter => $Param{Quarter},
    );

    # Format monthly breakdown
    if ( $QuarterlyData{MonthlyBreakdown} ) {
        for my $Month ( @{ $QuarterlyData{MonthlyBreakdown} } ) {
            $Month->{AverageMTRDFormatted} = $Self->_FormatSeconds( $Month->{AverageMTRD} );
        }
    }

    # Format summary
    if ( $QuarterlyData{Summary} ) {
        $QuarterlyData{Summary}{AverageMTRDFormatted} = $Self->_FormatSeconds( $QuarterlyData{Summary}{AverageMTRD} );
    }

    return {
        %QuarterlyData,
    };
}

sub _GetMTRDYearlyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %YearlyData = $OperationalKPIsObject->CalculateMTRDYearly(
        Year => $Param{Year},
    );

    # Format monthly breakdown
    if ( $YearlyData{MonthlyBreakdown} ) {
        for my $Month ( @{ $YearlyData{MonthlyBreakdown} } ) {
            $Month->{AverageMTRDFormatted} = $Self->_FormatSeconds( $Month->{AverageMTRD} );
        }
    }

    # Format summary
    if ( $YearlyData{Summary} ) {
        $YearlyData{Summary}{AverageMTRDFormatted} = $Self->_FormatSeconds( $YearlyData{Summary}{AverageMTRD} );
    }

    return {
        %YearlyData,
    };
}

sub _GetMTRDTabularReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my @TabularData = $OperationalKPIsObject->GetMTRDTabularData(
        StartDate => $Param{StartDate},
        EndDate   => $Param{EndDate},
    );

    return {
        TabularData => \@TabularData,
        TotalRecords => scalar(@TabularData),
        StartDate   => $Param{StartDate},
        EndDate     => $Param{EndDate},
    };
}

sub _ShowMTTR {
    my ( $Self, %Param ) = @_;

    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    # Get View parameter (Live, Daily, Weekly, Monthly, Quarterly, Yearly, Tabular)
    my $View = $Param{View} || 'Live';

    # Handle CSV Export
    if ( $ParamObject->GetParam( Param => 'Export' ) ) {
        return $Self->_ExportMTTRToCSV(%Param);
    }

    # Initialize data hash
    my %Data = (
        View => $View,
    );

    # Route to appropriate MTTR view
    if ( $View eq 'Live' ) {
        %Data = ( %Data, %{ $Self->_GetMTTRLiveDashboard() } );
    }
    elsif ( $View eq 'Daily' && $Param{SelectedDate} ) {
        %Data = ( %Data, %{ $Self->_GetMTTRDailyReport(%Param) } );
    }
    elsif ( $View eq 'Weekly' && $Param{StartDate} && $Param{EndDate} ) {
        %Data = ( %Data, %{ $Self->_GetMTTRWeeklyReport(%Param) } );
    }
    elsif ( $View eq 'Monthly' && $Param{Year} && $Param{Month} ) {
        %Data = ( %Data, %{ $Self->_GetMTTRMonthlyReport(%Param) } );
    }
    elsif ( $View eq 'Quarterly' && $Param{Year} && $Param{Quarter} ) {
        %Data = ( %Data, %{ $Self->_GetMTTRQuarterlyReport(%Param) } );
    }
    elsif ( $View eq 'Yearly' && $Param{Year} ) {
        %Data = ( %Data, %{ $Self->_GetMTTRYearlyReport(%Param) } );
    }
    elsif ( $View eq 'Tabular' && $Param{StartDate} && $Param{EndDate} ) {
        %Data = ( %Data, %{ $Self->_GetMTTRTabularReport(%Param) } );
    }

    return \%Data;
}

sub _GetMTTRLiveDashboard {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my @UnassignedTickets = $OperationalKPIsObject->GetLiveUnassignedDashboard();

    return {
        UnassignedTickets => \@UnassignedTickets,
        TotalUnassigned   => scalar(@UnassignedTickets),
    };
}

sub _GetMTTRDailyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %DailyData = $OperationalKPIsObject->CalculateMTTRDaily(
        SelectedDate => $Param{SelectedDate},
    );

    # Format hourly breakdown for display
    if ( $DailyData{HourlyBreakdown} ) {
        for my $Hour ( @{ $DailyData{HourlyBreakdown} } ) {
            $Hour->{AverageMTTRFormatted} = $Self->_FormatSeconds( $Hour->{AverageMTTR} );
        }
    }

    # Format summary
    if ( $DailyData{Summary} ) {
        $DailyData{Summary}{AverageMTTRFormatted} = $Self->_FormatSeconds( $DailyData{Summary}{AverageMTTR} );
    }

    return {
        %DailyData,
        SelectedDate => $Param{SelectedDate},
    };
}

sub _GetMTTRWeeklyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %WeeklyData = $OperationalKPIsObject->CalculateMTTRWeekly(
        StartDate => $Param{StartDate},
        EndDate   => $Param{EndDate},
    );

    # Format daily breakdown
    if ( $WeeklyData{DailyBreakdown} ) {
        for my $Day ( @{ $WeeklyData{DailyBreakdown} } ) {
            $Day->{AverageMTTRFormatted} = $Self->_FormatSeconds( $Day->{AverageMTTR} );
            # Trim weekday name (PostgreSQL returns padded strings)
            $Day->{Weekday} =~ s/\s+$//;
        }
    }

    # Format summary
    if ( $WeeklyData{Summary} ) {
        $WeeklyData{Summary}{AverageMTTRFormatted} = $Self->_FormatSeconds( $WeeklyData{Summary}{AverageMTTR} );
    }

    return {
        %WeeklyData,
    };
}

sub _GetMTTRMonthlyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %MonthlyData = $OperationalKPIsObject->CalculateMTTRMonthly(
        Year  => $Param{Year},
        Month => $Param{Month},
    );

    # Format weekly breakdown
    if ( $MonthlyData{WeeklyBreakdown} ) {
        for my $Week ( @{ $MonthlyData{WeeklyBreakdown} } ) {
            $Week->{AverageMTTRFormatted} = $Self->_FormatSeconds( $Week->{AverageMTTR} );
        }
    }

    # Format summary
    if ( $MonthlyData{Summary} ) {
        $MonthlyData{Summary}{AverageMTTRFormatted} = $Self->_FormatSeconds( $MonthlyData{Summary}{AverageMTTR} );
    }

    return {
        %MonthlyData,
    };
}

sub _GetMTTRQuarterlyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %QuarterlyData = $OperationalKPIsObject->CalculateMTTRQuarterly(
        Year    => $Param{Year},
        Quarter => $Param{Quarter},
    );

    # Format monthly breakdown
    if ( $QuarterlyData{MonthlyBreakdown} ) {
        for my $Month ( @{ $QuarterlyData{MonthlyBreakdown} } ) {
            $Month->{AverageMTTRFormatted} = $Self->_FormatSeconds( $Month->{AverageMTTR} );
        }
    }

    # Format summary
    if ( $QuarterlyData{Summary} ) {
        $QuarterlyData{Summary}{AverageMTTRFormatted} = $Self->_FormatSeconds( $QuarterlyData{Summary}{AverageMTTR} );
    }

    return {
        %QuarterlyData,
    };
}

sub _GetMTTRYearlyReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my %YearlyData = $OperationalKPIsObject->CalculateMTTRYearly(
        Year => $Param{Year},
    );

    # Format monthly breakdown
    if ( $YearlyData{MonthlyBreakdown} ) {
        for my $Month ( @{ $YearlyData{MonthlyBreakdown} } ) {
            $Month->{AverageMTTRFormatted} = $Self->_FormatSeconds( $Month->{AverageMTTR} );
        }
    }

    # Format summary
    if ( $YearlyData{Summary} ) {
        $YearlyData{Summary}{AverageMTTRFormatted} = $Self->_FormatSeconds( $YearlyData{Summary}{AverageMTTR} );
    }

    return {
        %YearlyData,
    };
}

sub _GetMTTRTabularReport {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my @TabularData = $OperationalKPIsObject->GetMTTRTabularData(
        StartDate => $Param{StartDate},
        EndDate   => $Param{EndDate},
    );

    return {
        TabularData => \@TabularData,
        TotalRecords => scalar(@TabularData),
        StartDate   => $Param{StartDate},
        EndDate     => $Param{EndDate},
    };
}

sub _ExportMTTRToCSV {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Get tabular data
    my @TabularData = $OperationalKPIsObject->GetMTTRTabularData(
        StartDate => $Param{StartDate},
        EndDate   => $Param{EndDate},
    );

    # Generate CSV
    my $CSV = "\x{FEFF}";  # UTF-8 BOM
    $CSV .= "Incident Number,Summary,Start Date,MTTR (hours),Priority,Status,Assigned To,Source\n";

    for my $Record (@TabularData) {
        my $MTTRHours = sprintf("%.2f", $Record->{MTTR} / 3600);

        # Escape CSV fields
        my @Fields = (
            $Record->{TicketNumber},
            $Self->_EscapeCSV($Record->{Title}),
            $Record->{StartDate},
            $MTTRHours,
            $Record->{Priority},
            $Record->{Status},
            $Record->{AssignedTo},
            $Record->{Source},
        );

        $CSV .= join(',', @Fields) . "\n";
    }

    # Return file download
    my $Timestamp = $TimeObject->CurrentTimestamp();
    $Timestamp =~ s/[:\s-]//g;

    return $LayoutObject->Attachment(
        Content     => $CSV,
        ContentType => 'text/csv; charset=utf-8',
        Filename    => "mttr_report_$Timestamp.csv",
        Type        => 'attachment',
    );
}

sub _ExportToCSV {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Get tabular data
    my @TabularData = $OperationalKPIsObject->GetMTRDTabularData(
        StartDate => $Param{StartDate},
        EndDate   => $Param{EndDate},
    );

    # Generate CSV
    my $CSV = "\x{FEFF}";  # UTF-8 BOM
    $CSV .= "Incident Number,Summary,Start Date,MTRD (hours),Priority,Status,Assigned To,Source\n";

    for my $Record (@TabularData) {
        my $MTRDHours = sprintf("%.2f", $Record->{MTRD} / 3600);

        # Escape CSV fields
        my @Fields = (
            $Record->{TicketNumber},
            $Self->_EscapeCSV($Record->{Title}),
            $Record->{StartDate},
            $MTRDHours,
            $Record->{Priority},
            $Record->{Status},
            $Record->{AssignedTo},
            $Record->{Source},
        );

        $CSV .= join(',', @Fields) . "\n";
    }

    # Return file download
    my $Timestamp = $TimeObject->CurrentTimestamp();
    $Timestamp =~ s/[:\s-]//g;

    return $LayoutObject->Attachment(
        Content     => $CSV,
        ContentType => 'text/csv; charset=utf-8',
        Filename    => "mtrd_report_$Timestamp.csv",
        Type        => 'attachment',
    );
}

sub _EscapeCSV {
    my ( $Self, $Value ) = @_;

    return '' if !defined $Value;

    # Escape quotes and wrap in quotes if contains comma, quote, or newline
    if ( $Value =~ /[,"\n\r]/ ) {
        $Value =~ s/"/""/g;
        $Value = '"' . $Value . '"';
    }

    return $Value;
}

sub _FormatSeconds {
    my ( $Self, $Seconds ) = @_;

    return '0h 0m' if !$Seconds || $Seconds <= 0;

    my $Hours = int($Seconds / 3600);
    my $Minutes = int(($Seconds % 3600) / 60);

    if ( $Hours > 0 ) {
        return sprintf("%dh %dm", $Hours, $Minutes);
    }
    else {
        return sprintf("%dm", $Minutes);
    }
}

sub _ShowActiveTicketsAssignment {
    my ( $Self, %Param ) = @_;

    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $KPIObject  = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    # Generate options for dropdowns
    my $WeekOptions = $Self->_GenerateWeekOptions();
    my $MonthOptions = $Self->_GenerateMonthOptions();
    my $YearOptionsMonthly = $Self->_GenerateYearOptions('monthly');
    my $YearOptionsYearly = $Self->_GenerateYearOptions('yearly');

    # Get current date defaults using timestamp
    my $CurrentTimestamp = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $TimeObject->SystemTime(),
    );
    my ($CurrentYear, $CurrentMonth, $CurrentDay) = split /-| /, $CurrentTimestamp;
    my $CurrentWeekValue = $WeekOptions->[0]->{Value}; # First week is current week
    my $CurrentDate = sprintf("%04d-%02d-%02d", $CurrentYear, $CurrentMonth, $CurrentDay);

    # Determine filter type and get date range
    my $FilterType = $Param{FilterType} || 'day';
    my ($StartDate, $EndDate);

    if ($FilterType eq 'day') {
        my $SelectedDate = $Param{SelectedDate} || $CurrentDate;
        ($StartDate, $EndDate) = $Self->_GetDateRangeForFilter(
            FilterType => 'day',
            SelectedDate => $SelectedDate,
        );
    }
    elsif ($FilterType eq 'week') {
        my $SelectedWeek = $Param{SelectedWeek} || $CurrentWeekValue;
        ($StartDate, $EndDate) = $Self->_GetDateRangeForFilter(
            FilterType => 'week',
            SelectedWeek => $SelectedWeek,
        );
    }
    elsif ($FilterType eq 'month') {
        my $SelectedMonth = $Param{SelectedMonth} || $CurrentMonth;
        my $SelectedYear = $Param{SelectedYear} || $CurrentYear;
        ($StartDate, $EndDate) = $Self->_GetDateRangeForFilter(
            FilterType => 'month',
            SelectedMonth => $SelectedMonth,
            SelectedYear => $SelectedYear,
        );
    }
    elsif ($FilterType eq 'year') {
        my $SelectedYear = $Param{SelectedYear} || $CurrentYear;
        ($StartDate, $EndDate) = $Self->_GetDateRangeForFilter(
            FilterType => 'year',
            SelectedYear => $SelectedYear,
        );
    }

    # Call backend for data retrieval
    my %Result = $KPIObject->GetActiveTicketsByAssignment(
        StartDate => $StartDate,
        EndDate   => $EndDate,
    );

    return {
        %Result,
        WeekOptions => $WeekOptions,
        MonthOptions => $MonthOptions,
        YearOptionsMonthly => $YearOptionsMonthly,
        YearOptionsYearly => $YearOptionsYearly,
        FilterType => $FilterType,
        SelectedDate => $Param{SelectedDate} || $CurrentDate,
        SelectedWeek => $Param{SelectedWeek} || $CurrentWeekValue,
        SelectedMonth => $Param{SelectedMonth} || $CurrentMonth,
        SelectedYear => $Param{SelectedYear} || $CurrentYear,
        CurrentWeekValue => $CurrentWeekValue,
        CurrentMonth => $CurrentMonth,
        CurrentYear => $CurrentYear,
        CurrentDate => $CurrentDate,
    };
}

sub _ShowAllActiveTickets {
    my ( $Self, %Param ) = @_;

    my $KPIObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    # Call backend for data retrieval
    return $KPIObject->GetAllActiveTicketsSummary();
}

sub _ShowAverageBacklog {
    my ( $Self, %Param ) = @_;

    my $KPIObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    # Call backend for data retrieval
    return $KPIObject->GetAverageBacklog();
}

sub _GenerateWeekOptions {
    my ( $Self ) = @_;

    use POSIX qw(strftime mktime);

    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $CurrentSystemTime = $TimeObject->SystemTime();

    my @Weeks;

    # Generate last 12 weeks (current week + 11 previous)
    for my $WeeksBack (0 .. 11) {
        my $WeekStartTime = $CurrentSystemTime - ($WeeksBack * 7 * 86400);

        # Get date components using POSIX localtime
        my @date = localtime($WeekStartTime);
        my $Year = $date[5] + 1900;
        my $Month = $date[4] + 1;
        my $Day = $date[3];
        my $DayOfWeek = $date[6];  # 0=Sunday, 6=Saturday

        # Calculate ISO week number
        my $WeekNumber = $Self->_GetISOWeekNumber($Year, $Month, $Day);

        # Calculate Monday of this week (ISO 8601 - week starts Monday)
        # Convert Sunday=0 to Sunday=7 for easier calculation
        my $ISODayOfWeek = $DayOfWeek == 0 ? 7 : $DayOfWeek;
        my $DaysFromMonday = $ISODayOfWeek - 1;  # Monday=1, so 0 days from Monday

        my $MondayTime = $WeekStartTime - ($DaysFromMonday * 86400);
        my $SundayTime = $MondayTime + (6 * 86400);

        # Get Monday and Sunday dates
        my @monday = localtime($MondayTime);
        my $MonYear = $monday[5] + 1900;
        my $MonMonth = $monday[4] + 1;
        my $MonDay = $monday[3];

        my @sunday = localtime($SundayTime);
        my $SunYear = $sunday[5] + 1900;
        my $SunMonth = $sunday[4] + 1;
        my $SunDay = $sunday[3];

        # Format: "Week 47 (Nov 18-24, 2025)"
        my $MonthNameShort = $Self->_GetMonthNameShort($MonMonth);
        my $Label = sprintf("Week %02d (%s %02d-%02d, %d)",
            $WeekNumber, $MonthNameShort, $MonDay, $SunDay, $MonYear);

        push @Weeks, {
            Value => "$MonYear-W" . sprintf("%02d", $WeekNumber),
            Label => $Label,
            Year  => $MonYear,
            Week  => $WeekNumber,
        };
    }

    return \@Weeks;
}

sub _GetISOWeekNumber {
    my ( $Self, $Year, $Month, $Day ) = @_;

    # Simple ISO 8601 week number calculation
    use POSIX qw(strftime mktime);
    my $time = mktime(0, 0, 0, $Day, $Month - 1, $Year - 1900);
    my $week = strftime("%V", localtime($time));
    return int($week);
}

sub _GetMonthNameShort {
    my ( $Self, $Month ) = @_;

    my %MonthNames = (
        1  => 'Jan', 2  => 'Feb', 3  => 'Mar', 4  => 'Apr',
        5  => 'May', 6  => 'Jun', 7  => 'Jul', 8  => 'Aug',
        9  => 'Sep', 10 => 'Oct', 11 => 'Nov', 12 => 'Dec',
    );

    return $MonthNames{int($Month)} || 'Jan';
}

sub _GenerateMonthOptions {
    my ( $Self ) = @_;

    my @Months = (
        { Value => 1,  Label => 'January' },
        { Value => 2,  Label => 'February' },
        { Value => 3,  Label => 'March' },
        { Value => 4,  Label => 'April' },
        { Value => 5,  Label => 'May' },
        { Value => 6,  Label => 'June' },
        { Value => 7,  Label => 'July' },
        { Value => 8,  Label => 'August' },
        { Value => 9,  Label => 'September' },
        { Value => 10, Label => 'October' },
        { Value => 11, Label => 'November' },
        { Value => 12, Label => 'December' },
    );

    return \@Months;
}

sub _GenerateYearOptions {
    my ( $Self, $Type ) = @_;

    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Get current timestamp and extract year
    my $CurrentTimestamp = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $TimeObject->SystemTime(),
    );
    my ($CurrentYear) = split /-/, $CurrentTimestamp;  # Format: YYYY-MM-DD HH:MM:SS

    my @Years;

    if ($Type eq 'monthly') {
        # Last 2 years for monthly view
        for my $i (0 .. 1) {
            my $year = $CurrentYear - $i;
            push @Years, { Value => $year, Label => $year };
        }
    }
    else {
        # Last 3 years for yearly view
        for my $i (0 .. 2) {
            my $year = $CurrentYear - $i;
            push @Years, { Value => $year, Label => $year };
        }
    }

    return \@Years;
}

sub _GetDateRangeForFilter {
    my ( $Self, %Param ) = @_;

    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $FilterType = $Param{FilterType} || 'week';

    my ($StartDate, $EndDate);

    if ($FilterType eq 'day') {
        # Single day filter (YYYY-MM-DD format)
        my $SelectedDate = $Param{SelectedDate};
        if ($SelectedDate && $SelectedDate =~ /^(\d{4})-(\d{2})-(\d{2})$/) {
            $StartDate = "$SelectedDate 00:00:00";
            $EndDate = "$SelectedDate 23:59:59";
        }
    }
    elsif ($FilterType eq 'week') {
        # Parse week format: "2025-W47"
        my $SelectedWeek = $Param{SelectedWeek};
        if ($SelectedWeek && $SelectedWeek =~ /^(\d{4})-W(\d+)$/) {
            my ($Year, $WeekNum) = ($1, $2);

            # Calculate Monday and Sunday of that ISO week
            use POSIX qw(mktime);
            # Jan 4th is always in week 1 (ISO 8601)
            my $jan4 = mktime(0, 0, 0, 4, 0, $Year - 1900);
            my @jan4_date = localtime($jan4);
            my $jan4_dow = ($jan4_date[6] + 6) % 7; # Convert Sun=0 to Mon=0

            # First Monday of year
            my $first_monday = $jan4 - ($jan4_dow * 86400);

            # Monday of target week
            my $target_monday = $first_monday + (($WeekNum - 1) * 7 * 86400);
            my @monday_date = localtime($target_monday);

            $StartDate = sprintf("%04d-%02d-%02d 00:00:00",
                $monday_date[5] + 1900, $monday_date[4] + 1, $monday_date[3]);

            # Sunday of that week
            my $target_sunday = $target_monday + (6 * 86400);
            my @sunday_date = localtime($target_sunday);
            $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
                $sunday_date[5] + 1900, $sunday_date[4] + 1, $sunday_date[3]);
        }
    }
    elsif ($FilterType eq 'month') {
        my $Month = $Param{SelectedMonth};
        my $Year = $Param{SelectedYear};

        if ($Month && $Year) {
            $StartDate = sprintf("%04d-%02d-01 00:00:00", $Year, $Month);

            # Calculate last day of month
            use POSIX qw(mktime);
            my $last_day_time = mktime(0, 0, 0, 1, $Month, $Year - 1900) - 86400;
            my @last_day = localtime($last_day_time);

            $EndDate = sprintf("%04d-%02d-%02d 23:59:59",
                $last_day[5] + 1900, $last_day[4] + 1, $last_day[3]);
        }
    }
    elsif ($FilterType eq 'year') {
        my $Year = $Param{SelectedYear};

        if ($Year) {
            $StartDate = sprintf("%04d-01-01 00:00:00", $Year);
            $EndDate = sprintf("%04d-12-31 23:59:59", $Year);
        }
    }

    # Fallback to current day if something went wrong
    if (!$StartDate || !$EndDate) {
        my $CurrentTimestamp = $TimeObject->SystemTime2TimeStamp(
            SystemTime => $TimeObject->SystemTime(),
        );
        my ($Year, $Month, $Day) = split /-| /, $CurrentTimestamp;
        $StartDate = "$Year-$Month-$Day 00:00:00";
        $EndDate = "$Year-$Month-$Day 23:59:59";
    }

    return ($StartDate, $EndDate);
}

sub _GetActiveTicketsDataJSON {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Get filtered data
    my $Result = $Self->_ShowActiveTicketsAssignment(%Param);

    if ( $Result->{Error} ) {
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=utf-8',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    ErrorMessage => $Result->{ErrorMessage} || 'Unknown error',
                }
            ),
        );
    }

    # Return JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success => 1,
                Data    => $Result->{ByPriority},
            }
        ),
    );
}

sub _ValidateDateParam {
    my ( $Self, %Param ) = @_;

    my $Value = $Param{Value};
    my $Type  = $Param{Type} || 'date';

    return 1 if !defined $Value || $Value eq '';

    if ( $Type eq 'date' ) {
        # YYYY-MM-DD format
        return 0 unless $Value =~ /^\d{4}-\d{2}-\d{2}$/;
        my ($Year, $Month, $Day) = split /-/, $Value;
        return 0 unless $Year >= 2000 && $Year <= 2100;
        return 0 unless $Month >= 1 && $Month <= 12;
        return 0 unless $Day >= 1 && $Day <= 31;
    }
    elsif ( $Type eq 'year' ) {
        return 0 unless $Value =~ /^\d{4}$/;
        return 0 unless $Value >= 2000 && $Value <= 2100;
    }
    elsif ( $Type eq 'month' ) {
        return 0 unless $Value =~ /^\d{1,2}$/;
        return 0 unless $Value >= 1 && $Value <= 12;
    }
    elsif ( $Type eq 'week' ) {
        # YYYY-Wnn format
        return 0 unless $Value =~ /^\d{4}-W\d{2}$/;
    }
    elsif ( $Type eq 'quarter' ) {
        return 0 unless $Value =~ /^\d{1}$/;
        return 0 unless $Value >= 1 && $Value <= 4;
    }

    return 1;  # Valid
}

1;
