# --
# Copyright (C) 2025 MSST Solutions
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Config::Files::ZZZIncidentModule;

use strict;
use warnings;
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # Frontend module registration
    $Self->{'Frontend::Module'}->{'AgentIncidentForm'} = {
        'Description' => 'Incident Management Form',
        'Title' => 'Incident',
        'NavBarName' => 'Ticket',
        'Group' => [ 'users' ],
    };

    $Self->{'Frontend::Module'}->{'AgentIncidentList'} = {
        'Description' => 'Incident List',
        'Title' => 'Incidents',
        'NavBarName' => 'Ticket',
        'Group' => [ 'users' ],
    };

    # Navigation bar entries
    $Self->{'Frontend::Navigation'}->{'AgentIncidentForm'}->{'002-Incident'} = [
        {
            'AccessKey' => '',
            'Block' => 'ItemArea',
            'Description' => 'Create new incident',
            'Action' => 'AgentIncidentForm',
            'Link' => 'Action=AgentIncidentForm',
            'LinkOption' => '',
            'Name' => 'New Incident',
            'NavBar' => 'Ticket',
            'Type' => 'Menu',
            'Prio' => '200',
        },
    ];

    $Self->{'Frontend::Navigation'}->{'AgentIncidentList'}->{'002-Incident'} = [
        {
            'AccessKey' => '',
            'Block' => 'ItemArea',
            'Description' => 'View all incidents',
            'Action' => 'AgentIncidentList',
            'Link' => 'Action=AgentIncidentList',
            'LinkOption' => '',
            'Name' => 'Incident List',
            'NavBar' => 'Ticket',
            'Type' => 'Menu',
            'Prio' => '210',
        },
    ];

    return 1;
}

1;