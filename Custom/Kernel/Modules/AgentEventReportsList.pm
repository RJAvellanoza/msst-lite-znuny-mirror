# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentEventReportsList;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Log',
    'Kernel::System::DB',
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
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    # Get parameters
    my %GetParam;
    for my $Param (qw(StartDate EndDate IncidentStatus OrderBy OrderDir Page)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Set defaults
    $GetParam{IncidentStatus} ||= 'all';
    $GetParam{OrderBy} ||= 'event_clock';
    $GetParam{OrderDir} ||= 'DESC';
    $GetParam{Page} ||= 1;

    my $PageSize = 50;
    my $Offset = ($GetParam{Page} - 1) * $PageSize;

    # Validate dates
    if (!$GetParam{StartDate} || !$GetParam{EndDate}) {
        return $LayoutObject->ErrorScreen(
            Message => 'Missing date parameters',
        );
    }

    # Build SQL
    my $SQL = q{
        SELECT
            alarm_id, trigger_id, event_clock, r_clock,
            severity, acknowledged, host_id, host_name,
            event_name, has_incident, incident_number
        FROM zabbix_event_cache
        WHERE event_clock >= ?
          AND event_clock <= ?
    };

    my @Bind = (\$GetParam{StartDate}, \$GetParam{EndDate});

    # Filter by incident status
    if ($GetParam{IncidentStatus} eq 'with') {
        $SQL .= ' AND has_incident = 1';
    }
    elsif ($GetParam{IncidentStatus} eq 'without') {
        $SQL .= ' AND has_incident = 0';
    }

    # Validate and apply ordering
    my %ValidOrderBy = (
        alarm_id     => 'alarm_id',
        event_clock  => 'event_clock',
        severity     => 'severity',
        host_name    => 'host_name',
        has_incident => 'has_incident',
    );

    my $OrderBy = $ValidOrderBy{$GetParam{OrderBy}} || 'event_clock';
    my $OrderDir = ($GetParam{OrderDir} eq 'ASC') ? 'ASC' : 'DESC';

    $SQL .= " ORDER BY $OrderBy $OrderDir";
    $SQL .= " LIMIT $PageSize OFFSET $Offset";

    # Get total count for pagination
    my $CountSQL = q{
        SELECT COUNT(*)
        FROM zabbix_event_cache
        WHERE event_clock >= ?
          AND event_clock <= ?
    };

    my @CountBind = (\$GetParam{StartDate}, \$GetParam{EndDate});

    if ($GetParam{IncidentStatus} eq 'with') {
        $CountSQL .= ' AND has_incident = 1';
    }
    elsif ($GetParam{IncidentStatus} eq 'without') {
        $CountSQL .= ' AND has_incident = 0';
    }

    my $TotalCount = 0;
    if ($DBObject->Prepare( SQL => $CountSQL, Bind => \@CountBind )) {
        while (my @Row = $DBObject->FetchrowArray()) {
            $TotalCount = $Row[0] || 0;
        }
    }

    # Fetch events
    my @Events;
    if ($DBObject->Prepare( SQL => $SQL, Bind => \@Bind )) {
        while (my @Row = $DBObject->FetchrowArray()) {
            push @Events, {
                AlarmID        => $Row[0] || '',
                TriggerID      => $Row[1] || '',
                EventClock     => $Row[2] || '',
                RClock         => $Row[3] || '',
                Severity       => $Row[4] || 0,
                Acknowledged   => $Row[5] || 0,
                HostID         => $Row[6] || '',
                HostName       => $Row[7] || '',
                EventName      => $Row[8] || '',
                HasIncident    => $Row[9] || 0,
                IncidentNumber => $Row[10] || '',
            };
        }
    }

    # Calculate pagination
    my $TotalPages = int(($TotalCount + $PageSize - 1) / $PageSize);
    $TotalPages = 1 if $TotalPages < 1;

    # Build output
    my $Output = $LayoutObject->Header(
        Title => 'Event Reports - Details',
    );
    $Output .= $LayoutObject->NavigationBar();

    # Pass data to template
    for my $Event (@Events) {
        $LayoutObject->Block(
            Name => 'EventRow',
            Data => $Event,
        );
    }

    if (!@Events) {
        $LayoutObject->Block(
            Name => 'NoEvents',
        );
    }

    # Pagination links
    if ($GetParam{Page} > 1) {
        $LayoutObject->Block(
            Name => 'PrevPage',
            Data => {
                PrevPage => $GetParam{Page} - 1,
                StartDate => $GetParam{StartDate},
                EndDate => $GetParam{EndDate},
                IncidentStatus => $GetParam{IncidentStatus},
                OrderBy => $GetParam{OrderBy},
                OrderDir => $GetParam{OrderDir},
            },
        );
    }

    if ($GetParam{Page} < $TotalPages) {
        $LayoutObject->Block(
            Name => 'NextPage',
            Data => {
                NextPage => $GetParam{Page} + 1,
                StartDate => $GetParam{StartDate},
                EndDate => $GetParam{EndDate},
                IncidentStatus => $GetParam{IncidentStatus},
                OrderBy => $GetParam{OrderBy},
                OrderDir => $GetParam{OrderDir},
            },
        );
    }

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentEventReportsList',
        Data         => {
            StartDate      => $GetParam{StartDate},
            EndDate        => $GetParam{EndDate},
            IncidentStatus => $GetParam{IncidentStatus},
            OrderBy        => $GetParam{OrderBy},
            OrderDir       => $GetParam{OrderDir},
            CurrentPage    => $GetParam{Page},
            TotalPages     => $TotalPages,
            TotalCount     => $TotalCount,
            EventCount     => scalar(@Events),
        },
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

1;
