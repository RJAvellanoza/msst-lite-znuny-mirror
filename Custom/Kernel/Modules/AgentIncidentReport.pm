# --
# Copyright (C) 2025 MSST Lite
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentIncidentReport;

use strict;
use warnings;

use Kernel::Language qw(Translatable);
use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Web::Request',
    'Kernel::System::IncidentReporting',
    'Kernel::System::Log',
    'Kernel::System::JSON',
);

=head1 NAME

Kernel::Modules::AgentIncidentReport - Frontend module for Incident Report

=head1 DESCRIPTION

Provides the frontend interface for incident reporting and analytics.

=head1 PUBLIC INTERFACE

=head2 new()

Create an object.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

=head2 Run()

Handle the HTTP request.

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject             = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject              = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $IncidentReportingObject  = $Kernel::OM->Get('Kernel::System::IncidentReporting');
    my $ConfigObject             = $Kernel::OM->Get('Kernel::Config');
    my $JSONObject               = $Kernel::OM->Get('Kernel::System::JSON');

    # get subaction
    my $Subaction = $ParamObject->GetParam( Param => 'Subaction' ) || '';

    # route to appropriate handler
    if ( $Subaction eq 'GetTrendingData' ) {
        return $Self->_GetTrendingData();
    }
    elsif ( $Subaction eq 'GetTabularData' ) {
        return $Self->_GetTabularData();
    }
    elsif ( $Subaction eq 'GetMSIHandoverData' ) {
        return $Self->_GetMSIHandoverData();
    }
    elsif ( $Subaction eq 'ExportCSV' ) {
        return $Self->_ExportCSV();
    }
    elsif ( $Subaction eq 'ExportExcel' ) {
        return $Self->_ExportExcel();
    }

    # default: show main page
    return $Self->_ShowMainPage();
}

=begin Internal:

=head2 _ShowMainPage()

Render the main report page.

=cut

sub _ShowMainPage {
    my ( $Self, %Param ) = @_;

    my $LayoutObject            = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject            = $Kernel::OM->Get('Kernel::Config');
    my $IncidentReportingObject = $Kernel::OM->Get('Kernel::System::IncidentReporting');
    my $JSONObject              = $Kernel::OM->Get('Kernel::System::JSON');

    # get default settings
    my $DefaultTimeRange = $ConfigObject->Get('IncidentReporting::DefaultTimeRange') || 'weekly';
    my $EnableMSIAnalysis = $ConfigObject->Get('IncidentReporting::EnableMSIAnalysis') || 1;

    # prepare chart data for initial page load
    my %ChartData;

    # get trend chart data
    my $TrendChartData = $IncidentReportingObject->GetTrendChartData(
        TimeRange => $DefaultTimeRange,
    );
    $ChartData{TrendChart} = $TrendChartData if $TrendChartData;

    # get source chart data
    my $SourceChartData = $IncidentReportingObject->GetSourceChartData(
        TimeRange => $DefaultTimeRange,
    );
    $ChartData{SourceChart} = $SourceChartData if $SourceChartData;

    # get state chart data
    my $StateChartData = $IncidentReportingObject->GetStateChartData(
        TimeRange => $DefaultTimeRange,
    );
    $ChartData{StateChart} = $StateChartData if $StateChartData;

    # get top devices chart data
    my $TopDevicesData = $IncidentReportingObject->GetTopDevicesChartData(
        TimeRange => $DefaultTimeRange,
    );
    $ChartData{TopDevicesChart} = $TopDevicesData if $TopDevicesData;

    # get resolution time histogram data
    my $ResolutionTimeData = $IncidentReportingObject->GetResolutionTimeHistogramData(
        TimeRange => $DefaultTimeRange,
    );
    $ChartData{ResolutionTimeChart} = $ResolutionTimeData if $ResolutionTimeData;

    # encode chart data as JSON and inject into page
    my $ChartDataJSON = $JSONObject->Encode( Data => \%ChartData );
    $LayoutObject->AddJSOnDocumentComplete(
        Code => "window.IncidentReportChartData = $ChartDataJSON;",
    );

    # prepare template data
    $LayoutObject->Block(
        Name => 'IncidentReport',
        Data => {
            DefaultTimeRange  => $DefaultTimeRange,
            EnableMSIAnalysis => $EnableMSIAnalysis,
        },
    );

    # output header
    my $Output = $LayoutObject->Header(
        Title => Translatable('Incident Report'),
    );
    $Output .= $LayoutObject->NavigationBar();

    # output main template
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentIncidentReport',
        Data         => {
            %Param,
            DefaultTimeRange  => $DefaultTimeRange,
            EnableMSIAnalysis => $EnableMSIAnalysis,
        },
    );

    # output footer
    $Output .= $LayoutObject->Footer();

    return $Output;
}

=head2 _GetTrendingData()

Get trending data via AJAX.

=cut

sub _GetTrendingData {
    my ( $Self, %Param ) = @_;

    my $LayoutObject            = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject             = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $IncidentReportingObject = $Kernel::OM->Get('Kernel::System::IncidentReporting');
    my $JSONObject              = $Kernel::OM->Get('Kernel::System::JSON');
    my $LogObject               = $Kernel::OM->Get('Kernel::System::Log');

    # get parameters
    my $TimeRange = $ParamObject->GetParam( Param => 'TimeRange' ) || 'weekly';
    my $StartDate = $ParamObject->GetParam( Param => 'StartDate' );
    my $EndDate   = $ParamObject->GetParam( Param => 'EndDate' );

    # get trending data
    my $Result = $IncidentReportingObject->GetTrendingData(
        TimeRange => $TimeRange,
        StartDate => $StartDate,
        EndDate   => $EndDate,
    );

    if ( !$Result ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Failed to get trending data',
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=utf-8',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    Message => 'Failed to retrieve trending data',
                },
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }

    # return JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success => 1,
                Data    => $Result,
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

=head2 _GetTabularData()

Get tabular data via AJAX.

=cut

sub _GetTabularData {
    my ( $Self, %Param ) = @_;

    my $LayoutObject            = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject             = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $IncidentReportingObject = $Kernel::OM->Get('Kernel::System::IncidentReporting');
    my $JSONObject              = $Kernel::OM->Get('Kernel::System::JSON');
    my $LogObject               = $Kernel::OM->Get('Kernel::System::Log');

    # get parameters
    my $TimeRange = $ParamObject->GetParam( Param => 'TimeRange' ) || 'weekly';
    my $Page      = $ParamObject->GetParam( Param => 'Page' ) || 1;
    my $PageSize  = $ParamObject->GetParam( Param => 'PageSize' ) || 100;

    # get tabular data
    my $Result = $IncidentReportingObject->GetTabularData(
        TimeRange => $TimeRange,
        Page      => $Page,
        PageSize  => $PageSize,
    );

    if ( !$Result ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Failed to get tabular data',
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=utf-8',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    Message => 'Failed to retrieve tabular data',
                },
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }

    # return JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success => 1,
                Data    => $Result,
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

=head2 _GetMSIHandoverData()

Get MSI handover data via AJAX.

=cut

sub _GetMSIHandoverData {
    my ( $Self, %Param ) = @_;

    my $LayoutObject            = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject             = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $IncidentReportingObject = $Kernel::OM->Get('Kernel::System::IncidentReporting');
    my $JSONObject              = $Kernel::OM->Get('Kernel::System::JSON');
    my $LogObject               = $Kernel::OM->Get('Kernel::System::Log');

    # get parameters
    my $TimeRange = $ParamObject->GetParam( Param => 'TimeRange' ) || 'weekly';

    # get MSI handover data
    my $Result = $IncidentReportingObject->GetMSIHandoverData(
        TimeRange => $TimeRange,
    );

    if ( !$Result ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Failed to get MSI handover data',
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=utf-8',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    Message => 'Failed to retrieve MSI handover data',
                },
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }

    # return JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success => 1,
                Data    => $Result,
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

=head2 _ExportCSV()

Export data to CSV format.

=cut

sub _ExportCSV {
    my ( $Self, %Param ) = @_;

    my $LayoutObject            = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject             = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $IncidentReportingObject = $Kernel::OM->Get('Kernel::System::IncidentReporting');
    my $LogObject               = $Kernel::OM->Get('Kernel::System::Log');

    # get parameters
    my $TimeRange = $ParamObject->GetParam( Param => 'TimeRange' ) || 'weekly';

    # get ALL data (no pagination for export)
    my $Result = $IncidentReportingObject->GetTabularData(
        TimeRange => $TimeRange,
        Page      => 1,
        PageSize  => 999999,  # get all records
    );

    if ( !$Result || !$Result->{Tickets} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Failed to get data for CSV export',
        );
        return $LayoutObject->ErrorScreen(
            Message => 'Failed to retrieve data for export',
        );
    }

    # generate CSV
    my $CSV = $IncidentReportingObject->ExportToCSV(
        Data => $Result,
    );

    if ( !$CSV ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Failed to generate CSV',
        );
        return $LayoutObject->ErrorScreen(
            Message => 'Failed to generate CSV export',
        );
    }

    # generate filename
    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = localtime();
    $Year  += 1900;
    $Month += 1;
    my $DateStr = sprintf( "%04d%02d%02d_%02d%02d%02d", $Year, $Month, $Day, $Hour, $Min, $Sec );
    my $Filename = "incident_report_$DateStr.csv";

    # return CSV as download
    return $LayoutObject->Attachment(
        ContentType => 'text/csv; charset=utf-8',
        Content     => $CSV,
        Filename    => $Filename,
        Type        => 'attachment',
        NoCache     => 1,
    );
}

=head2 _ExportExcel()

Export data to Excel format (XLSX).

Note: This is a placeholder. Excel export requires additional Perl modules.
For now, it returns CSV with .xlsx extension.

=cut

sub _ExportExcel {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    # TODO: Implement Excel export using Spreadsheet::WriteExcel or Excel::Writer::XLSX
    # For now, return error message

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'Excel export not yet implemented, use CSV export instead',
    );

    return $LayoutObject->ErrorScreen(
        Message => 'Excel export is not yet implemented. Please use CSV export instead.',
    );
}

=end Internal:

=cut

1;
