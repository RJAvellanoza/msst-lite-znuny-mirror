# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::Dashboard::IncidentTrends;

use strict;
use warnings;

use Kernel::Language qw(Translatable);
use Kernel::System::Time;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed objects
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    # No user preferences for this widget
    return ();
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },
        CacheKey => 'IncidentTrends-' . $Kernel::OM->Get('Kernel::Output::HTML::Layout')->{UserLanguage},
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject       = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $OperationalKPIsObj = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $TimeObject         = $Kernel::OM->Get('Kernel::System::Time');

    # Calculate date range - last 30 days
    my $EndDate = $TimeObject->SystemTime2TimeStamp(
        SystemTime => time(),
    );

    my $StartDate = $TimeObject->SystemTime2TimeStamp(
        SystemTime => time() - (30 * 24 * 3600),
    );

    # Get incident trends data
    my %TrendsData = $OperationalKPIsObj->GetIncidentTrends(
        StartDate => $StartDate,
        EndDate   => $EndDate,
    );

    if ( !$TrendsData{Trends} || !@{ $TrendsData{Trends} } ) {
        $LayoutObject->Block(
            Name => 'NoData',
        );
        my $Content = $LayoutObject->Output(
            TemplateFile => 'AgentDashboardIncidentTrends',
            Data         => {
                %{ $Self->{Config} },
            },
        );
        return $Content;
    }

    # Build chart data for template
    my @ChartData;
    my $TotalIncidents = 0;
    my $MaxDayCount = 0;

    for my $TrendDay ( @{ $TrendsData{Trends} } ) {
        my $DayCount = $TrendDay->{TotalCount} || 0;
        $TotalIncidents += $DayCount;

        if ( $DayCount > $MaxDayCount ) {
            $MaxDayCount = $DayCount;
        }

        push @ChartData, {
            Date  => $TrendDay->{Date},
            Count => $DayCount,
            P1    => $TrendDay->{PriorityBreakdown}->{P1} || 0,
            P2    => $TrendDay->{PriorityBreakdown}->{P2} || 0,
            P3    => $TrendDay->{PriorityBreakdown}->{P3} || 0,
            P4    => $TrendDay->{PriorityBreakdown}->{P4} || 0,
        };
    }

    # Add trend data to template
    $LayoutObject->Block(
        Name => 'TrendChart',
        Data => {
            TotalIncidents => $TotalIncidents,
            MaxDayCount    => $MaxDayCount,
            StartDate      => $StartDate,
            EndDate        => $EndDate,
        },
    );

    # Add individual day data rows
    for my $Day (@ChartData) {
        my $PercentHeight = $MaxDayCount > 0 ? int(($Day->{Count} / $MaxDayCount) * 100) : 0;

        $LayoutObject->Block(
            Name => 'TrendDay',
            Data => {
                Date          => $Day->{Date},
                Count         => $Day->{Count},
                PercentHeight => $PercentHeight,
                P1            => $Day->{P1},
                P2            => $Day->{P2},
                P3            => $Day->{P3},
                P4            => $Day->{P4},
            },
        );
    }

    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardIncidentTrends',
        Data         => {
            %{ $Self->{Config} },
        },
    );

    return $Content;
}

1;
