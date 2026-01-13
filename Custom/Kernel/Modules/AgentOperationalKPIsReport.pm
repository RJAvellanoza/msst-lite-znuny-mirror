# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentOperationalKPIsReport;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

use Kernel::Language qw(Translatable);

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
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # Check if module is enabled
    my $Enabled = $ConfigObject->Get('OperationalKPIs::Enabled');
    if ( !$Enabled ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('Operational KPIs module is not enabled.'),
        );
    }

    # Handle AJAX export requests
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'ExportCSV' ) {
        return $Self->_ExportCSV();
    }

    if ( $Self->{Subaction} && $Self->{Subaction} eq 'ExportExcel' ) {
        return $Self->_ExportExcel();
    }

    # Default: Show main report page
    return $Self->_ShowReportPage();
}

sub _ShowReportPage {
    my ( $Self, %Param ) = @_;

    my $LayoutObject           = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject            = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $OperationalKPIsObject  = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $ConfigObject           = $Kernel::OM->Get('Kernel::Config');
    my $TimeObject             = $Kernel::OM->Get('Kernel::System::Time');
    my $LogObject              = $Kernel::OM->Get('Kernel::System::Log');

    # Get filter parameters
    my %GetParam;
    for my $Param (qw(ReportType DateStart DateEnd Priority Source ProductCat AggregationLevel Page)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Set defaults
    $GetParam{ReportType}        ||= 'mtrd';
    $GetParam{AggregationLevel}  ||= 'daily';
    $GetParam{Page}              ||= 1;

    # Calculate default date range (last 30 days)
    if ( !$GetParam{DateStart} || !$GetParam{DateEnd} ) {
        my $CurrentTime = $TimeObject->SystemTime();
        $GetParam{DateEnd} = $TimeObject->SystemTime2TimeStamp(
            SystemTime => $CurrentTime,
        );
        $GetParam{DateStart} = $TimeObject->SystemTime2TimeStamp(
            SystemTime => $CurrentTime - ( 30 * 24 * 3600 ),
        );
    }
    else {
        # Convert YYYY-MM-DD format from HTML5 date input to full timestamp
        if ( $GetParam{DateStart} && $GetParam{DateStart} =~ /^\d{4}-\d{2}-\d{2}$/ ) {
            $GetParam{DateStart} .= ' 00:00:00';
        }
        if ( $GetParam{DateEnd} && $GetParam{DateEnd} =~ /^\d{4}-\d{2}-\d{2}$/ ) {
            $GetParam{DateEnd} .= ' 23:59:59';
        }
    }

    # Validate date range against data retention period
    my $RetentionDays = $ConfigObject->Get('OperationalKPIs::DataRetentionDays') || 180;
    my $MaxStartDate = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $TimeObject->SystemTime() - ( $RetentionDays * 24 * 3600 ),
    );

    if ( $GetParam{DateStart} lt $MaxStartDate ) {
        $GetParam{DateStart} = $MaxStartDate;
        $GetParam{RetentionWarning} = 1;
    }

    # Load report data based on type
    my %ReportData;
    eval {
        if ( $GetParam{ReportType} eq 'mtrd' ) {
            %ReportData = $OperationalKPIsObject->CalculateMTRD(
                StartDate        => $GetParam{DateStart},
                EndDate          => $GetParam{DateEnd},
                Priority         => $GetParam{Priority},
                Source           => $GetParam{Source},
                AggregationLevel => $GetParam{AggregationLevel},
            );
        }
        elsif ( $GetParam{ReportType} eq 'mttr' ) {
            %ReportData = $OperationalKPIsObject->CalculateMTTR(
                StartDate        => $GetParam{DateStart},
                EndDate          => $GetParam{DateEnd},
                Priority         => $GetParam{Priority},
                Source           => $GetParam{Source},
                AggregationLevel => $GetParam{AggregationLevel},
            );
        }
        elsif ( $GetParam{ReportType} eq 'trends' ) {
            %ReportData = $OperationalKPIsObject->GetIncidentTrends(
                StartDate        => $GetParam{DateStart},
                EndDate          => $GetParam{DateEnd},
                Priority         => $GetParam{Priority},
                Source           => $GetParam{Source},
                AggregationLevel => $GetParam{AggregationLevel},
            );
        }
        elsif ( $GetParam{ReportType} eq 'msi_handover' ) {
            %ReportData = $OperationalKPIsObject->GetMSIHandoverReport(
                StartDate => $GetParam{DateStart},
                EndDate   => $GetParam{DateEnd},
            );
        }

        # Load additional breakdowns for MTRD/MTTR reports (if no specific filters applied)
        if ( $GetParam{ReportType} eq 'mtrd' || $GetParam{ReportType} eq 'mttr' ) {
            # Priority breakdown
            my @PriorityBreakdown = $OperationalKPIsObject->CalculateMTRDByPriority(
                StartDate => $GetParam{DateStart},
                EndDate   => $GetParam{DateEnd},
            );
            $ReportData{PriorityBreakdown} = \@PriorityBreakdown if @PriorityBreakdown;

            # Source breakdown
            my @SourceBreakdown = $OperationalKPIsObject->CalculateMTRDBySource(
                StartDate => $GetParam{DateStart},
                EndDate   => $GetParam{DateEnd},
            );
            $ReportData{SourceBreakdown} = \@SourceBreakdown if @SourceBreakdown;

            # Assignment statistics
            my %AssignmentStats = $OperationalKPIsObject->GetAssignmentStats(
                StartDate => $GetParam{DateStart},
                EndDate   => $GetParam{DateEnd},
            );
            $ReportData{AssignmentStats} = \%AssignmentStats if %AssignmentStats;
        }
    };

    if ($@) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentOperationalKPIsReport: Error loading report data: $@",
        );

        return $LayoutObject->ErrorScreen(
            Message => Translatable('An error occurred while loading the report data. Please try again later.'),
        );
    }

    # Format data for display
    $Self->_FormatReportData(\%ReportData, $GetParam{ReportType});

    # Build output
    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();

    # Add breadcrumb
    $LayoutObject->Block(
        Name => 'Breadcrumb',
        Data => {
            Name => Translatable('Operational KPIs'),
        },
    );

    # Pass data to template
    # Convert dates to YYYY-MM-DD format for HTML5 date inputs
    my $DateStartDisplay = $GetParam{DateStart};
    my $DateEndDisplay = $GetParam{DateEnd};
    $DateStartDisplay =~ s/\s.*$// if $DateStartDisplay;  # Remove time part
    $DateEndDisplay =~ s/\s.*$// if $DateEndDisplay;      # Remove time part

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentOperationalKPIsReport',
        Data         => {
            %GetParam,
            %ReportData,
            DateStart => $DateStartDisplay,
            DateEnd   => $DateEndDisplay,
        },
    );

    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _ExportCSV {
    my ( $Self, %Param ) = @_;

    my $LayoutObject          = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $ParamObject           = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $TimeObject            = $Kernel::OM->Get('Kernel::System::Time');
    my $LogObject             = $Kernel::OM->Get('Kernel::System::Log');

    # Get parameters
    my $ReportType = $ParamObject->GetParam( Param => 'ReportType' ) || 'mtrd';
    my $DateStart  = $ParamObject->GetParam( Param => 'DateStart' );
    my $DateEnd    = $ParamObject->GetParam( Param => 'DateEnd' );

    # Validate required parameters
    if ( !$DateStart || !$DateEnd ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('Date range is required for export.'),
        );
    }

    # Load report data
    my %ReportData;
    eval {
        if ( $ReportType eq 'mtrd' ) {
            %ReportData = $OperationalKPIsObject->CalculateMTRD(
                StartDate => $DateStart,
                EndDate   => $DateEnd,
            );
        }
        elsif ( $ReportType eq 'mttr' ) {
            %ReportData = $OperationalKPIsObject->CalculateMTTR(
                StartDate => $DateStart,
                EndDate   => $DateEnd,
            );
        }
        elsif ( $ReportType eq 'trends' ) {
            %ReportData = $OperationalKPIsObject->GetIncidentTrends(
                StartDate => $DateStart,
                EndDate   => $DateEnd,
            );
        }
        elsif ( $ReportType eq 'msi_handover' ) {
            %ReportData = $OperationalKPIsObject->GetMSIHandoverReport(
                StartDate => $DateStart,
                EndDate   => $DateEnd,
            );
        }
    };

    if ($@) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentOperationalKPIsReport: Error loading data for CSV export: $@",
        );

        return $LayoutObject->ErrorScreen(
            Message => Translatable('Failed to load data for export. Please try again.'),
        );
    }

    # Generate CSV
    my $CSVContent;
    eval {
        $CSVContent = $OperationalKPIsObject->ExportToCSV(
            ReportType => $ReportType,
            Data       => \%ReportData,
        );
    };

    if ($@ || !$CSVContent) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentOperationalKPIsReport: Failed to generate CSV: $@",
        );

        return $LayoutObject->ErrorScreen(
            Message => Translatable('Failed to generate CSV export. Please try again.'),
        );
    }

    # Generate filename
    my $Timestamp = $TimeObject->CurrentTimestamp();
    $Timestamp =~ s/[: -]//g;
    my $Filename = "${ReportType}_Report_${Timestamp}.csv";

    # Return as attachment
    return $LayoutObject->Attachment(
        ContentType => 'text/csv; charset=utf-8',
        Content     => $CSVContent,
        Filename    => $Filename,
        Type        => 'attachment',
        NoCache     => 1,
    );
}

sub _ExportExcel {
    my ( $Self, %Param ) = @_;

    my $LayoutObject          = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $OperationalKPIsObject = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $ParamObject           = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $TimeObject            = $Kernel::OM->Get('Kernel::System::Time');
    my $LogObject             = $Kernel::OM->Get('Kernel::System::Log');

    # Get parameters
    my $ReportType = $ParamObject->GetParam( Param => 'ReportType' ) || 'mtrd';
    my $DateStart  = $ParamObject->GetParam( Param => 'DateStart' );
    my $DateEnd    = $ParamObject->GetParam( Param => 'DateEnd' );

    # Validate required parameters
    if ( !$DateStart || !$DateEnd ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('Date range is required for export.'),
        );
    }

    # Load report data
    my %ReportData;
    eval {
        if ( $ReportType eq 'mtrd' ) {
            %ReportData = $OperationalKPIsObject->CalculateMTRD(
                StartDate => $DateStart,
                EndDate   => $DateEnd,
            );
        }
        elsif ( $ReportType eq 'mttr' ) {
            %ReportData = $OperationalKPIsObject->CalculateMTTR(
                StartDate => $DateStart,
                EndDate   => $DateEnd,
            );
        }
        elsif ( $ReportType eq 'trends' ) {
            %ReportData = $OperationalKPIsObject->GetIncidentTrends(
                StartDate => $DateStart,
                EndDate   => $DateEnd,
            );
        }
        elsif ( $ReportType eq 'msi_handover' ) {
            %ReportData = $OperationalKPIsObject->GetMSIHandoverReport(
                StartDate => $DateStart,
                EndDate   => $DateEnd,
            );
        }
    };

    if ($@) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentOperationalKPIsReport: Error loading data for Excel export: $@",
        );

        return $LayoutObject->ErrorScreen(
            Message => Translatable('Failed to load data for export. Please try again.'),
        );
    }

    # Generate Excel
    my $ExcelContent;
    eval {
        $ExcelContent = $OperationalKPIsObject->ExportToExcel(
            ReportType => $ReportType,
            Data       => \%ReportData,
        );
    };

    if ($@ || !$ExcelContent) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "AgentOperationalKPIsReport: Failed to generate Excel: $@",
        );

        return $LayoutObject->ErrorScreen(
            Message => Translatable('Excel export is not available. Please use CSV export instead.'),
        );
    }

    # Generate filename
    my $Timestamp = $TimeObject->CurrentTimestamp();
    $Timestamp =~ s/[: -]//g;
    my $Filename = "${ReportType}_Report_${Timestamp}.xlsx";

    # Return as attachment
    return $LayoutObject->Attachment(
        ContentType => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        Content     => $ExcelContent,
        Filename    => $Filename,
        Type        => 'attachment',
        NoCache     => 1,
    );
}

sub _FormatReportData {
    my ( $Self, $Data, $ReportType ) = @_;

    # Format MTRD data
    if ( $ReportType eq 'mtrd' && $Data->{AverageMTRD} ) {
        $Data->{AverageMTRDFormatted} = $Self->_FormatSecondsToTime( $Data->{AverageMTRD} );
    }

    # Format MTTR data
    if ( $ReportType eq 'mttr' && $Data->{AverageMTTR} ) {
        $Data->{AverageMTTRFormatted} = $Self->_FormatSecondsToTime( $Data->{AverageMTTR} );
    }

    # Format Priority Breakdown
    if ( $Data->{PriorityBreakdown} && ref($Data->{PriorityBreakdown}) eq 'ARRAY' ) {
        for my $Item ( @{$Data->{PriorityBreakdown}} ) {
            $Item->{AverageMTRDFormatted} = $Self->_FormatSecondsToTime( $Item->{AverageMTRD} );
        }
    }

    # Format Source Breakdown
    if ( $Data->{SourceBreakdown} && ref($Data->{SourceBreakdown}) eq 'ARRAY' ) {
        for my $Item ( @{$Data->{SourceBreakdown}} ) {
            $Item->{AverageMTRDFormatted} = $Self->_FormatSecondsToTime( $Item->{AverageMTRD} );
        }
    }

    # Format MSI Handover data
    if ( $ReportType eq 'msi_handover' ) {
        if ( $Data->{SuccessRate} ) {
            $Data->{SuccessRateFormatted} = sprintf( "%.1f", $Data->{SuccessRate} );
        }
        if ( $Data->{AverageHandoverTime} ) {
            $Data->{AverageHandoverTimeFormatted} = $Self->_FormatSecondsToTime( $Data->{AverageHandoverTime} );
        }
    }

    return 1;
}

sub _FormatSecondsToTime {
    my ( $Self, $Seconds ) = @_;

    return '0s' if !$Seconds || $Seconds <= 0;

    my $Days    = int( $Seconds / 86400 );
    my $Hours   = int( ( $Seconds % 86400 ) / 3600 );
    my $Minutes = int( ( $Seconds % 3600 ) / 60 );
    my $Secs    = int( $Seconds % 60 );

    my @Parts;
    push @Parts, "${Days}d"    if $Days;
    push @Parts, "${Hours}h"   if $Hours;
    push @Parts, "${Minutes}m" if $Minutes;
    push @Parts, "${Secs}s"    if $Secs && !$Days;  # Only show seconds if less than a day

    return join( ' ', @Parts ) || '0s';
}

1;