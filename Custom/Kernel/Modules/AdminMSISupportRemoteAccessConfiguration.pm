# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminMSISupportRemoteAccessConfiguration;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

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
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $ProxmoxObject = $Kernel::OM->Get('Kernel::System::Proxmox');
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    # Check permissions
    my $Access = 0;
    my $AdminGroups = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::AdminGroups') || ['admin', 'MSIAdmin', 'NOCAdmin'];
    
    for my $Group ( @{$AdminGroups} ) {
        my $HasPermission = $GroupObject->PermissionCheck(
            UserID    => $Self->{UserID},
            GroupName => $Group,
            Type      => 'rw',
        );
        if ($HasPermission) {
            $Access = 1;
            last;
        }
    }

    if ( !$Access ) {
        return $LayoutObject->ErrorScreen(
            Message => 'You don\'t have permission to access this page.',
        );
    }


    # Handle AJAX API test
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'TestAPI' ) {
        my $Result = $Self->_TestAPIConnection();

        my $JSON = $LayoutObject->JSONEncode(
            Data => $Result,
        );

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Handle AJAX get nodes
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'GetNodes' ) {
        my $Result = $Self->_GetNodes();

        my $JSON = $LayoutObject->JSONEncode(
            Data => $Result,
        );

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Handle AJAX get containers
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'GetContainers' ) {
        my $Result = $Self->_GetContainers();

        my $JSON = $LayoutObject->JSONEncode(
            Data => $Result,
        );

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Handle AJAX container control
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'ContainerControl' ) {
        my $Action = $ParamObject->GetParam( Param => 'ContainerAction' ) || '';
        
        my $Result = $Self->_ControlContainer(
            Action => $Action,
        );

        my $JSON = $LayoutObject->JSONEncode(
            Data => $Result,
        );

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # Handle AJAX status check
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'CheckStatus' ) {
        my $Result = $Self->_CheckContainerStatus();

        my $JSON = $LayoutObject->JSONEncode(
            Data => $Result,
        );

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }


    # Handle form submission
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'Save' ) {
        # Get form parameters - NO TOKEN FIELDS (those are in Config.pm)
        my %FormData = (
            ProxmoxHost       => $ParamObject->GetParam( Param => 'ProxmoxHost' ) || '',
            ProxmoxPort       => $ParamObject->GetParam( Param => 'ProxmoxPort' ) || '8006',
            ContainerNode     => $ParamObject->GetParam( Param => 'ContainerNode' ) || '',
            ContainerID       => $ParamObject->GetParam( Param => 'ContainerID' ) || '',
        );
        

        # Validate form data
        my %Errors;
        
        if ( !$FormData{ProxmoxHost} ) {
            $Errors{ProxmoxHostInvalid} = 'ServerError';
        }

        # Validate container configuration 
        if ( !$FormData{ContainerNode} ) {
            $Errors{ContainerNodeInvalid} = 'ServerError';
        }

        if ( !$FormData{ContainerID} ) {
            $Errors{ContainerIDInvalid} = 'ServerError';
        }

        if ( $FormData{ProxmoxPort} && $FormData{ProxmoxPort} !~ /^\d+$/ ) {
            $Errors{ProxmoxPortInvalid} = 'ServerError';
        }

        # Validate Bomgar URL if provided
        if ( $FormData{BomgarURL} && $FormData{BomgarURL} !~ /^https?:\/\/.+/ ) {
            $Errors{BomgarURLInvalid} = 'ServerError';
        }

        # If no errors, save configuration
        if ( !%Errors ) {
            my $Success = 1;
            
            $LogObject->Log(
                Priority => 'info',
                Message  => "MSI Support Remote Access Config: Starting save process for user $Self->{UserID}",
            );
            
            # Save ProxmoxHost, ProxmoxPort, ContainerNode and ContainerID to SysConfig
            my @ConfigSettings = (
                {
                    Name  => 'MSISupportRemoteAccessConfiguration::ProxmoxHost',
                    Value => $FormData{ProxmoxHost},
                },
                {
                    Name  => 'MSISupportRemoteAccessConfiguration::ProxmoxPort',
                    Value => $FormData{ProxmoxPort},
                },
                {
                    Name  => 'MSISupportRemoteAccessConfiguration::ContainerNode',
                    Value => $FormData{ContainerNode},
                },
                {
                    Name  => 'MSISupportRemoteAccessConfiguration::ContainerID',
                    Value => $FormData{ContainerID},
                },
            );
            
            for my $Setting (@ConfigSettings) {
                # Lock setting
                my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
                    Name   => $Setting->{Name},
                    Force  => 1,
                    UserID => $Self->{UserID},
                );

                if ( !$ExclusiveLockGUID ) {
                    $Success = 0;
                    $LogObject->Log(
                        Priority => 'error',
                        Message  => "MSI Support Remote Access Config: Failed to lock setting $Setting->{Name}",
                    );
                    last;
                }

                # Update setting
                my $UpdateSuccess = $SysConfigObject->SettingUpdate(
                    Name              => $Setting->{Name},
                    IsValid           => 1,
                    EffectiveValue    => $Setting->{Value},
                    ExclusiveLockGUID => $ExclusiveLockGUID,
                    UserID            => $Self->{UserID},
                );
                
                if ( !$UpdateSuccess ) {
                    $Success = 0;
                    $LogObject->Log(
                        Priority => 'error',
                        Message  => "MSI Support Remote Access Config: Failed to update setting $Setting->{Name}",
                    );
                    last;
                }
            }

            if ($Success) {
                # Deploy configuration
                my $DeploymentID = $SysConfigObject->ConfigurationDeploy(
                    Comments    => "MSI Support Remote Access configuration settings updated",
                    AllSettings => 1,
                    Force       => 1,
                    UserID      => $Self->{UserID},
                );

                if ($DeploymentID) {
                    # Log successful configuration
                    $LogObject->Log(
                        Priority => 'info',
                        Message  => "MSI Support Remote Access Config: Configuration saved successfully by user $Self->{UserID}",
                    );
                    
                    # Redirect to success page
                    return $LayoutObject->Redirect(
                        OP => "Action=$Self->{Action};Saved=1"
                    );
                }
            }

            # If we got here, something went wrong
            $Errors{SaveError} = 1;
        }

        # Show form again with errors
        return $Self->_ShowForm(
            %FormData,
            %Errors,
        );
    }

    # Default: show form
    return $Self->_ShowForm();
}

sub _ShowForm {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # Set default values from SysConfig - TOKEN-ONLY
    $Param{ProxmoxHost}       //= $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxHost') || '';
    $Param{ProxmoxPort}       //= $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxPort') || '8006';
    $Param{ProxmoxTokenID}    //= $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenID') || '';
    $Param{ProxmoxTokenSecret}//= $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenSecret') || '';
    $Param{ContainerNode}     //= $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ContainerNode') || '';
    $Param{ContainerID}       //= $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ContainerID') || '';
    
    # Check if critical Proxmox configuration is missing
    $Param{ConfigMissing} = 0;
    $Param{ConfigWarning} = '';
    
    my @Missing;
    if (!$Param{ProxmoxHost}) {
        push @Missing, 'MSISupportRemoteAccessConfiguration::ProxmoxHost';
    }
    if (!$Param{ProxmoxTokenID}) {
        push @Missing, 'MSISupportRemoteAccessConfiguration::ProxmoxTokenID';
    }
    if (!$Param{ProxmoxTokenSecret}) {
        push @Missing, 'MSISupportRemoteAccessConfiguration::ProxmoxTokenSecret';
    }
    
    if (@Missing) {
        $Param{ConfigMissing} = 1;
        $Param{MissingFields} = join(', ', @Missing);
    }

    # Check if saved
    if ( $ParamObject->GetParam( Param => 'Saved' ) ) {
        $Param{Saved} = 1;
    }

    # Get container status
    my $StatusResult = $Self->_CheckContainerStatus();
    $Param{ContainerStatus} = $StatusResult->{Status} || 'unknown';
    $Param{ContainerStatusClass} = $StatusResult->{StatusClass} || 'unknown';
    $Param{ContainerStatusMessage} = $StatusResult->{Message} || 'Status unknown';

    # Build output
    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();
    
    $LayoutObject->Block(
        Name => 'Overview',
        Data => \%Param,
    );

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminMSISupportRemoteAccessConfiguration',
        Data         => \%Param,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _TestAPIConnection {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ProxmoxObject = $Kernel::OM->Get('Kernel::System::Proxmox');
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    

    # Get API credentials from form or config
    # Get parameters safely without consuming them for subsequent calls
    my $FormHost = $ParamObject->GetParam( Param => 'ProxmoxHost' );
    my $FormPort = $ParamObject->GetParam( Param => 'ProxmoxPort' );
    my $FormTokenID = $ParamObject->GetParam( Param => 'ProxmoxTokenID' );
    my $FormTokenSecret = $ParamObject->GetParam( Param => 'ProxmoxTokenSecret' );
    
    # Log what we received from form
    $LogObject->Log(
        Priority => 'info',
        Message  => "MSI_SUPPORT_REMOTE_ACCESS_API_TEST: User $Self->{UserID} - Form params: Host=" . 
                   ($FormHost ? 'PROVIDED' : 'EMPTY') . 
                   ", TokenID=" . ($FormTokenID ? 'PROVIDED' : 'EMPTY') . 
                   ", TokenSecret=" . ($FormTokenSecret ? 'PROVIDED_' . length($FormTokenSecret) : 'EMPTY'),
    );
    
    # Use form parameters if available, otherwise fall back to config
    my $Host = (defined $FormHost && $FormHost ne '') ? $FormHost : 
               ($ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxHost') || '');
    my $Port = (defined $FormPort && $FormPort ne '') ? $FormPort :
               ($ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxPort') || '8006');
    my $TokenID = (defined $FormTokenID && $FormTokenID ne '') ? $FormTokenID :
                  ($ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenID') || '');
    my $TokenSecret = (defined $FormTokenSecret && $FormTokenSecret ne '') ? $FormTokenSecret :
                      ($ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenSecret') || '');

    # Test connection AND get all data in one call
    my $TestResult = $ProxmoxObject->TestConnection(
        Host        => $Host,
        Port        => $Port,
        TokenID     => $TokenID,
        TokenSecret => $TokenSecret,
        UserID      => $Self->{UserID},
        SSLVerify   => 0,
    );
    
    # If connection successful, also get nodes and containers
    if ($TestResult->{Success}) {
        # Get nodes
        my $NodesResult = $ProxmoxObject->GetNodes(
            Host        => $Host,
            Port        => $Port,
            TokenID     => $TokenID,
            TokenSecret => $TokenSecret,
            UserID      => $Self->{UserID},
            SSLVerify   => 0,
        );
        
        if ($NodesResult->{Success} && $NodesResult->{Nodes}) {
            $TestResult->{Nodes} = $NodesResult->{Nodes};
            
            # Get containers for each node
            my %AllContainers;
            for my $Node (@{$NodesResult->{Nodes}}) {
                if ($Node->{Status} eq 'online') {
                    my $ContainersResult = $ProxmoxObject->GetContainers(
                        Host        => $Host,
                        Port        => $Port,
                        TokenID     => $TokenID,
                        TokenSecret => $TokenSecret,
                        Node        => $Node->{Node},
                        UserID      => $Self->{UserID},
                        SSLVerify   => 0,
                    );
                    
                    if ($ContainersResult->{Success} && $ContainersResult->{Containers}) {
                        $AllContainers{$Node->{Node}} = $ContainersResult->{Containers};
                    }
                }
            }
            $TestResult->{Containers} = \%AllContainers;
        }
    }
    
    return $TestResult;
}

sub _GetNodes {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ProxmoxObject = $Kernel::OM->Get('Kernel::System::Proxmox');

    # Get API credentials from config
    my $Host = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxHost') || '';
    my $Port = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxPort') || '8006';
    my $TokenID = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenID') || '';
    my $TokenSecret = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenSecret') || '';

    return $ProxmoxObject->GetNodes(
        Host        => $Host,
        Port        => $Port,
        TokenID     => $TokenID,
        TokenSecret => $TokenSecret,
        UserID      => $Self->{UserID},
        SSLVerify   => 0,
    );
}

sub _GetContainers {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ProxmoxObject = $Kernel::OM->Get('Kernel::System::Proxmox');

    my $Node = $ParamObject->GetParam( Param => 'Node' ) || '';

    # Get API credentials from config
    my $Host = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxHost') || '';
    my $Port = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxPort') || '8006';
    my $TokenID = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenID') || '';
    my $TokenSecret = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenSecret') || '';

    return $ProxmoxObject->GetContainers(
        Host        => $Host,
        Port        => $Port,
        TokenID     => $TokenID,
        TokenSecret => $TokenSecret,
        Node        => $Node,
        UserID      => $Self->{UserID},
        SSLVerify   => 0,
    );
}

sub _ControlContainer {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ProxmoxObject = $Kernel::OM->Get('Kernel::System::Proxmox');

    my $Action = $Param{Action} || '';

    # Get configuration from database
    my $Host = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxHost');
    my $Port = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxPort') || '8006';
    my $TokenID = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenID');
    my $TokenSecret = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenSecret');
    my $ContainerNode = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ContainerNode');
    my $ContainerID = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ContainerID');

    if ( !$Host || !$TokenID || !$TokenSecret || !$ContainerNode || !$ContainerID ) {
        return {
            Success => 0,
            Message => "Missing Proxmox API configuration. Please configure all required settings first.",
        };
    }

    return $ProxmoxObject->ControlContainer(
        Host        => $Host,
        Port        => $Port,
        TokenID     => $TokenID,
        TokenSecret => $TokenSecret,
        Node        => $ContainerNode,
        ContainerID => $ContainerID,
        Action      => $Action,
        UserID      => $Self->{UserID},
        SSLVerify   => 0,
    );
}

sub _CheckContainerStatus {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ProxmoxObject = $Kernel::OM->Get('Kernel::System::Proxmox');

    # Get configuration from database
    my $Host = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxHost');
    my $Port = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxPort') || '8006';
    my $TokenID = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenID');
    my $TokenSecret = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ProxmoxTokenSecret');
    my $ContainerNode = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ContainerNode');
    my $ContainerID = $ConfigObject->Get('MSISupportRemoteAccessConfiguration::ContainerID');

    if ( !$Host || !$TokenID || !$TokenSecret || !$ContainerNode || !$ContainerID ) {
        return {
            Status => 'not_configured',
            StatusClass => 'warning',
            Message => "Proxmox API configuration incomplete",
        };
    }

    return $ProxmoxObject->GetContainerStatus(
        Host        => $Host,
        Port        => $Port,
        TokenID     => $TokenID,
        TokenSecret => $TokenSecret,
        Node        => $ContainerNode,
        ContainerID => $ContainerID,
        UserID      => $Self->{UserID},
        SSLVerify   => 0,
    );
}



1;