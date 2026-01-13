# --
# Copyright (C) 2024 MSSTLite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Config::Files::ZZZZMSSTLiteSearchTemplate;

use strict;
use warnings;

sub Load {
    my ($File, $Self) = @_;

    # Define a default search template for MSSTLite
    $Self->{'Ticket::SearchTemplate::MSSTLiteDefault'} = {
        Name => 'MSSTLite Default Search',
        Config => {
            # Standard fields
            TicketNumber => 1,  # Show by default
            PriorityIDs => 1,
            # StateIDs => 1,  # Removed - defined in Defaults section below
            # QueueIDs => 1,  # Removed - only one queue in use
            OwnerIDs => 1,
            Title => 1,
            
            # Time fields - show by default
            TicketCreateTimePoint => 1,  # Show create time (before/after) by default
            TicketCreateTimeSlot => 1,  # Show create time (between) by default
            
            # Dynamic fields to show
            # DynamicField_TicketNumber => 1,  # Removed - regular TicketNumber is used instead
            DynamicField_IncidentSource => 1,
            DynamicField_Priority => 1,
            DynamicField_AlarmID => 1,
            DynamicField_CI => 1,
            DynamicField_CIDeviceType => 1,
            DynamicField_Description => 1,
            DynamicField_EventID => 1,
            DynamicField_EventMessage => 1,
            DynamicField_EventSite => 1,
        },
    };

    # Auto-load this template when accessing ticket search
    $Self->{'Ticket::Frontend::AgentTicketSearch'}->{'DefaultSearchTemplate'} = 'MSSTLiteDefault';

    # Commented out - let Znuny use its default attributes which includes all time fields
    # Overriding this was preventing time fields from appearing in dropdown
    # $Self->{'Ticket::Frontend::AgentTicketSearch'}->{'Attributes'} = {
    #     # Core ticket fields
    #     'TicketNumber' => 'Ticket Number',
    #     'Title' => 'Short Description',
    #     'StateIDs' => 'State',
    #     'PriorityIDs' => 'Priority',
    #     # 'QueueIDs' => 'Queue',  # Removed - only one queue in use
    #     'OwnerIDs' => 'Assigned To',
    #     'CreatedUserIDs' => 'Created by',
    #     
    #     # Time fields (only the ones needed)
    #     'TicketCreateTimePoint' => 'Ticket Create Time (before/after)',
    #     'TicketCreateTimeSlot' => 'Ticket Create Time (between)',
    # };

    # Set default fields to show when opening search
    $Self->{'Ticket::Frontend::AgentTicketSearch'}->{'Defaults'} = {
        'TicketNumber' => '',  # Show Ticket Number field by default
        'StateIDs' => ['1', '4', '6', '7', '8'],  # new, open, pending reminder, pending auto close+, pending auto close-
        
        # Show Ticket Create Time (before/after)
        'TicketCreateTimePoint' => '1',
        'TicketCreateTimePointStart' => 'Last',
        'TicketCreateTimePointValue' => '7',
        'TicketCreateTimePointFormat' => 'day',
        
        # Show Ticket Create Time (between)
        'TicketCreateTimeSlot' => '1',
        'TicketCreateTimeStartMonth' => '',
        'TicketCreateTimeStartDay' => '',
        'TicketCreateTimeStartYear' => '',
        'TicketCreateTimeStopMonth' => '',
        'TicketCreateTimeStopDay' => '',
        'TicketCreateTimeStopYear' => '',
    };

    return 1;
}

1;
