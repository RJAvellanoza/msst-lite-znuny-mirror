# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AgentEventManagementDB;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
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

    # Get parameters (use // '' to preserve '0' values)
    my %GetParam;
    for my $Param (qw(Subaction Days Limit Offset HostFilter StartEpoch EndEpoch HasTicket EntityFilter)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) // '';
    }

    # Handle AJAX request for getting problems
    if ( $GetParam{Subaction} eq 'GetProblems' ) {
        return $Self->_GetProblemsJSON(
            Days       => $GetParam{Days},
            Limit      => $GetParam{Limit},
            Offset     => $GetParam{Offset},
            HostFilter => $GetParam{HostFilter},
            StartEpoch => $GetParam{StartEpoch},
            EndEpoch   => $GetParam{EndEpoch},
            HasTicket  => $GetParam{HasTicket},
        );
    }

    # Build the page output
    my $Output = $LayoutObject->Header(
        Title => 'Event Management (Direct)',
    );
    $Output .= $LayoutObject->NavigationBar();

    # Get problems for initial load
    my $ZabbixDBObject = $Kernel::OM->Get('Kernel::System::ZabbixDB');
    my $Result = $ZabbixDBObject->GetProblems(
        Days       => defined $GetParam{Days} && $GetParam{Days} ne '' ? $GetParam{Days} : 0,
        Limit      => 100,
        Offset     => 0,
        StartEpoch => $GetParam{StartEpoch},
        EndEpoch   => $GetParam{EndEpoch},
        HasTicket  => $GetParam{HasTicket},
    );

    # Pass data to template (include filter params for JS)
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentEventManagementDB',
        Data         => {
            ProblemsJSON   => $JSONObject->Encode( Data => $Result->{Problems} || [] ),
            Success        => $Result->{Success} ? 1 : 0,
            ErrorMessage   => $Result->{ErrorMessage} || '',
            TotalCount     => $Result->{TotalCount} || 0,
            EntityFilter   => $GetParam{EntityFilter} // '',
            StartEpoch     => $GetParam{StartEpoch} // '',
            EndEpoch       => $GetParam{EndEpoch} // '',
            HasTicket      => $GetParam{HasTicket} // '',
        },
    );

    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _GetProblemsJSON {
    my ( $Self, %Param ) = @_;

    my $LayoutObject   = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject     = $Kernel::OM->Get('Kernel::System::JSON');
    my $ZabbixDBObject = $Kernel::OM->Get('Kernel::System::ZabbixDB');

    # Get parameters with defaults
    my $Days   = defined $Param{Days} ? $Param{Days} : 0;
    my $Limit  = $Param{Limit}  || 100;
    my $Offset = $Param{Offset} || 0;

    # Validate limits
    $Days  = int($Days);
    $Limit = int($Limit);
    $Offset = int($Offset);

    # Days: 0 = all time, otherwise 1-3650
    $Days  = 0    if $Days < 0;
    $Days  = 3650 if $Days > 3650;
    $Limit = 50  if $Limit < 50;
    $Limit = 500 if $Limit > 500;

    # Get problems from Zabbix DB
    my $Result = $ZabbixDBObject->GetProblems(
        Days       => $Days,
        Limit      => $Limit,
        Offset     => $Offset,
        HostFilter => $Param{HostFilter} // '',
        StartEpoch => $Param{StartEpoch} // '',
        EndEpoch   => $Param{EndEpoch} // '',
        HasTicket  => $Param{HasTicket} // '',
    );

    # Return JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=utf-8',
        Content     => $JSONObject->Encode(
            Data => {
                Success      => $Result->{Success} ? 1 : 0,
                ErrorMessage => $Result->{ErrorMessage} || '',
                Problems     => $Result->{Problems} || [],
                TotalCount   => $Result->{TotalCount} || 0,
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

1;
