# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Proxmox;

use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use HTTP::Request;
use URI::Escape;
use Encode;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::Config',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub _ValidateInput {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my %ValidationRules = (
        Host => {
            Required => 1,
            Regex    => qr/^[a-zA-Z0-9._-]+$/,
            MaxLength => 253,
            Description => 'Hostname or IP address',
        },
        Port => {
            Required => 0,
            Regex    => qr/^\d+$/,
            Range    => [1, 65535],
            Description => 'Port number',
        },
        TokenID => {
            Required => 1,
            Regex    => qr/^[a-zA-Z0-9@._!-]+$/,
            MaxLength => 255,
            Description => 'Token ID (format: user@realm!tokenname)',
        },
        TokenSecret => {
            Required => 1,
            Regex    => qr/^[a-zA-Z0-9+\/=_-]+$/,
            MaxLength => 1024,
            Description => 'Token secret',
        },
        Node => {
            Required => 1,
            Regex    => qr/^[a-zA-Z0-9._-]+$/,
            MaxLength => 255,
            Description => 'Node name',
        },
        ContainerID => {
            Required => 1,
            Regex    => qr/^\d+$/,
            Range    => [100, 999999],
            Description => 'Container ID',
        },
        Action => {
            Required => 1,
            Enum     => ['start', 'stop'],
            Description => 'Container action',
        },
    );

    for my $Field ( keys %Param ) {
        # DEBUG: Log each field being processed (reduced to debug level)
        $LogObject->Log(
            Priority => 'debug',
            Message  => "DEBUG _ValidateInput processing field: $Field = " . 
                       (defined $Param{$Field} ? 
                           ($Param{$Field} eq '' ? 'DEFINED_BUT_EMPTY' : 'HAS_VALUE_' . length($Param{$Field})) : 
                           'UNDEFINED'),
        );
        
        next if !defined $Param{$Field};
        next if !$ValidationRules{$Field};
        
        my $Value = $Param{$Field};
        my $Rules = $ValidationRules{$Field};
        
        # Required validation
        if ( $Rules->{Required} && (!defined $Value || $Value eq '') ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Proxmox::_ValidateInput: Missing required field $Field",
            );
            return {
                Success => 0,
                Field   => $Field,
                Message => "Missing required field: $Rules->{Description}",
            };
        }
        
        next if !defined $Value || $Value eq '';
        
        # Length validation
        if ( $Rules->{MaxLength} && length($Value) > $Rules->{MaxLength} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Proxmox::_ValidateInput: Field $Field exceeds maximum length",
            );
            return {
                Success => 0,
                Field   => $Field,
                Message => "$Rules->{Description} exceeds maximum length ($Rules->{MaxLength})",
            };
        }
        
        # Regex validation
        if ( $Rules->{Regex} && $Value !~ $Rules->{Regex} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Proxmox::_ValidateInput: Field $Field contains invalid characters",
            );
            return {
                Success => 0,
                Field   => $Field,
                Message => "Invalid format for $Rules->{Description}",
            };
        }
        
        # Range validation
        if ( $Rules->{Range} && ($Value < $Rules->{Range}[0] || $Value > $Rules->{Range}[1]) ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Proxmox::_ValidateInput: Field $Field out of valid range",
            );
            return {
                Success => 0,
                Field   => $Field,
                Message => "$Rules->{Description} must be between $Rules->{Range}[0] and $Rules->{Range}[1]",
            };
        }
        
        # Enum validation
        if ( $Rules->{Enum} && !grep { $_ eq $Value } @{$Rules->{Enum}} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Proxmox::_ValidateInput: Field $Field has invalid value",
            );
            return {
                Success => 0,
                Field   => $Field,
                Message => "Invalid value for $Rules->{Description}",
            };
        }
    }
    
    return { Success => 1 };
}

sub _SanitizeURL {
    my ( $Self, %Param ) = @_;
    
    my $Host = $Param{Host} || '';
    my $Port = $Param{Port} || '8006';
    my $Path = $Param{Path} || '';
    
    # Remove any protocol prefix if accidentally included
    $Host =~ s/^https?:\/\///;
    
    # URL encode path components
    my @PathParts = split /\//, $Path;
    @PathParts = map { uri_escape_utf8($_) } @PathParts;
    my $SafePath = join '/', @PathParts;
    
    return "https://$Host:$Port$SafePath";
}

sub _LogAuditEvent {
    my ( $Self, %Param ) = @_;
    
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    my $Event = $Param{Event} || 'Unknown';
    my $UserID = $Param{UserID} || 0;
    my $Success = $Param{Success} ? 'SUCCESS' : 'FAILED';
    my $Details = $Param{Details} || '';
    my $Host = $Param{Host} || 'unknown';
    my $Node = $Param{Node} || '';
    my $ContainerID = $Param{ContainerID} || '';
    
    my $Message = "MSI_SUPPORT_REMOTE_ACCESS_AUDIT: Event=$Event, User=$UserID, Status=$Success, Host=$Host";
    
    if ( $Node ) {
        $Message .= ", Node=$Node";
    }
    
    if ( $ContainerID ) {
        $Message .= ", Container=$ContainerID";
    }
    
    if ( $Details ) {
        # Sanitize details to prevent log injection
        $Details =~ s/[\r\n]/ /g;
        $Details = substr($Details, 0, 500); # Limit length
        $Message .= ", Details=$Details";
    }
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => $Message,
    );
}

sub TestConnection {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # DEBUG: Log what we received (reduced to debug level)
    $LogObject->Log(
        Priority => 'debug',
        Message  => "DEBUG TestConnection params: Host=" . ($Param{Host} || 'UNDEF') . 
                   ", TokenID=" . ($Param{TokenID} || 'UNDEF') . 
                   ", TokenSecret=" . (defined $Param{TokenSecret} ? 
                       ($Param{TokenSecret} eq '' ? 'DEFINED_BUT_EMPTY' : 'HAS_VALUE_' . length($Param{TokenSecret})) : 
                       'UNDEFINED'),
    );

    # Validate and sanitize input
    my $ValidationResult = $Self->_ValidateInput(
        Host        => $Param{Host},
        Port        => $Param{Port},
        TokenID     => $Param{TokenID},
        TokenSecret => $Param{TokenSecret},
    );
    
    if ( !$ValidationResult->{Success} ) {
        $Self->_LogAuditEvent(
            Event   => 'API_TEST_CONNECTION',
            UserID  => $Param{UserID} || 0,
            Success => 0,
            Details => "Validation failed: $ValidationResult->{Message}",
            Host    => $Param{Host} || 'invalid',
        );
        return $ValidationResult;
    }

    my $Port = $Param{Port} || '8006';
    my $SSLVerify = $Param{SSLVerify} // 0;

    # Create user agent
    my $UA = LWP::UserAgent->new(
        timeout => 10,
        ssl_opts => { 
            verify_hostname => $SSLVerify, 
            SSL_verify_mode => $SSLVerify ? 1 : 0 
        },
    );

    # Test connection with version endpoint
    my $AuthToken = "PVEAPIToken=$Param{TokenID}=$Param{TokenSecret}";
    my $TestURL = $Self->_SanitizeURL(
        Host => $Param{Host},
        Port => $Port,
        Path => '/api2/extjs/version',
    );
    
    my $Request = HTTP::Request->new('GET', $TestURL);
    $Request->header('Authorization', $AuthToken);
    $Request->header('User-Agent', 'ZNUNY-MSISupportRemoteAccessIntegration/1.0');

    my $Response = $UA->request($Request);

    if ( !$Response->is_success ) {
        $Self->_LogAuditEvent(
            Event   => 'API_TEST_CONNECTION',
            UserID  => $Param{UserID} || 0,
            Success => 0,
            Details => "Connection failed: " . $Response->status_line,
            Host    => $Param{Host},
        );
        return {
            Success => 0,
            Message => "Connection failed: " . $Response->status_line,
        };
    }

    my $Data;
    eval {
        $Data = decode_json($Response->decoded_content);
    };
    
    if ( $@ || !$Data->{data} ) {
        $Self->_LogAuditEvent(
            Event   => 'API_TEST_CONNECTION',
            UserID  => $Param{UserID} || 0,
            Success => 0,
            Details => "Failed to parse API response",
            Host    => $Param{Host},
        );
        return {
            Success => 0,
            Message => "Failed to parse response from Proxmox API",
        };
    }

    $Self->_LogAuditEvent(
        Event   => 'API_TEST_CONNECTION',
        UserID  => $Param{UserID} || 0,
        Success => 1,
        Details => "Connection test successful, version: " . ($Data->{data}->{version} || 'Unknown'),
        Host    => $Param{Host},
    );

    return {
        Success => 1,
        Message => "Connection successful",
        Version => $Data->{data}->{version} || 'Unknown',
    };
}

sub GetNodes {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Validate and sanitize input
    my $ValidationResult = $Self->_ValidateInput(
        Host        => $Param{Host},
        Port        => $Param{Port},
        TokenID     => $Param{TokenID},
        TokenSecret => $Param{TokenSecret},
    );
    
    if ( !$ValidationResult->{Success} ) {
        $Self->_LogAuditEvent(
            Event   => 'API_GET_NODES',
            UserID  => $Param{UserID} || 0,
            Success => 0,
            Details => "Validation failed: $ValidationResult->{Message}",
            Host    => $Param{Host} || 'invalid',
        );
        return $ValidationResult;
    }

    my $Port = $Param{Port} || '8006';
    my $SSLVerify = $Param{SSLVerify} // 0;

    # Create user agent
    my $UA = LWP::UserAgent->new(
        timeout => 15,
        ssl_opts => { 
            verify_hostname => $SSLVerify, 
            SSL_verify_mode => $SSLVerify ? 1 : 0 
        },
    );

    my $AuthToken = "PVEAPIToken=$Param{TokenID}=$Param{TokenSecret}";
    my $NodesURL = $Self->_SanitizeURL(
        Host => $Param{Host},
        Port => $Port,
        Path => '/api2/extjs/nodes',
    );
    
    my $Request = HTTP::Request->new('GET', $NodesURL);
    $Request->header('Authorization', $AuthToken);
    $Request->header('User-Agent', 'ZNUNY-MSISupportRemoteAccessIntegration/1.0');

    my $Response = $UA->request($Request);

    if ( !$Response->is_success ) {
        $Self->_LogAuditEvent(
            Event   => 'API_GET_NODES',
            UserID  => $Param{UserID} || 0,
            Success => 0,
            Details => "Failed to get nodes: " . $Response->status_line,
            Host    => $Param{Host},
        );
        return {
            Success => 0,
            Message => "Failed to get nodes: " . $Response->status_line,
        };
    }

    my $Data;
    eval {
        $Data = decode_json($Response->decoded_content);
    };
    
    if ( $@ || !$Data->{data} ) {
        $Self->_LogAuditEvent(
            Event   => 'API_GET_NODES',
            UserID  => $Param{UserID} || 0,
            Success => 0,
            Details => "Failed to parse nodes response",
            Host    => $Param{Host},
        );
        return {
            Success => 0,
            Message => "Failed to parse nodes response",
        };
    }

    my @Nodes;
    for my $Node ( @{ $Data->{data} } ) {
        # Validate node data
        next if !$Node->{node};
        next if $Node->{node} !~ /^[a-zA-Z0-9._-]+$/;
        
        push @Nodes, {
            Node   => $Node->{node},
            Status => $Node->{status} || 'unknown',
            Type   => $Node->{type} || 'unknown',
        };
    }

    $Self->_LogAuditEvent(
        Event   => 'API_GET_NODES',
        UserID  => $Param{UserID} || 0,
        Success => 1,
        Details => "Retrieved " . scalar(@Nodes) . " nodes",
        Host    => $Param{Host},
    );

    return {
        Success => 1,
        Nodes   => \@Nodes,
    };
}

sub GetContainers {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Validate and sanitize input
    my $ValidationResult = $Self->_ValidateInput(
        Host        => $Param{Host},
        Port        => $Param{Port},
        TokenID     => $Param{TokenID},
        TokenSecret => $Param{TokenSecret},
        Node        => $Param{Node},
    );
    
    if ( !$ValidationResult->{Success} ) {
        $Self->_LogAuditEvent(
            Event   => 'API_GET_CONTAINERS',
            UserID  => $Param{UserID} || 0,
            Success => 0,
            Details => "Validation failed: $ValidationResult->{Message}",
            Host    => $Param{Host} || 'invalid',
            Node    => $Param{Node} || 'invalid',
        );
        return $ValidationResult;
    }

    my $Port = $Param{Port} || '8006';
    my $SSLVerify = $Param{SSLVerify} // 0;

    # Create user agent
    my $UA = LWP::UserAgent->new(
        timeout => 15,
        ssl_opts => { 
            verify_hostname => $SSLVerify, 
            SSL_verify_mode => $SSLVerify ? 1 : 0 
        },
    );

    my $AuthToken = "PVEAPIToken=$Param{TokenID}=$Param{TokenSecret}";
    
    # Fetch both LXC containers and QEMU VMs
    my @AllContainers;
    
    # 1. Get LXC containers
    my $LXCContainersURL = $Self->_SanitizeURL(
        Host => $Param{Host},
        Port => $Port,
        Path => "/api2/extjs/nodes/$Param{Node}/lxc",
    );
    
    my $LXCRequest = HTTP::Request->new('GET', $LXCContainersURL);
    $LXCRequest->header('Authorization', $AuthToken);
    $LXCRequest->header('User-Agent', 'ZNUNY-MSISupportRemoteAccessIntegration/1.0');

    my $LXCResponse = $UA->request($LXCRequest);

    if ( $LXCResponse->is_success ) {
        my $LXCData;
        eval {
            $LXCData = decode_json($LXCResponse->decoded_content);
        };
        
        if ( !$@ && $LXCData->{data} ) {
            for my $Container ( @{ $LXCData->{data} } ) {
                $Container->{type} = 'lxc';
                push @AllContainers, $Container;
            }
        }
    }
    
    # 2. Get QEMU VMs
    my $QEMUVMsURL = $Self->_SanitizeURL(
        Host => $Param{Host},
        Port => $Port,
        Path => "/api2/extjs/nodes/$Param{Node}/qemu",
    );
    
    my $QEMURequest = HTTP::Request->new('GET', $QEMUVMsURL);
    $QEMURequest->header('Authorization', $AuthToken);
    $QEMURequest->header('User-Agent', 'ZNUNY-MSISupportRemoteAccessIntegration/1.0');

    my $QEMUResponse = $UA->request($QEMURequest);

    if ( $QEMUResponse->is_success ) {
        my $QEMUData;
        eval {
            $QEMUData = decode_json($QEMUResponse->decoded_content);
        };
        
        if ( !$@ && $QEMUData->{data} ) {
            for my $VM ( @{ $QEMUData->{data} } ) {
                $VM->{type} = 'qemu';
                push @AllContainers, $VM;
            }
        }
    }
    
    # Check if we got any containers/VMs
    if ( !@AllContainers ) {
        $Self->_LogAuditEvent(
            Event   => 'API_GET_CONTAINERS',
            UserID  => $Param{UserID} || 0,
            Success => 0,
            Details => "No containers or VMs found on node",
            Host    => $Param{Host},
            Node    => $Param{Node},
        );
        return {
            Success => 0,
            Message => "No containers or VMs found on node $Param{Node}",
        };
    }

    my @Containers;
    for my $Container ( @AllContainers ) {
        # Validate container data
        next if !$Container->{vmid};
        next if $Container->{vmid} !~ /^\d+$/;
        
        # Check if this might be an MSI Support Remote Access container
        my $Name = $Container->{name} || '';
        # Sanitize name to prevent any potential issues
        $Name =~ s/[<>&"']//g;
        $Name = substr($Name, 0, 255);
        
        my $IsBomgar = 0;
        if ( $Name =~ /(bomgar|beyond|trust|remote|support)/i ) {
            $IsBomgar = 1;
        }
        
        push @Containers, {
            VMID     => $Container->{vmid},
            Name     => $Name,
            Status   => $Container->{status} || 'unknown',
            CPU      => $Container->{cpu} || 0,
            MaxMem   => $Container->{maxmem} || 0,
            IsBomgar => $IsBomgar,
            Type     => $Container->{type} || 'lxc',  # 'lxc' or 'qemu'
        };
    }

    # Sort containers with potential MSI Support Remote Access containers first
    @Containers = sort { 
        $b->{IsBomgar} <=> $a->{IsBomgar} || 
        $a->{VMID} <=> $b->{VMID} 
    } @Containers;

    my $MSISupportRemoteAccessCount = grep { $_->{IsBomgar} } @Containers;
    
    $Self->_LogAuditEvent(
        Event   => 'API_GET_CONTAINERS',
        UserID  => $Param{UserID} || 0,
        Success => 1,
        Details => "Retrieved " . scalar(@Containers) . " containers (" . $MSISupportRemoteAccessCount . " potential MSI Support Remote Access)",
        Host    => $Param{Host},
        Node    => $Param{Node},
    );

    return {
        Success    => 1,
        Containers => \@Containers,
    };
}

sub GetContainerStatus {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Validate required parameters
    for my $Required (qw(Host TokenID TokenSecret Node ContainerID)) {
        if ( !$Param{$Required} ) {
            return {
                Success => 0,
                Message => "Missing required parameter: $Required",
            };
        }
    }

    my $Port = $Param{Port} || '8006';
    my $SSLVerify = $Param{SSLVerify} // 0;

    # Create user agent
    my $UA = LWP::UserAgent->new(
        timeout => 10,
        ssl_opts => { 
            verify_hostname => $SSLVerify, 
            SSL_verify_mode => $SSLVerify ? 1 : 0 
        },
    );

    my $AuthToken = "PVEAPIToken=$Param{TokenID}=$Param{TokenSecret}";

    # First, get the list of containers/VMs to determine the type
    my $ContainersResult = $Self->GetContainers(
        Host        => $Param{Host},
        Port        => $Param{Port},
        TokenID     => $Param{TokenID},
        TokenSecret => $Param{TokenSecret},
        Node        => $Param{Node},
        UserID      => $Param{UserID} || 0,
        SSLVerify   => $Param{SSLVerify} // 0,
    );

    if ( !$ContainersResult->{Success} ) {
        return {
            Success => 0,
            Status  => 'query_error',
            Message => "Failed to get containers list: " . $ContainersResult->{Message},
        };
    }

    # Find the container/VM with the matching ID
    my $ContainerType;
    my $ContainerData;
    for my $Container ( @{ $ContainersResult->{Containers} } ) {
        if ( $Container->{VMID} == $Param{ContainerID} ) {
            $ContainerType = $Container->{Type};  # 'qemu' or 'lxc'
            $ContainerData = $Container;
            last;
        }
    }

    if ( !$ContainerType ) {
        return {
            Success => 0,
            Status  => 'not_found',
            Message => "Container/VM with ID $Param{ContainerID} not found on node $Param{Node}",
        };
    }

    # Now use the correct API endpoint based on the actual type
    my $StatusURL = $Self->_SanitizeURL(
        Host => $Param{Host},
        Port => $Port,
        Path => "/api2/extjs/nodes/$Param{Node}/$ContainerType/$Param{ContainerID}/status/current",
    );

    my $Request = HTTP::Request->new('GET', $StatusURL);
    $Request->header('Authorization', $AuthToken);
    my $Response = $UA->request($Request);

    if ( !$Response->is_success ) {
        return {
            Success => 0,
            Status  => 'api_error',
            Message => "Failed to get status: " . $Response->status_line,
        };
    }

    my $Data;
    my $RawResponse = $Response->decoded_content;

    # DEBUG: Log the raw response for troubleshooting
    $LogObject->Log(
        Priority => 'error',
        Message  => "DEBUG GetContainerStatus raw response: " . substr($RawResponse, 0, 500),
    );

    eval {
        $Data = decode_json($RawResponse);
    };

    if ( $@ ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "DEBUG GetContainerStatus JSON decode error: $@",
        );
        return {
            Success => 0,
            Status  => 'parse_error',
            Message => "Failed to parse JSON response: $@",
        };
    }

    if ( !$Data->{data} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "DEBUG GetContainerStatus missing data field. Full response: " . $RawResponse,
        );

        # Check if it's an API error response
        if ( exists $Data->{success} && $Data->{success} == 0 ) {
            return {
                Success => 0,
                Status  => 'api_error',
                Message => $Data->{message} || "Proxmox API returned error",
            };
        }

        # Return the raw Proxmox response for debugging
        return {
            Success => 0,
            Status  => 'parse_error',
            Message => "Unexpected API response format: " . $RawResponse,
        };
    }

    my $Status = $Data->{data}->{status} || 'unknown';
    my $StatusClass = 'unknown';
    
    if ( $Status eq 'running' ) {
        $StatusClass = 'success';
    } elsif ( $Status eq 'stopped' ) {
        $StatusClass = 'error';
    }

    my $ResourceType = $ContainerType eq 'qemu' ? 'VM' : 'Container';
    
    return {
        Success     => 1,
        Status      => $Status,
        StatusClass => $StatusClass,
        Message     => "$ResourceType is $Status",
        Data        => $Data->{data},
        Type        => $ContainerType,
    };
}

sub ControlContainer {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Validate and sanitize input
    my $ValidationResult = $Self->_ValidateInput(
        Host        => $Param{Host},
        Port        => $Param{Port},
        TokenID     => $Param{TokenID},
        TokenSecret => $Param{TokenSecret},
        Node        => $Param{Node},
        ContainerID => $Param{ContainerID},
        Action      => $Param{Action},
    );
    
    if ( !$ValidationResult->{Success} ) {
        $Self->_LogAuditEvent(
            Event       => 'CONTAINER_CONTROL',
            UserID      => $Param{UserID} || 0,
            Success     => 0,
            Details     => "Validation failed: $ValidationResult->{Message}",
            Host        => $Param{Host} || 'invalid',
            Node        => $Param{Node} || 'invalid',
            ContainerID => $Param{ContainerID} || 'invalid',
        );
        return $ValidationResult;
    }

    my $Port = $Param{Port} || '8006';
    my $SSLVerify = $Param{SSLVerify} // 0;

    # Create user agent
    my $UA = LWP::UserAgent->new(
        timeout => 30,
        ssl_opts => { 
            verify_hostname => $SSLVerify, 
            SSL_verify_mode => $SSLVerify ? 1 : 0 
        },
    );

    my $AuthToken = "PVEAPIToken=$Param{TokenID}=$Param{TokenSecret}";

    # First, get the list of containers/VMs to determine the type
    my $ContainersResult = $Self->GetContainers(
        Host        => $Param{Host},
        Port        => $Param{Port},
        TokenID     => $Param{TokenID},
        TokenSecret => $Param{TokenSecret},
        Node        => $Param{Node},
        UserID      => $Param{UserID} || 0,
        SSLVerify   => $Param{SSLVerify} // 0,
    );

    if ( !$ContainersResult->{Success} ) {
        return {
            Success => 0,
            Message => "Failed to get containers list: " . $ContainersResult->{Message},
        };
    }

    # Find the container/VM with the matching ID
    my $ContainerType;
    my $ContainerData;
    for my $Container ( @{ $ContainersResult->{Containers} } ) {
        if ( $Container->{VMID} == $Param{ContainerID} ) {
            $ContainerType = $Container->{Type};  # 'qemu' or 'lxc'
            $ContainerData = $Container;
            last;
        }
    }

    if ( !$ContainerType ) {
        $Self->_LogAuditEvent(
            Event       => 'CONTAINER_CONTROL',
            UserID      => $Param{UserID} || 0,
            Success     => 0,
            Details     => "Container/VM with ID $Param{ContainerID} not found on node $Param{Node}",
            Host        => $Param{Host},
            Node        => $Param{Node},
            ContainerID => $Param{ContainerID},
        );
        return {
            Success => 0,
            Message => "Container/VM with ID $Param{ContainerID} not found on node $Param{Node}",
        };
    }

    # Now use the correct API endpoint based on the actual type
    my $ActionURL = $Self->_SanitizeURL(
        Host => $Param{Host},
        Port => $Port,
        Path => "/api2/extjs/nodes/$Param{Node}/$ContainerType/$Param{ContainerID}/status/$Param{Action}",
    );

    my $Request = HTTP::Request->new('POST', $ActionURL);
    $Request->header('Authorization', $AuthToken);
    $Request->header('User-Agent', 'ZNUNY-MSISupportRemoteAccessIntegration/1.0');
    my $Response = $UA->request($Request);

    if ( !$Response->is_success ) {
        $Self->_LogAuditEvent(
            Event       => 'CONTAINER_CONTROL',
            UserID      => $Param{UserID} || 0,
            Success     => 0,
            Details     => "Failed to $Param{Action} container/VM: " . $Response->status_line,
            Host        => $Param{Host},
            Node        => $Param{Node},
            ContainerID => $Param{ContainerID},
        );
        return {
            Success => 0,
            Message => "Failed to $Param{Action} container/VM: " . $Response->status_line,
        };
    }
    
    my $ResourceType = $ContainerType eq 'qemu' ? 'VM' : 'Container';
    
    $Self->_LogAuditEvent(
        Event       => 'CONTAINER_CONTROL',
        UserID      => $Param{UserID} || 0,
        Success     => 1,
        Details     => "Successfully ${Param{Action}}ed $ResourceType",
        Host        => $Param{Host},
        Node        => $Param{Node},
        ContainerID => $Param{ContainerID},
    );

    return {
        Success => 1,
        Message => "$ResourceType ${Param{Action}}ed successfully",
    };
}

1;