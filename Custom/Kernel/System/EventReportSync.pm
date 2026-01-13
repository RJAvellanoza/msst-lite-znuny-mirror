# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::EventReportSync;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::ZabbixAPI',
    'Kernel::System::Time',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 SyncEvents()

Main sync method that fetches events from Zabbix and caches them locally.

    my $Result = $EventReportSyncObject->SyncEvents(
        Limit       => 1000,     # Optional, defaults to 500
        LastEventID => 0,        # Optional, for incremental sync
    );

Returns:

    $Result = {
        Success      => 1,
        EventsAdded  => 150,
        EventsUpdated => 25,
        TotalProcessed => 175,
        LastEventID  => 123456,
    };

=cut

sub SyncEvents {
    my ( $Self, %Param ) = @_;

    my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject      = $Kernel::OM->Get('Kernel::System::DB');
    my $ZabbixAPIObject = $Kernel::OM->Get('Kernel::System::ZabbixAPI');

    my $Limit = $Param{Limit} || 500;
    my $LastEventID = $Param{LastEventID} || 0;

    # If no LastEventID provided, get the highest from cache
    if (!$LastEventID) {
        $LastEventID = $Self->_GetLastCachedEventID();
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => "EventReportSync: Starting sync from event ID $LastEventID",
    );

    # Fetch events from Zabbix
    my $Result = $ZabbixAPIObject->GetEvents(
        Limit       => $Limit,
        LastEventID => $LastEventID,
    );

    if (!$Result->{Success}) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "EventReportSync: Failed to get events from Zabbix: " . ($Result->{ErrorMessage} || 'Unknown error'),
        );
        return {
            Success      => 0,
            ErrorMessage => $Result->{ErrorMessage},
        };
    }

    my $Events = $Result->{Events} || [];
    my $EventsAdded = 0;
    my $EventsUpdated = 0;
    my $NewLastEventID = $LastEventID;

    for my $Event (@$Events) {
        my $ProcessResult = $Self->_ProcessEvent(Event => $Event);

        if ($ProcessResult->{Added}) {
            $EventsAdded++;
        }
        elsif ($ProcessResult->{Updated}) {
            $EventsUpdated++;
        }

        # Track highest event ID
        if ($Event->{eventid} && $Event->{eventid} > $NewLastEventID) {
            $NewLastEventID = $Event->{eventid};
        }
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => "EventReportSync: Completed. Added: $EventsAdded, Updated: $EventsUpdated, Total: " . scalar(@$Events),
    );

    return {
        Success        => 1,
        EventsAdded    => $EventsAdded,
        EventsUpdated  => $EventsUpdated,
        TotalProcessed => scalar(@$Events),
        LastEventID    => $NewLastEventID,
    };
}

=head2 SyncFullRange()

Sync all events for a specific date range. Used for historical data population.

    my $Result = $EventReportSyncObject->SyncFullRange(
        TimeFrom => '2024-12-01',  # Start date
        TimeTill => '2024-12-31',  # End date
    );

=cut

sub SyncFullRange {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Validate parameters
    for my $Needed (qw(TimeFrom TimeTill)) {
        if (!$Param{$Needed}) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "EventReportSync::SyncFullRange - Need $Needed!",
            );
            return { Success => 0, ErrorMessage => "Missing $Needed" };
        }
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => "EventReportSync::SyncFullRange - Syncing from $Param{TimeFrom} to $Param{TimeTill}",
    );

    # Convert dates to Unix timestamps
    my $TimeFrom = $Self->_DateToUnix($Param{TimeFrom} . ' 00:00:00');
    my $TimeTill = $Self->_DateToUnix($Param{TimeTill} . ' 23:59:59');

    # We'll need to implement a method in ZabbixAPI that supports time range filtering
    # For now, we'll use the existing GetEvents with pagination
    my $LastEventID = 0;
    my $TotalAdded = 0;
    my $TotalUpdated = 0;
    my $BatchCount = 0;

    while (1) {
        my $Result = $Self->SyncEvents(
            Limit       => 500,
            LastEventID => $LastEventID,
        );

        if (!$Result->{Success}) {
            last;
        }

        $TotalAdded   += $Result->{EventsAdded} || 0;
        $TotalUpdated += $Result->{EventsUpdated} || 0;
        $LastEventID   = $Result->{LastEventID};
        $BatchCount++;

        # If we got fewer events than the limit, we've reached the end
        if ($Result->{TotalProcessed} < 500) {
            last;
        }

        # Safety limit - don't run forever
        if ($BatchCount >= 100) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "EventReportSync::SyncFullRange - Reached batch limit, stopping",
            );
            last;
        }
    }

    return {
        Success       => 1,
        TotalAdded    => $TotalAdded,
        TotalUpdated  => $TotalUpdated,
        BatchesRun    => $BatchCount,
    };
}

=head2 _ProcessEvent()

Process a single event and upsert into cache table.

=cut

sub _ProcessEvent {
    my ( $Self, %Param ) = @_;

    my $Event = $Param{Event};
    return { Success => 0 } if !$Event;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Extract event fields
    my $AlarmID = $Event->{eventid} || '';
    return { Success => 0 } if !$AlarmID;

    my $TriggerID = $Event->{objectid} || '';

    # Convert Unix timestamp to datetime
    my $EventClock = $Self->_UnixToDateTime($Event->{clock});
    my $RClock = $Event->{r_clock} ? $Self->_UnixToDateTime($Event->{r_clock}) : undef;

    my $Severity = $Event->{severity} || 0;
    my $Acknowledged = $Event->{acknowledged} || 0;

    # Extract host info
    my $HostID = '';
    my $HostName = '';
    if ($Event->{hosts} && ref($Event->{hosts}) eq 'ARRAY' && @{$Event->{hosts}}) {
        $HostID = $Event->{hosts}[0]{hostid} || '';
        $HostName = $Event->{hosts}[0]{name} || $Event->{hosts}[0]{host} || '';
    }

    my $EventName = $Event->{name} || '';

    # Check for incident number in tags (znuny_ticket_nr)
    my $HasIncident = 0;
    my $IncidentNumber = '';
    if ($Event->{tags} && ref($Event->{tags}) eq 'ARRAY') {
        for my $Tag (@{$Event->{tags}}) {
            if ($Tag->{tag} && $Tag->{tag} eq 'znuny_ticket_nr' && $Tag->{value}) {
                $HasIncident = 1;
                $IncidentNumber = $Tag->{value};
                last;
            }
        }
    }

    # Check if event already exists
    my $Exists = 0;
    return { Success => 0 } if !$DBObject->Prepare(
        SQL   => 'SELECT id FROM zabbix_event_cache WHERE alarm_id = ?',
        Bind  => [ \$AlarmID ],
        Limit => 1,
    );

    while (my @Row = $DBObject->FetchrowArray()) {
        $Exists = 1;
    }

    my $CurrentTime = $Self->_GetCurrentDateTime();

    if ($Exists) {
        # Update existing event
        my $SQL = 'UPDATE zabbix_event_cache SET
            trigger_id = ?, event_clock = ?, r_clock = ?, severity = ?,
            acknowledged = ?, host_id = ?, host_name = ?, event_name = ?,
            has_incident = ?, incident_number = ?, sync_time = ?
            WHERE alarm_id = ?';

        return { Success => 0 } if !$DBObject->Do(
            SQL  => $SQL,
            Bind => [
                \$TriggerID, \$EventClock, \$RClock, \$Severity,
                \$Acknowledged, \$HostID, \$HostName, \$EventName,
                \$HasIncident, \$IncidentNumber, \$CurrentTime,
                \$AlarmID,
            ],
        );

        return { Success => 1, Updated => 1 };
    }
    else {
        # Insert new event
        my $SQL = 'INSERT INTO zabbix_event_cache
            (alarm_id, trigger_id, event_clock, r_clock, severity,
             acknowledged, host_id, host_name, event_name,
             has_incident, incident_number, sync_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

        return { Success => 0 } if !$DBObject->Do(
            SQL  => $SQL,
            Bind => [
                \$AlarmID, \$TriggerID, \$EventClock, \$RClock, \$Severity,
                \$Acknowledged, \$HostID, \$HostName, \$EventName,
                \$HasIncident, \$IncidentNumber, \$CurrentTime,
            ],
        );

        return { Success => 1, Added => 1 };
    }
}

=head2 _GetLastCachedEventID()

Get the highest event ID in the cache to use for incremental sync.

=cut

sub _GetLastCachedEventID {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return 0 if !$DBObject->Prepare(
        SQL   => 'SELECT MAX(CAST(alarm_id AS BIGINT)) FROM zabbix_event_cache',
        Limit => 1,
    );

    my $LastID = 0;
    while (my @Row = $DBObject->FetchrowArray()) {
        $LastID = $Row[0] || 0;
    }

    return $LastID;
}

=head2 _UnixToDateTime()

Convert Unix timestamp to database datetime format.

=cut

sub _UnixToDateTime {
    my ( $Self, $Unix ) = @_;

    return undef if !$Unix;

    my ($Sec, $Min, $Hour, $Day, $Month, $Year) = localtime($Unix);
    $Year  += 1900;
    $Month += 1;

    return sprintf(
        "%04d-%02d-%02d %02d:%02d:%02d",
        $Year, $Month, $Day, $Hour, $Min, $Sec
    );
}

=head2 _DateToUnix()

Convert datetime string to Unix timestamp.

=cut

sub _DateToUnix {
    my ( $Self, $DateTime ) = @_;

    return 0 if !$DateTime;

    # Parse YYYY-MM-DD HH:MM:SS format
    if ($DateTime =~ /^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/) {
        my ($Year, $Month, $Day, $Hour, $Min, $Sec) = ($1, $2, $3, $4, $5, $6);

        use POSIX qw(mktime);
        return mktime($Sec, $Min, $Hour, $Day, $Month - 1, $Year - 1900);
    }

    return 0;
}

=head2 _GetCurrentDateTime()

Get current datetime in database format.

=cut

sub _GetCurrentDateTime {
    my ( $Self, %Param ) = @_;

    my ($Sec, $Min, $Hour, $Day, $Month, $Year) = localtime();
    $Year  += 1900;
    $Month += 1;

    return sprintf(
        "%04d-%02d-%02d %02d:%02d:%02d",
        $Year, $Month, $Day, $Hour, $Min, $Sec
    );
}

=head2 GetCacheStats()

Get statistics about the event cache.

    my $Stats = $EventReportSyncObject->GetCacheStats();

Returns:

    $Stats = {
        TotalEvents      => 1500,
        WithIncident     => 1200,
        WithoutIncident  => 300,
        LastSyncTime     => '2024-12-13 14:30:00',
        OldestEvent      => '2024-01-01 08:00:00',
        NewestEvent      => '2024-12-13 14:25:00',
    };

=cut

sub GetCacheStats {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my %Stats;

    # Total events
    return {} if !$DBObject->Prepare(
        SQL => 'SELECT COUNT(*),
                SUM(CASE WHEN has_incident = 1 THEN 1 ELSE 0 END),
                SUM(CASE WHEN has_incident = 0 THEN 1 ELSE 0 END),
                MAX(sync_time), MIN(event_clock), MAX(event_clock)
                FROM zabbix_event_cache',
    );

    while (my @Row = $DBObject->FetchrowArray()) {
        $Stats{TotalEvents}     = $Row[0] || 0;
        $Stats{WithIncident}    = $Row[1] || 0;
        $Stats{WithoutIncident} = $Row[2] || 0;
        $Stats{LastSyncTime}    = $Row[3] || '';
        $Stats{OldestEvent}     = $Row[4] || '';
        $Stats{NewestEvent}     = $Row[5] || '';
    }

    return \%Stats;
}

1;
