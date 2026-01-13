# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentMTTRReport;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::OperationalKPIs',
    'Kernel::System::Time',
    'Kernel::System::Log',
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

    # Get parameters
    my %GetParam;
    for my $Param (qw(View SelectedDate StartDate EndDate Year Month Quarter Action)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Default view
    $GetParam{View} ||= 'Live';

    # Handle CSV Export
    if ( $GetParam{Action} && $GetParam{Action} eq 'ExportCSV' ) {
        return $Self->_ExportToCSV(%GetParam);
    }

    # Prepare template data
    my %Data = (
        View => $GetParam{View},
    );

    # Process based on view type
    if ( $GetParam{View} eq 'Live' ) {
        %Data = ( %Data, %{ $Self->_GetLiveDashboard() } );
    }
    elsif ( $GetParam{View} eq 'Daily' && $GetParam{SelectedDate} ) {
        %Data = ( %Data, %{ $Self->_GetDailyReport(%GetParam) } );
    }
    elsif ( $GetParam{View} eq 'Weekly' && $GetParam{StartDate} && $GetParam{EndDate} ) {
        %Data = ( %Data, %{ $Self->_GetWeeklyReport(%GetParam) } );
    }
    elsif ( $GetParam{View} eq 'Monthly' && $GetParam{Year} && $GetParam{Month} ) {
        %Data = ( %Data, %{ $Self->_GetMonthlyReport(%GetParam) } );
    }
    elsif ( $GetParam{View} eq 'Quarterly' && $GetParam{Year} && $GetParam{Quarter} ) {
        %Data = ( %Data, %{ $Self->_GetQuarterlyReport(%GetParam) } );
    }
    elsif ( $GetParam{View} eq 'Yearly' && $GetParam{Year} ) {
        %Data = ( %Data, %{ $Self->_GetYearlyReport(%GetParam) } );
    }
    elsif ( $GetParam{View} eq 'Tabular' && $GetParam{StartDate} && $GetParam{EndDate} ) {
        %Data = ( %Data, %{ $Self->_GetTabularReport(%GetParam) } );
    }

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'MTTR Reports',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentMTTRReport',
        Data         => \%Data,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetLiveDashboard {
    my ( $Self, %Param ) = @_;

    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');

    my @UnassignedTickets = $OperationalKPIsObject->GetLiveUnassignedDashboard();

    return {
        UnassignedTickets => \@UnassignedTickets,
        TotalUnassigned   => scalar(@UnassignedTickets),
    };
}

sub _GetDailyReport {
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

sub _GetWeeklyReport {
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

sub _GetMonthlyReport {
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

sub _GetQuarterlyReport {
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

sub _GetYearlyReport {
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

sub _GetTabularReport {
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

sub _ExportToCSV {
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

1;
