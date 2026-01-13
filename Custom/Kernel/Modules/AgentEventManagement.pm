# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AgentEventManagement;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Log',
    'Kernel::System::JSON',
    'Kernel::System::ZabbixAPI',
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
    for my $Param (qw(Subaction Limit LastEventID)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Handle AJAX request for getting events
    if ( $GetParam{Subaction} eq 'GetEvents' ) {
        return $Self->_GetEventsJSON(
            Limit       => $GetParam{Limit},
            LastEventID => $GetParam{LastEventID},
        );
    }

    # Build the page output
    my $Output = $LayoutObject->Header(
        Title => 'Event Management',
    );
    $Output .= $LayoutObject->NavigationBar();

    # Get events for initial load (first page, 100 per page)
    my $ZabbixAPIObject = $Kernel::OM->Get('Kernel::System::ZabbixAPI');
    my $EventsResult = $ZabbixAPIObject->GetEvents(
        Limit  => 100,
        Offset => 0,
    );

    # Pass data to template
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentEventManagement',
        Data         => {
            EventsJSON   => $JSONObject->Encode( Data => $EventsResult->{Events} || [] ),
            Success      => $EventsResult->{Success} ? 1 : 0,
            ErrorMessage => $EventsResult->{ErrorMessage} || '',
            TotalCount   => $EventsResult->{TotalCount} || 0,
        },
    );

    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetEventsJSON {
    my ( $Self, %Param ) = @_;

    my $LayoutObject    = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject      = $Kernel::OM->Get('Kernel::System::JSON');
    my $ZabbixAPIObject = $Kernel::OM->Get('Kernel::System::ZabbixAPI');

    # Get limit parameter (default 100)
    my $Limit = $Param{Limit} || 100;
    $Limit = int($Limit);
    $Limit = 50   if $Limit < 50;
    $Limit = 500  if $Limit > 500;

    # Get LastEventID for pagination
    my $LastEventID = $Param{LastEventID} || 0;
    $LastEventID = int($LastEventID);

    # Get events from Zabbix
    my $EventsResult = $ZabbixAPIObject->GetEvents(
        Limit       => $Limit,
        LastEventID => $LastEventID,
    );

    # Return JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success      => $EventsResult->{Success} ? 1 : 0,
                ErrorMessage => $EventsResult->{ErrorMessage} || '',
                Events       => $EventsResult->{Events} || [],
                TotalCount   => $EventsResult->{TotalCount} || 0,
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

1;
