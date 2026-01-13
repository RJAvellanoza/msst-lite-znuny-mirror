# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::Dashboard::MTRDSummary;

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
        CacheKey => 'MTRDSummary-' . $Kernel::OM->Get('Kernel::Output::HTML::Layout')->{UserLanguage},
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

    # Get current month MTRD data
    my %MTRDMonthly = $OperationalKPIsObj->CalculateMTRDMonthly(
        Year  => $Year,
        Month => $Month,
    );

    if ( !%MTRDMonthly ) {
        $LayoutObject->Block(
            Name => 'NoData',
        );
        my $Content = $LayoutObject->Output(
            TemplateFile => 'AgentDashboardMTRDSummary',
            Data         => {
                %{ $Self->{Config} },
            },
        );
        return $Content;
    }

    # Get priority breakdown
    my @PriorityBreakdown = $OperationalKPIsObj->CalculateMTRDByPriority(
        StartDate => "$Year-" . sprintf("%02d", $Month) . "-01 00:00:00",
        EndDate   => "$Year-" . sprintf("%02d", $Month) . "-31 23:59:59",
    );

    # Format MTRD in human-readable format
    my $AverageMTRDSeconds = $MTRDMonthly{Summary}->{AverageMTRD} || 0;
    my $AverageMTRDFormatted = $Self->_FormatSeconds($AverageMTRDSeconds);

    # Build data for template
    $LayoutObject->Block(
        Name => 'MTRDData',
        Data => {
            Month           => sprintf("%02d", $Month),
            Year            => $Year,
            TotalIncidents  => $MTRDMonthly{Summary}->{Total} || 0,
            AverageMTRD     => $AverageMTRDFormatted,
            AverageMTRDSecs => $AverageMTRDSeconds,
            P1Count         => $MTRDMonthly{Summary}->{P1} || 0,
            P2Count         => $MTRDMonthly{Summary}->{P2} || 0,
            P3Count         => $MTRDMonthly{Summary}->{P3} || 0,
            P4Count         => $MTRDMonthly{Summary}->{P4} || 0,
        },
    );

    # Add priority breakdown rows
    for my $Priority (@PriorityBreakdown) {
        my $FormattedMTRD = $Self->_FormatSeconds($Priority->{AverageMTRD});
        $LayoutObject->Block(
            Name => 'PriorityBreakdown',
            Data => {
                Priority    => $Priority->{Priority},
                Count       => $Priority->{Count},
                AverageMTRD => $FormattedMTRD,
                Percentage  => $Priority->{Percentage},
            },
        );
    }

    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardMTRDSummary',
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
