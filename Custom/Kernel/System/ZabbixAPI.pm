# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::ZabbixAPI;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;

our @ObjectDependencies = (
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::ZabbixConfig',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # Cache settings for auth tokens
    $Self->{CacheType} = 'ZabbixAPI';
    $Self->{CacheTTL}  = 60 * 30;  # 30 minutes for auth tokens

    return $Self;
}

sub TestConnection {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    for my $Needed (qw(APIURL APIUser APIPassword)) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Need $Needed!",
            };
        }
    }

    # Try to authenticate
    my $AuthResult = $Self->Authenticate(
        APIURL      => $Param{APIURL},
        APIUser     => $Param{APIUser},
        APIPassword => $Param{APIPassword},
    );

    if ( $AuthResult->{Success} && $AuthResult->{AuthToken} ) {
        return {
            Success => 1,
            Message => 'Connection successful',
        };
    }

    return {
        Success      => 0,
        ErrorMessage => $AuthResult->{ErrorMessage} || 'Authentication failed',
    };
}

sub Authenticate {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check needed stuff
    for my $Needed (qw(APIURL APIUser APIPassword)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "ZabbixAPI::Authenticate - Need $Needed!",
            );
            return {
                Success      => 0,
                ErrorMessage => "Missing $Needed",
            };
        }
    }

    # Check cache for existing auth token
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    my $CacheKey = 'Auth::' . $Param{APIUser} . '::' . $Param{APIURL};
    
    my $CachedAuth = $CacheObject->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );

    if ($CachedAuth) {
        return {
            Success   => 1,
            AuthToken => $CachedAuth,
        };
    }

    # Prepare authentication request
    my $AuthRequest = {
        jsonrpc => '2.0',
        method  => 'user.login',
        params  => {
            username => $Param{APIUser},
            password => $Param{APIPassword},
        },
        id => 1,
    };

    # Send request
    my $Response = $Self->_SendRequest(
        URL     => $Param{APIURL},
        Request => $AuthRequest,
    );

    if ( !$Response->{Success} ) {
        return {
            Success      => 0,
            ErrorMessage => $Response->{ErrorMessage},
        };
    }

    # Check for auth token in response
    if ( $Response->{Data}->{result} ) {
        my $AuthToken = $Response->{Data}->{result};
        
        # Cache the auth token
        $CacheObject->Set(
            Type  => $Self->{CacheType},
            Key   => $CacheKey,
            Value => $AuthToken,
            TTL   => $Self->{CacheTTL},
        );

        return {
            Success   => 1,
            AuthToken => $AuthToken,
        };
    }

    # Check for error in response
    my $ErrorMessage = 'Authentication failed';
    if ( $Response->{Data}->{error} ) {
        $ErrorMessage = $Response->{Data}->{error}->{message} 
                     || $Response->{Data}->{error}->{data}
                     || 'Unknown error';
    }

    return {
        Success      => 0,
        ErrorMessage => $ErrorMessage,
    };
}

sub CloseEvent {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check needed stuff
    for my $Needed (qw(EventID TicketNumber)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "ZabbixAPI::CloseEvent - Need $Needed!",
            );
            return {
                Success      => 0,
                ErrorMessage => "Missing $Needed",
            };
        }
    }

    # Get configuration
    my $ZabbixConfigObject = $Kernel::OM->Get('Kernel::System::ZabbixConfig');
    
    my $APIURL      = $ZabbixConfigObject->GetAPIURL();
    my $APIUser     = $ZabbixConfigObject->GetAPIUser();
    my $APIPassword = $ZabbixConfigObject->GetAPIPassword();

    if ( !$APIURL || !$APIUser || !$APIPassword ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'ZabbixAPI::CloseEvent - Zabbix not configured properly',
        );
        return {
            Success      => 0,
            ErrorMessage => 'Zabbix integration not configured',
        };
    }

    # Get auth token
    my $AuthResult = $Self->Authenticate(
        APIURL      => $APIURL,
        APIUser     => $APIUser,
        APIPassword => $APIPassword,
    );

    if ( !$AuthResult->{Success} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixAPI::CloseEvent - Authentication failed: " . ($AuthResult->{ErrorMessage} || ''),
        );
        return {
            Success      => 0,
            ErrorMessage => 'Authentication failed',
        };
    }

    # Prepare close event request
    my $CloseRequest = {
        jsonrpc => '2.0',
        method  => 'event.acknowledge',
        params  => {
            eventids => $Param{EventID},
            action   => 1,  # 4 = acknowledge (works even when manual close is disabled)
            message  => "Problem acknowledged by Ticket $Param{TicketNumber}",
        },
        auth => $AuthResult->{AuthToken},
        id   => 1,
    };

    # Send request
    my $Response = $Self->_SendRequest(
        URL     => $APIURL,
        Request => $CloseRequest,
    );

    # Check if session expired and retry with fresh authentication
    if ( $Response->{Success} && $Response->{Data}->{error} 
         && $Response->{Data}->{error}->{data} 
         && $Response->{Data}->{error}->{data} =~ /Session terminated|re-login/i ) {
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'ZabbixAPI::CloseEvent - Session expired, re-authenticating',
        );
        
        # Clear cached auth token
        my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
        my $CacheKey = 'Auth::' . $APIUser . '::' . $APIURL;
        $CacheObject->Delete(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );
        
        # Re-authenticate
        $AuthResult = $Self->Authenticate(
            APIURL      => $APIURL,
            APIUser     => $APIUser,
            APIPassword => $APIPassword,
        );
        
        if ( !$AuthResult->{Success} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "ZabbixAPI::CloseEvent - Re-authentication failed: " . ($AuthResult->{ErrorMessage} || ''),
            );
            return {
                Success      => 0,
                ErrorMessage => 'Re-authentication failed after session expiry',
            };
        }
        
        # Update request with new auth token
        $CloseRequest->{auth} = $AuthResult->{AuthToken};
        
        # Retry the request
        $Response = $Self->_SendRequest(
            URL     => $APIURL,
            Request => $CloseRequest,
        );
    }

    if ( !$Response->{Success} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixAPI::CloseEvent - Request failed: " . ($Response->{ErrorMessage} || ''),
        );
        return {
            Success      => 0,
            ErrorMessage => $Response->{ErrorMessage},
        };
    }

    # Check for success in response
    if ( $Response->{Data}->{result} ) {
        
        # Log to audit table
        $Self->_LogAudit(
            TicketID     => $Param{TicketID},
            Action       => 'CloseEvent',
            EventID      => $Param{EventID},
            TicketNumber => $Param{TicketNumber},
            Success      => 1,
        );

        return {
            Success => 1,
            Message => 'Event closed successfully',
        };
    }

    # Handle error response
    my $ErrorMessage = 'Failed to close event';
    if ( $Response->{Data}->{error} ) {
        $ErrorMessage = $Response->{Data}->{error}->{message} || 'Unknown error';
        # Append detailed error data if available
        if ( $Response->{Data}->{error}->{data} ) {
            $ErrorMessage .= ': ' . $Response->{Data}->{error}->{data};
        }
    }

    # Log to audit table
    $Self->_LogAudit(
        TicketID     => $Param{TicketID},
        Action       => 'CloseEvent',
        EventID      => $Param{EventID},
        TicketNumber => $Param{TicketNumber},
        Success      => 0,
        ErrorMessage => $ErrorMessage,
    );

    return {
        Success      => 0,
        ErrorMessage => $ErrorMessage,
    };
}

sub _SendRequest {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check needed stuff
    for my $Needed (qw(URL Request)) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Need $Needed!",
            };
        }
    }

    # Create user agent
    my $UserAgent = LWP::UserAgent->new(
        timeout => 30,
        agent   => 'ZNUNY-Zabbix-Integration/1.0',
    );

    # Encode request to JSON
    my $JSONRequest;
    eval {
        $JSONRequest = encode_json( $Param{Request} );
    };
    if ($@) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixAPI::_SendRequest - JSON encode error: $@",
        );
        return {
            Success      => 0,
            ErrorMessage => 'Failed to encode request',
        };
    }

    # Create HTTP request
    my $HTTPRequest = HTTP::Request->new(
        'POST',
        $Param{URL},
        [ 'Content-Type' => 'application/json-rpc' ],
        $JSONRequest,
    );

    # Send request
    my $HTTPResponse;
    eval {
        $HTTPResponse = $UserAgent->request($HTTPRequest);
    };
    if ($@) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixAPI::_SendRequest - Request error: $@",
        );
        return {
            Success      => 0,
            ErrorMessage => "Connection error: $@",
        };
    }

    # Check HTTP response
    if ( !$HTTPResponse->is_success ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixAPI::_SendRequest - HTTP error: " . $HTTPResponse->status_line,
        );
        return {
            Success      => 0,
            ErrorMessage => 'HTTP error: ' . $HTTPResponse->status_line,
        };
    }

    # Decode JSON response
    my $ResponseData;
    eval {
        $ResponseData = decode_json( $HTTPResponse->content );
    };
    if ($@) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixAPI::_SendRequest - JSON decode error: $@",
        );
        return {
            Success      => 0,
            ErrorMessage => 'Invalid JSON response',
        };
    }

    return {
        Success => 1,
        Data    => $ResponseData,
    };
}

sub GetEvents {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Get configuration
    my $ZabbixConfigObject = $Kernel::OM->Get('Kernel::System::ZabbixConfig');

    my $APIURL      = $ZabbixConfigObject->GetAPIURL();
    my $APIUser     = $ZabbixConfigObject->GetAPIUser();
    my $APIPassword = $ZabbixConfigObject->GetAPIPassword();

    if ( !$APIURL || !$APIUser || !$APIPassword ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'ZabbixAPI::GetEvents - Zabbix not configured properly',
        );
        return {
            Success      => 0,
            ErrorMessage => 'Zabbix integration not configured',
            Events       => [],
        };
    }

    # Get auth token
    my $AuthResult = $Self->Authenticate(
        APIURL      => $APIURL,
        APIUser     => $APIUser,
        APIPassword => $APIPassword,
    );

    if ( !$AuthResult->{Success} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixAPI::GetEvents - Authentication failed: " . ($AuthResult->{ErrorMessage} || ''),
        );
        return {
            Success      => 0,
            ErrorMessage => 'Authentication failed: ' . ($AuthResult->{ErrorMessage} || ''),
            Events       => [],
        };
    }

    # Step 1: Get total count for pagination
    my $CountRequest = {
        jsonrpc => '2.0',
        method  => 'event.get',
        params  => {
            countOutput => \1,
            source      => 0,    # trigger events
            value       => 1,    # problem events only
        },
        auth => $AuthResult->{AuthToken},
        id   => 1,
    };

    my $CountResponse = $Self->_SendRequest(
        URL     => $APIURL,
        Request => $CountRequest,
    );
    my $TotalCount = $CountResponse->{Data}->{result} || 0;

    # Step 2: Get events with fields for LSMP format
    my $Limit = $Param{Limit} || 100;
    my $LastEventID = $Param{LastEventID} || 0;  # For pagination (get events before this ID)

    my $EventParams = {
        output      => ['eventid', 'clock', 'name', 'severity', 'acknowledged', 'objectid', 'r_eventid', 'suppressed'],
        selectHosts => ['hostid', 'host', 'name'],
        selectTags  => 'extend',
        source      => 0,    # trigger events
        value       => 1,    # problem events only
        sortfield   => ['eventid'],
        sortorder   => 'ASC',
        limit       => $Limit,
    };

    # Use eventid_from for pagination ASC (get events with ID greater than this)
    if ($LastEventID && $LastEventID > 0) {
        $EventParams->{eventid_from} = $LastEventID + 1;
    }

    my $EventRequest = {
        jsonrpc => '2.0',
        method  => 'event.get',
        params  => $EventParams,
        auth    => $AuthResult->{AuthToken},
        id      => 1,
    };

    # Send request
    my $Response = $Self->_SendRequest(
        URL     => $APIURL,
        Request => $EventRequest,
    );

    # Check if session expired and retry with fresh authentication
    if ( $Response->{Success} && $Response->{Data}->{error}
         && $Response->{Data}->{error}->{data}
         && $Response->{Data}->{error}->{data} =~ /Session terminated|re-login/i ) {

        $LogObject->Log(
            Priority => 'notice',
            Message  => 'ZabbixAPI::GetEvents - Session expired, re-authenticating',
        );

        # Clear cached auth token
        my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
        my $CacheKey = 'Auth::' . $APIUser . '::' . $APIURL;
        $CacheObject->Delete(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );

        # Re-authenticate
        $AuthResult = $Self->Authenticate(
            APIURL      => $APIURL,
            APIUser     => $APIUser,
            APIPassword => $APIPassword,
        );

        if ( !$AuthResult->{Success} ) {
            return {
                Success      => 0,
                ErrorMessage => 'Re-authentication failed after session expiry',
                Events       => [],
            };
        }

        # Update request with new auth token
        $EventRequest->{auth} = $AuthResult->{AuthToken};

        # Retry the request
        $Response = $Self->_SendRequest(
            URL     => $APIURL,
            Request => $EventRequest,
        );
    }

    if ( !$Response->{Success} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "ZabbixAPI::GetEvents - Request failed: " . ($Response->{ErrorMessage} || ''),
        );
        return {
            Success      => 0,
            ErrorMessage => $Response->{ErrorMessage},
            Events       => [],
        };
    }

    # Check for success in response
    if ( $Response->{Data}->{result} ) {
        my $Events = $Response->{Data}->{result};

        # Step 3: Collect unique host IDs and recovery event IDs
        my %HostIDs;
        my %RecoveryEventIDs;
        for my $Event (@$Events) {
            if ($Event->{hosts} && ref($Event->{hosts}) eq 'ARRAY') {
                for my $Host (@{$Event->{hosts}}) {
                    $HostIDs{$Host->{hostid}} = 1 if $Host->{hostid};
                }
            }
            if ($Event->{r_eventid} && $Event->{r_eventid} ne '0') {
                $RecoveryEventIDs{$Event->{r_eventid}} = 1;
            }
        }

        # Step 4: Get host details (groups + inventory + interfaces) for Location, System, Alias
        my %HostDetails;
        if (keys %HostIDs) {
            my $HostRequest = {
                jsonrpc => '2.0',
                method  => 'host.get',
                params  => {
                    output           => ['hostid', 'host', 'name'],
                    hostids          => [keys %HostIDs],
                    selectInterfaces => ['ip', 'main'],
                    selectGroups     => ['name'],
                    selectInventory  => ['name', 'type', 'model', 'vendor', 'location', 'alias', 'site_address_a', 'site_city'],
                },
                auth => $AuthResult->{AuthToken},
                id   => 2,
            };

            my $HostResponse = $Self->_SendRequest(
                URL     => $APIURL,
                Request => $HostRequest,
            );

            if ($HostResponse->{Success} && $HostResponse->{Data}->{result}) {
                for my $Host (@{$HostResponse->{Data}->{result}}) {
                    # Get main interface IP
                    my $MainIP = '';
                    if ($Host->{interfaces} && ref($Host->{interfaces}) eq 'ARRAY') {
                        for my $Interface (@{$Host->{interfaces}}) {
                            if ($Interface->{main} && $Interface->{main} eq '1') {
                                $MainIP = $Interface->{ip} || '';
                                last;
                            }
                        }
                        # Fallback to first interface if no main found
                        if (!$MainIP && @{$Host->{interfaces}}) {
                            $MainIP = $Host->{interfaces}[0]{ip} || '';
                        }
                    }

                    # Handle inventory - can be empty array [] or hash {}
                    my $Inventory = {};
                    if ($Host->{inventory} && ref($Host->{inventory}) eq 'HASH') {
                        $Inventory = $Host->{inventory};
                    }

                    $HostDetails{$Host->{hostid}} = {
                        groups     => $Host->{groups} || [],
                        inventory  => $Inventory,
                        interfaces => $Host->{interfaces} || [],
                        main_ip    => $MainIP,
                    };
                }
            }
        }

        # Step 5: Get recovery events for Last Occurrence timestamp
        my %RecoveryClocks;
        if (keys %RecoveryEventIDs) {
            my $RecoveryRequest = {
                jsonrpc => '2.0',
                method  => 'event.get',
                params  => {
                    output   => ['eventid', 'clock'],
                    eventids => [keys %RecoveryEventIDs],
                },
                auth => $AuthResult->{AuthToken},
                id   => 3,
            };

            my $RecoveryResponse = $Self->_SendRequest(
                URL     => $APIURL,
                Request => $RecoveryRequest,
            );

            if ($RecoveryResponse->{Success} && $RecoveryResponse->{Data}->{result}) {
                for my $RecEvent (@{$RecoveryResponse->{Data}->{result}}) {
                    $RecoveryClocks{$RecEvent->{eventid}} = $RecEvent->{clock};
                }
            }
        }

        # Step 6: Enrich events with host details and recovery clock
        for my $Event (@$Events) {
            # Add host groups, inventory, and IP
            if ($Event->{hosts} && ref($Event->{hosts}) eq 'ARRAY' && $Event->{hosts}[0]) {
                my $HostID = $Event->{hosts}[0]{hostid};
                if ($HostID && $HostDetails{$HostID}) {
                    $Event->{host_groups}    = $HostDetails{$HostID}{groups};
                    $Event->{host_inventory} = $HostDetails{$HostID}{inventory};
                    $Event->{host_interfaces} = $HostDetails{$HostID}{interfaces};
                    $Event->{host_main_ip}   = $HostDetails{$HostID}{main_ip};
                }
            }

            # Add recovery clock for Last Occurrence
            if ($Event->{r_eventid} && $Event->{r_eventid} ne '0' && $RecoveryClocks{$Event->{r_eventid}}) {
                $Event->{r_clock} = $RecoveryClocks{$Event->{r_eventid}};
            }
        }

        return {
            Success    => 1,
            Events     => $Events,
            TotalCount => $TotalCount,
        };
    }

    # Handle error response
    my $ErrorMessage = 'Failed to get events';
    if ( $Response->{Data}->{error} ) {
        $ErrorMessage = $Response->{Data}->{error}->{message} || 'Unknown error';
        if ( $Response->{Data}->{error}->{data} ) {
            $ErrorMessage .= ': ' . $Response->{Data}->{error}->{data};
        }
    }

    return {
        Success      => 0,
        ErrorMessage => $ErrorMessage,
        Events       => [],
    };
}

sub _LogAudit {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Prepare request/response data for storage
    my $RequestData = encode_json({
        EventID      => $Param{EventID} || '',
        TicketNumber => $Param{TicketNumber} || '',
    });

    my $ResponseData = encode_json({
        Success      => $Param{Success} || 0,
        ErrorMessage => $Param{ErrorMessage} || '',
    });

    # Insert audit log
    $DBObject->Do(
        SQL => 'INSERT INTO zabbix_audit_log 
                (ticket_id, action, request_data, response_data, success, error_message, create_time) 
                VALUES (?, ?, ?, ?, ?, ?, current_timestamp)',
        Bind => [
            \$Param{TicketID},
            \$Param{Action},
            \$RequestData,
            \$ResponseData,
            \($Param{Success} || 0),
            \($Param{ErrorMessage} || ''),
        ],
    );

    return 1;
}

1;