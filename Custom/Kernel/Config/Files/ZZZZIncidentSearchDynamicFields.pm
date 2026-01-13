# --
# Copyright (C) 2024 - MSSTLite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Config::Files::ZZZZIncidentSearchDynamicFields;

use strict;
use warnings;

sub Load {
    my ($File, $Self) = @_;

    # Disable historical values for dropdown fields to only show configured values
    $Self->{'DynamicFields::Driver::BaseSelect::EnableHistoricalValues'} = 0;

    $Self->{'Ticket::Frontend::AgentTicketSearch'}->{'SearchPageShown'} =  '25';
    $Self->{'Ticket::Frontend::AgentTicketSearch'}->{'SortBy::Default'} =  'TicketNumber';

    # Override Dynamic Fields for Agent Ticket Search
    $Self->{'Ticket::Frontend::AgentTicketSearch'}->{'DynamicField'} = {
        # Incident fields
        'TicketNumber'           => 2,
        'IncidentSource'           => 2,
        'Priority'                 => 2,
        
        # Other dynamic fields
        'AlarmID'                      => 2,
        'CI'                           => 2,
        'CIDeviceType'                 => 2,
        'Description'                  => 2,
        'EventID'                      => 2,
        'EventMessage'                 => 2,
        'EventSite'                    => 2,
        
        # Enable AssignedTo dynamic field in search (but not shown by default)
        'AssignedTo'               => 1,
        
    };

    # Configure ticket search result columns to match dashboard widgets
    $Self->{'Ticket::Frontend::AgentTicketSearch'}->{'DefaultColumns'} = {
        'TicketNumber' => '2',
        'Created' => '2',
        'Queue' => '2',
        'DynamicField_AssignedTo' => '2',
        'DynamicField_CI' => '2',
        'Title' => '2',
        'Priority' => '2',
        'State' => '2',
        'Age' => '2',
    };
    $Self->{'Ticket::Frontend::AgentTicketQueue'}->{'DefaultColumns'} =  {
       'TicketNumber' => '2',
        'Created' => '2',
        'Queue' => '2',
        'DynamicField_AssignedTo' => '2',
        'DynamicField_CI' => '2',
        'Title' => '2',
        'Priority' => '2',
        'State' => '2',
        'Age' => '2',
    };
    $Self->{'Ticket::Frontend::AgentTicketStatusView'}->{'DefaultColumns'} =  {
       'TicketNumber' => '2',
        'Created' => '2',
        'Queue' => '2',
        'DynamicField_AssignedTo' => '2',
        'DynamicField_CI' => '2',
        'Title' => '2',
        'Priority' => '2',
        'State' => '2',
        'Age' => '2',
    };
    $Self->{'Ticket::Frontend::AgentTicketEscalationView'}->{'DefaultColumns'} =  {
       'TicketNumber' => '2',
        'Created' => '2',
        'Queue' => '2',
        'DynamicField_AssignedTo' => '2',
        'DynamicField_MSITicketNumber' => '2',
        'DynamicField_MSITicketState' => '2',
        'DynamicField_MSITicketEbondLastUpdateTime' => '2',
        'DynamicField_CI' => '2',
        'Title' => '2',
        'Priority' => '2',
        'State' => '2',
        'Age' => '2',
        'UnreadArticles' => '0',  # Explicitly disable
    };



    # Register the new Basic view for simplified ticket display

    # Hide Preview and Medium views
    $Self->{'Ticket::Frontend::Overview'}->{'Preview'}->{'ModulePriority'} = 0;
    $Self->{'Ticket::Frontend::Overview'}->{'Medium'}->{'ModulePriority'} = 0;
    
    # Keep Small view available but with lower priority
    $Self->{'Ticket::Frontend::Overview'}->{'Small'}->{'ModulePriority'} = 100;
    
    # Set Basic as default view for AgentTicketQueue

    
    # Force Small view as default for queue
    $Self->{'Ticket::Frontend::AgentTicketQueue'}->{'DefaultView'} = 'Small';
    
    # Override the Queue menu link to include View=Small
    $Self->{'Frontend::Navigation'}->{'AgentTicketQueue'}->{'002-Ticket'}->[0]->{'Link'} = 'Action=AgentTicketQueue;View=Small';
    
    # Disable bulk action feature to remove checkbox column
    $Self->{'Ticket::Frontend::BulkFeature'} = 0;
    
    return 1;
}

1;