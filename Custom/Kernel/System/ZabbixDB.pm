# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::ZabbixDB;

use strict;
use warnings;

use DBI;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Connect {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    # Get connection parameters from config
    my $Host     = $ConfigObject->Get('EventManagement::ZabbixDBHost') || 'localhost';
    my $Port     = $ConfigObject->Get('EventManagement::ZabbixDBPort') || '5432';
    my $Database = $ConfigObject->Get('EventManagement::ZabbixDBName') || 'zabbix';
    my $User     = $ConfigObject->Get('EventManagement::ZabbixDBUser') || 'postgres';
    my $Password = $ConfigObject->Get('EventManagement::ZabbixDBPassword') || '';

    # Build DSN
    my $DSN = "dbi:Pg:dbname=$Database;host=$Host;port=$Port";

    # Connect to database
    my $DBH = DBI->connect(
        $DSN,
        $User,
        $Password,
        {
            RaiseError => 0,
            PrintError => 0,
            AutoCommit => 1,
        }
    );

    if (!$DBH) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixDB: Failed to connect to Zabbix database: " . DBI->errstr,
        );
        return {
            Success      => 0,
            ErrorMessage => "Failed to connect to Zabbix database: " . DBI->errstr,
        };
    }

    $Self->{DBH} = $DBH;

    return {
        Success => 1,
    };
}

sub Disconnect {
    my ( $Self, %Param ) = @_;

    if ($Self->{DBH}) {
        $Self->{DBH}->disconnect();
        delete $Self->{DBH};
    }

    return 1;
}

sub GetProblems {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Connect if not already connected
    if (!$Self->{DBH}) {
        my $ConnectResult = $Self->Connect();
        if (!$ConnectResult->{Success}) {
            return $ConnectResult;
        }
    }

    # Get parameters
    my $Days  = defined $Param{Days} ? $Param{Days} : 0;
    my $Limit = $Param{Limit} || 100;
    my $Offset = $Param{Offset} || 0;
    my $HostFilter = $Param{HostFilter} || '';
    my $StartEpoch = $Param{StartEpoch} || '';
    my $EndEpoch   = $Param{EndEpoch} || '';
    my $HasTicket  = defined $Param{HasTicket} ? $Param{HasTicket} : '';

    # Build WHERE clause
    my $WhereClause = "WHERE p.source = 0";

    # Date range: StartEpoch/EndEpoch takes priority over Days
    if ($StartEpoch && $EndEpoch) {
        $StartEpoch = int($StartEpoch);
        $EndEpoch   = int($EndEpoch);
        $WhereClause .= " AND p.clock >= $StartEpoch AND p.clock <= $EndEpoch";
    }
    elsif ($Days > 0) {
        $WhereClause .= " AND p.clock >= extract(epoch FROM now() - interval '$Days days')";
    }

    if ($HostFilter) {
        # Escape single quotes for safety
        $HostFilter =~ s/'/''/g;
        $WhereClause .= " AND h.host = '$HostFilter'";
    }

    # HasTicket filter: '1' = with ticket, '0' = without ticket
    if ($HasTicket eq '1') {
        $WhereClause .= " AND EXISTS (SELECT 1 FROM problem_tag WHERE eventid = p.eventid AND tag = 'znuny_ticket_nr')";
    }
    elsif ($HasTicket eq '0') {
        $WhereClause .= " AND NOT EXISTS (SELECT 1 FROM problem_tag WHERE eventid = p.eventid AND tag = 'znuny_ticket_nr')";
    }

    # Main query (adapted from bash script)
    my $SQL = qq{
SELECT
    -- PROBLEM
    p.eventid                                               AS problem_eventid,
    to_timestamp(p.clock)                                   AS problem_start_time,
    CASE WHEN p.r_clock > 0 THEN to_timestamp(p.r_clock) ELSE NULL END AS problem_end_time,
    CASE WHEN p.r_clock > 0
         THEN (p.r_clock - p.clock) || ' seconds'
         ELSE 'OPEN'
    END                                                     AS problem_duration,
    p.name                                                  AS problem_name,
    p.severity                                              AS problem_severity,
    CASE p.severity
        WHEN 0 THEN 'Not classified'
        WHEN 1 THEN 'Information'
        WHEN 2 THEN 'Warning'
        WHEN 3 THEN 'Average'
        WHEN 4 THEN 'High'
        WHEN 5 THEN 'Disaster'
    END                                                     AS problem_severity_name,
    p.acknowledged                                          AS problem_acknowledged,

    -- TRIGGER
    t.triggerid                                             AS trigger_triggerid,
    t.description                                           AS trigger_description,
    t.priority                                              AS trigger_priority,
    t.comments                                              AS trigger_comments,
    t.url                                                   AS trigger_url,
    t.opdata                                                AS trigger_opdata,

    -- ITEM
    i.itemid                                                AS item_itemid,
    i.name                                                  AS item_name,
    i.key_                                                  AS item_key,
    CASE i.value_type
        WHEN 0 THEN 'Float'
        WHEN 1 THEN 'String'
        WHEN 2 THEN 'Log'
        WHEN 3 THEN 'Unsigned'
        WHEN 4 THEN 'Text'
    END                                                     AS item_value_type,
    i.units                                                 AS item_units,
    i.description                                           AS item_description,

    -- HOST
    h.hostid                                                AS host_hostid,
    h.host                                                  AS host_host,
    h.name                                                  AS host_name,
    h.description                                           AS host_description,
    CASE h.maintenance_status WHEN 1 THEN 'Yes' ELSE 'No' END AS host_in_maintenance,

    -- INTERFACE
    iface.ip                                                AS interface_ip,
    iface.dns                                               AS interface_dns,

    -- HOST GROUP (aggregated)
    string_agg(DISTINCT hg.name, ', ')                      AS host_groups,

    -- PROBLEM TAGS (aggregated)
    string_agg(DISTINCT pt.tag || '=' || COALESCE(pt.value, ''), ' | ')   AS problem_tags,

    -- ZNUNY TICKET
    MAX(CASE WHEN pt.tag = 'znuny_ticket_nr' THEN pt.value END)   AS znuny_ticket_nr,

    -- ITEM VALUE at problem time (simplified - just get latest before problem)
    (SELECT CASE i.value_type
        WHEN 0 THEN (SELECT value::text FROM history WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1)
        WHEN 3 THEN (SELECT value::text FROM history_uint WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1)
        WHEN 1 THEN (SELECT value FROM history_str WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1)
        WHEN 4 THEN (SELECT value FROM history_text WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1)
        WHEN 2 THEN (SELECT LEFT(value, 500) FROM history_log WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1)
    END)                                                    AS item_value_at_problem_time,

    -- SNMP VARBIND extraction (for log items)
    COALESCE(
        (SELECT substring(value FROM 'enterprises\\.161\\.3\\.10\\.105\\.4\\.0 = \"([^\"]*)\"')
         FROM history_log WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1),
        (SELECT substring(value FROM 'enterprises\\.26267\\.4 = \"\"([^\"]*)\"\"')
         FROM history_log WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1)
    ) AS snmp_item_event_id,

    (SELECT substring(value FROM 'enterprises\\.161\\.3\\.10\\.105\\.6\\.0 = \"([^\"]*)\"')
     FROM history_log WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1
    ) AS snmp_component,

    COALESCE(
        (SELECT substring(value FROM 'enterprises\\.161\\.3\\.10\\.105\\.10\\.0 = \"([^\"]*)\"')
         FROM history_log WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1),
        (SELECT substring(value FROM 'enterprises\\.26267\\.9 = \"\"([^\"]*)\"\"')
         FROM history_log WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1)
    ) AS snmp_device,

    COALESCE(
        (SELECT substring(value FROM 'enterprises\\.161\\.3\\.10\\.105\\.13\\.0 = \"([^\"]*)\"')
         FROM history_log WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1),
        (SELECT substring(value FROM 'enterprises\\.26267\\.5 = \"\"([^\"]*)\"\"')
         FROM history_log WHERE itemid = i.itemid AND clock <= p.clock ORDER BY clock DESC LIMIT 1)
    ) AS snmp_summary_message

FROM problem p

-- Relation: problem -> trigger (1:1)
JOIN triggers t ON t.triggerid = p.objectid

-- Relation: trigger -> item (via functions, taking first)
JOIN functions f ON f.triggerid = t.triggerid
JOIN items i ON i.itemid = f.itemid

-- Relation: item -> host (1:1)
JOIN hosts h ON h.hostid = i.hostid

-- Relation: host -> interface (main interface only)
LEFT JOIN interface iface ON iface.hostid = h.hostid AND iface.main = 1

-- Relation: host -> groups (1:many, aggregated)
LEFT JOIN hosts_groups hgs ON hgs.hostid = h.hostid
LEFT JOIN hstgrp hg ON hg.groupid = hgs.groupid

-- Relation: problem -> tags (1:many, aggregated)
LEFT JOIN problem_tag pt ON pt.eventid = p.eventid

$WhereClause

GROUP BY
    p.eventid, p.clock, p.r_clock, p.name, p.severity, p.acknowledged,
    t.triggerid, t.description, t.priority, t.comments, t.url, t.opdata,
    i.itemid, i.name, i.key_, i.value_type, i.units, i.description,
    h.hostid, h.host, h.name, h.description, h.maintenance_status,
    iface.ip, iface.dns

ORDER BY p.clock DESC
LIMIT $Limit OFFSET $Offset
};

    # Get total count first
    my $CountSQL = qq{
SELECT COUNT(DISTINCT p.eventid)
FROM problem p
JOIN triggers t ON t.triggerid = p.objectid
JOIN functions f ON f.triggerid = t.triggerid
JOIN items i ON i.itemid = f.itemid
JOIN hosts h ON h.hostid = i.hostid
$WhereClause
};

    my $TotalCount = 0;
    my $CountSTH = $Self->{DBH}->prepare($CountSQL);
    if ($CountSTH && $CountSTH->execute()) {
        ($TotalCount) = $CountSTH->fetchrow_array();
        $CountSTH->finish();
    }

    # Execute main query
    my $STH = $Self->{DBH}->prepare($SQL);
    if (!$STH) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixDB: Failed to prepare query: " . $Self->{DBH}->errstr,
        );
        return {
            Success      => 0,
            ErrorMessage => "Failed to prepare query: " . $Self->{DBH}->errstr,
        };
    }

    if (!$STH->execute()) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixDB: Failed to execute query: " . $STH->errstr,
        );
        return {
            Success      => 0,
            ErrorMessage => "Failed to execute query: " . $STH->errstr,
        };
    }

    # Fetch results
    my @Problems;
    while (my $Row = $STH->fetchrow_hashref()) {
        push @Problems, $Row;
    }
    $STH->finish();

    return {
        Success    => 1,
        Problems   => \@Problems,
        TotalCount => $TotalCount,
    };
}

sub TestConnection {
    my ( $Self, %Param ) = @_;

    my $ConnectResult = $Self->Connect();
    if (!$ConnectResult->{Success}) {
        return $ConnectResult;
    }

    # Test with simple query
    my $STH = $Self->{DBH}->prepare("SELECT 1");
    if ($STH && $STH->execute()) {
        $STH->finish();
        $Self->Disconnect();
        return {
            Success => 1,
            Message => 'Connection successful',
        };
    }

    $Self->Disconnect();
    return {
        Success      => 0,
        ErrorMessage => 'Connection test query failed',
    };
}

sub DESTROY {
    my $Self = shift;
    $Self->Disconnect() if $Self->{DBH};
}

1;
