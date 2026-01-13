# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::Dashboard::MTTRSummary;

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
        CacheKey => 'MTTRSummary-' . $Kernel::OM->Get('Kernel::Output::HTML::Layout')->{UserLanguage},
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject       = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $OperationalKPIsObj = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $TimeObject         = $Kernel::OM->Get('Kernel::System::Time');

    # Get current month
    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = localtime(time);
    $Month += 1;  # localtime returns 0-11
    $Year += 1900;

    # Get current month MTTR data
    my %MTTRMonthly = $OperationalKPIsObj->CalculateMTTRMonthly(
        Year  => $Year,
        Month => $Month,
    );

    if ( !%MTTRMonthly ) {
        $LayoutObject->Block(
            Name => 'NoData',
        );
        my $Content = $LayoutObject->Output(
            TemplateFile => 'AgentDashboardMTTRSummary',
            Data         => {
                %{ $Self->{Config} },
            },
        );
        return $Content;
    }

    # Get priority breakdown
    my @PriorityBreakdown = $OperationalKPIsObj->CalculateMTTRByPriority(
        StartDate => "$Year-" . sprintf("%02d", $Month) . "-01 00:00:00",
        EndDate   => "$Year-" . sprintf("%02d", $Month) . "-31 23:59:59",
    );

    # Format MTTR in human-readable format
    my $AverageMTTRSeconds = $MTTRMonthly{Summary}->{AverageMTTR} || 0;
    my $AverageMTTRFormatted = $Self->_FormatSeconds($AverageMTTRSeconds);

    # Build data for template
    $LayoutObject->Block(
        Name => 'MTTRData',
        Data => {
            Month           => sprintf("%02d", $Month),
            Year            => $Year,
            TotalIncidents  => $MTTRMonthly{Summary}->{Total} || 0,
            AverageMTTR     => $AverageMTTRFormatted,
            AverageMTTRSecs => $AverageMTTRSeconds,
            P1Count         => $MTTRMonthly{Summary}->{P1} || 0,
            P2Count         => $MTTRMonthly{Summary}->{P2} || 0,
            P3Count         => $MTTRMonthly{Summary}->{P3} || 0,
            P4Count         => $MTTRMonthly{Summary}->{P4} || 0,
        },
    );

    # Add priority breakdown rows
    for my $Priority (@PriorityBreakdown) {
        my $FormattedMTTR = $Self->_FormatSeconds($Priority->{AverageMTTR});
        $LayoutObject->Block(
            Name => 'PriorityBreakdown',
            Data => {
                Priority    => $Priority->{Priority},
                Count       => $Priority->{Count},
                AverageMTTR => $FormattedMTTR,
                Percentage  => $Priority->{Percentage},
            },
        );
    }

    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardMTTRSummary',
        Data         => {
            %{ $Self->{Config} },
        },
    );

    return $Content;
}

sub _FormatSeconds {
    my ( $Self, $Seconds ) = @_;

    return '0s' if !$Seconds;

    if ( $Seconds < 60 ) {
        return $Seconds . 's';
    }
    elsif ( $Seconds < 3600 ) {
        my $Minutes = int($Seconds / 60);
        return $Minutes . 'm';
    }
    elsif ( $Seconds < 86400 ) {
        my $Hours = int($Seconds / 3600);
        my $Minutes = int(( $Seconds % 3600 ) / 60);
        return $Hours . 'h ' . $Minutes . 'm';
    }
    else {
        my $Days = int($Seconds / 86400);
        my $Hours = int(( $Seconds % 86400 ) / 3600);
        return $Days . 'd ' . $Hours . 'h';
    }
}

1;
