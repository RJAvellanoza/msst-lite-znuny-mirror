# --
# MSSTLITE-88: Incident Dashboard Widgets Configuration
# --

package Kernel::Config::Files::ZZZMSSTLiteIncidentDashboardWidgets;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # Override TicketMetaItemsCount globally to disable flag columns
    {
        no warnings 'redefine';
        require Kernel::Output::HTML::Layout::Ticket;
        *Kernel::Output::HTML::Layout::Ticket::TicketMetaItemsCount = sub {
            return ();  # Return empty - no flag columns
        };
        *Kernel::Output::HTML::Layout::Ticket::TicketMetaItems = sub {
            return ();  # Return empty - no flag data
        };
    }

# Disable flag columns (with star icons) for all dashboard ticket generic widgets
$Self->{'Ticket::Frontend::AgentDashboard'}->{'DefaultColumns'} = {
    'Flag' => '0',  # Disable priority flag column with star icons
    'UnreadArticles' => '0',  # Disable unread articles flag column with star icons
};

# My Incidents Dashboard Widget
$Self->{'DashboardBackend'}->{'0150-MyIncidents'} = {
    'Attributes' => 'StateType=open;StateType=pending reminder;StateType=pending auto;TypeIDs=2',
    'Block' => 'ContentLarge',
    'CacheTTLLocal' => '0.5',
    'Default' => '1',
    'DefaultColumns' => {
        'TicketNumber' => '2',
        'Created' => '2',
        'Queue' => '2',
        'DynamicField_AssignedTo' => '2',
        'DynamicField_CI' => '2',
        'Title' => '2',
        'Priority' => '2',
        'State' => '2',
        'Age' => '2',
    },
    'Description' => 'Active incidents assigned to me',
    'Filter' => 'Owned',
    'Group' => '',
    'Limit' => '25',
    'Mandatory' => '0',
    'Module' => 'Kernel::Output::HTML::Dashboard::TicketGeneric',
    'Permission' => 'ro',
    'Time' => 'Created',
    'Title' => 'My Incidents',
    'SortBy' => 'Priority',
    'OrderBy' => 'Down',
};

# Unassigned Incidents Dashboard Widget
$Self->{'DashboardBackend'}->{'0151-UnassignedIncidents'} = {
    'Attributes' => 'StateType=open;StateType=pending reminder;StateType=pending auto;StateType=new;TypeIDs=2;OwnerIDs=99',
    'Block' => 'ContentLarge',
    'CacheTTLLocal' => '0.5',
    'Default' => '1',
    'DefaultColumns' => {
        'TicketNumber' => '2',
        'Created' => '2',
        'Queue' => '2',
        'DynamicField_AssignedTo' => '2',
        'DynamicField_CI' => '2',
        'Title' => '2',
        'Priority' => '2',
        'State' => '2',
        'Age' => '2',
    },
    'Description' => 'Incidents without assignee (assigned to unassigned user)',
    'Group' => '',
    'Limit' => '25',
    'Mandatory' => '0',
    'Module' => 'Kernel::Output::HTML::Dashboard::TicketGeneric',
    'Permission' => 'ro',
    'Time' => 'Created',
    'Title' => 'Unassigned Incidents',
    'SortBy' => 'Priority',
    'OrderBy' => 'Down',
    'DisableFilters' => '1',
};

# Assigned Incidents Dashboard Widget - Shows all assigned incidents
$Self->{'DashboardBackend'}->{'0152-AssignedIncidents'} = {
    'Attributes' => 'StateType=open;StateType=pending auto;TypeIDs=2',
    'Block' => 'ContentLarge',
    'CacheTTLLocal' => '0.5',
    'Default' => '1',
    'DefaultColumns' => {
        'TicketNumber' => '2',
        'Created' => '2',
        'Queue' => '2',
        'DynamicField_AssignedTo' => '2',
        'DynamicField_CI' => '2',
        'Title' => '2',
        'Priority' => '2',
        'State' => '2',
        'Age' => '2',
    },
    'Description' => 'All assigned incidents system-wide (excludes unassigned)',
    'Group' => '',
    'Limit' => '25',
    'Mandatory' => '0',
    'Module' => 'Kernel::Output::HTML::Dashboard::TicketGeneric',
    'Permission' => 'ro',
    'Time' => 'Created',
    'Title' => 'Assigned Incidents',
    'SortBy' => 'Priority',
    'OrderBy' => 'Down',
    'DisableFilters' => '1',
};

# Incidents in Queues Dashboard Widget - MSSTLITE-202 requirement
$Self->{'DashboardBackend'}->{'0153-IncidentsInQueues'} = {
    'Attributes' => 'StateType=new;StateType=open;StateType=pending auto;TypeIDs=2',
    'Block' => 'ContentLarge',
    'CacheTTLLocal' => '0.5',
    'Default' => '1',
    'DefaultColumns' => {
        'TicketNumber' => '2',
        'Created' => '2',
        'Queue' => '2',
        'DynamicField_AssignedTo' => '2',
        'DynamicField_CI' => '2',
        'Title' => '2',
        'Priority' => '2',
        'State' => '2',
        'Age' => '2',
    },
    'Description' => 'All incidents in queues',
    'Group' => '',
    'Limit' => '25',
    'Mandatory' => '0',
    'Module' => 'Kernel::Output::HTML::Dashboard::TicketGeneric',
    'Permission' => 'ro',
    'Time' => 'Created',
    'Title' => 'Incidents in Queues',
    'SortBy' => 'Priority',
    'OrderBy' => 'Down',
    'DisableFilters' => '1',
};

# Escalated Tickets Dashboard Widget - ALWAYS ENABLED
# Shows incidents that have been submitted to MSI ServiceNow (MSITicketNumber populated)
# NOTE: Widget visibility controlled by EBonding integration module at runtime
$Self->{'DashboardBackend'}->{'0160-EscalatedTickets'} = {
    'Attributes' => 'StateType=new;StateType=open;StateType=pending reminder;StateType=pending auto;TypeIDs=2',
    'Block' => 'ContentLarge',
    'CacheTTLLocal' => '0.5',
    'Default' => '1',
    'DefaultColumns' => {
        'TicketNumber' => '2',
        'Created' => '2',
        'DynamicField_AssignedTo' => '2',
        'DynamicField_MSITicketNumber' => '2',
        'DynamicField_MSITicketState' => '2',
        'DynamicField_CI' => '2',
        'Title' => '2',
        'Priority' => '2',
        'State' => '2',
        'Age' => '2',
    },
    'Description' => 'Incidents escalated to MSI via Easy MSI Escalation',
    'Group' => '',
    'Limit' => '25',
    'Mandatory' => '0',
    'Module' => 'Kernel::Output::HTML::Dashboard::EscalatedTickets',
    'Permission' => 'ro',
    'Time' => 'Created',
    'Title' => 'Escalated Tickets',
    'SortBy' => 'Priority',
    'OrderBy' => 'Down',
    'DisableFilters' => '1',
};

# Disable standard ticket widgets that are not needed
$Self->{'DashboardBackend'}->{'0110-TicketEscalation'} = {};
$Self->{'DashboardBackend'}->{'0120-TicketNew'} = {};
$Self->{'DashboardBackend'}->{'0130-TicketOpen'} = {};
$Self->{'DashboardBackend'}->{'0140-RunningTicketProcess'} = {};
$Self->{'DashboardBackend'}->{'0300-LastMentions'} = {};
$Self->{'DashboardBackend'}->{'0270-TicketQueueOverview'} = {};

}

1;