# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package var::packagesetup::MSSTLiteGenericAgent;

use strict;
use warnings;

sub CreateIncidentAutoCloseJob {
    my (%Param) = @_;

    # Get needed objects
    my $GenericAgentObject = $Kernel::OM->Get('Kernel::System::GenericAgent');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $TypeObject = $Kernel::OM->Get('Kernel::System::Type');
    my $StateObject = $Kernel::OM->Get('Kernel::System::State');
    
    # Get Type ID for 'Incident'
    my %TypeList = $TypeObject->TypeList();
    my $IncidentTypeID;
    for my $TypeID (keys %TypeList) {
        if ($TypeList{$TypeID} eq 'Incident') {
            $IncidentTypeID = $TypeID;
            last;
        }
    }
    
    # Get State IDs
    my $ResolvedStateID = $StateObject->StateLookup(
        State => 'resolved',
    );
    my $ClosedStateID = $StateObject->StateLookup(
        State => 'closed',
    );
    
    if (!$IncidentTypeID || !$ResolvedStateID || !$ClosedStateID) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'MSSTLiteGenericAgent: Could not find required type or state IDs for IncidentAutoClose job',
        );
        return 0;
    }
    
    # Check if job already exists
    my %ExistingJob = $GenericAgentObject->JobGet(
        Name => 'IncidentAutoClose',
    );
    
    if (!%ExistingJob) {
        # Create the GenericAgent job
        my $Success = $GenericAgentObject->JobAdd(
            Name => 'IncidentAutoClose',
            Data => {
                Description => 'Automatically change resolved incident tickets to closed after 3 days',
                Valid => 1,
                # Search parameters - use IDs!
                TypeIDs => [$IncidentTypeID],
                StateIDs => [$ResolvedStateID],
                # Search for tickets in resolved state for more than 3 days
                LastChangeTimeSearchType => 'TimePoint',
                TicketLastChangeTimePoint => '3',
                TicketLastChangeTimePointFormat => 'day',
                TicketLastChangeTimePointStart => 'Before',
                # Action - use ID!
                NewStateID => $ClosedStateID,
                # Schedule information - run every 2 minutes
                ScheduleMinutes => [0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46,48,50,52,54,56,58],  # Every 2 minutes
                ScheduleHours => [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23],  # Every hour
                ScheduleDays => [0,1,2,3,4,5,6],  # Every weekday (0=Sunday, 6=Saturday)
                ScheduleMonths => [1,2,3,4,5,6,7,8,9,10,11,12],  # Every month
            },
            UserID => 1,
        );
        
        if ($Success) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => 'MSSTLiteGenericAgent: Created IncidentAutoClose GenericAgent job',
            );
            return 1;
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => 'MSSTLiteGenericAgent: Failed to create IncidentAutoClose GenericAgent job',
            );
            return 0;
        }
    } else {
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLiteGenericAgent: IncidentAutoClose GenericAgent job already exists',
        );
        return 1;
    }
}

sub RemoveIncidentAutoCloseJob {
    my (%Param) = @_;

    # Get needed objects
    my $GenericAgentObject = $Kernel::OM->Get('Kernel::System::GenericAgent');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Check if job exists
    my %ExistingJob = $GenericAgentObject->JobGet(
        Name => 'IncidentAutoClose',
    );
    
    if (%ExistingJob) {
        my $Success = $GenericAgentObject->JobDelete(
            Name => 'IncidentAutoClose',
            UserID => 1,
        );
        
        if ($Success) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => 'MSSTLiteGenericAgent: Removed IncidentAutoClose GenericAgent job',
            );
            return 1;
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => 'MSSTLiteGenericAgent: Failed to remove IncidentAutoClose GenericAgent job',
            );
            return 0;
        }
    } else {
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLiteGenericAgent: IncidentAutoClose GenericAgent job does not exist',
        );
        return 1;
    }
}

1;