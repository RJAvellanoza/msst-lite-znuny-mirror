# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminEBondingConfiguration;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

# Hardcoded ServiceNow environment credentials
our %EnvironmentCredentials = (
    reference => {
        APIURL      => 'https://cmsosnowref.service-now.com/api/now/table/u_inbound_incident',
        APIUser     => 'lsmp.integration.ref',
        APIPassword => 'LyYbK+qo<9<M7Cbyup8nQ.9l<1wWg>E9!z!)w}eI',
    },
    production => {
        APIURL      => 'https://cmsosnow.service-now.com/api/now/table/u_inbound_incident',
        APIUser     => 'lsmp.integration.prod',
        APIPassword => 'G-xig68QsC,ZE<a4P_w4Q+I.kCV]B[=<<bT1fHQr',
    },
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
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check permissions
    my $Access = 0;
    my $AdminGroups = $ConfigObject->Get('EBondingIntegration::AdminGroups') || ['admin', 'MSIAdmin', 'NOCAdmin'];

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

    # Handle AJAX test connection
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'TestConnection' ) {
        my $Result = $Self->_TestConnection();

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

    # Handle AJAX load API logs
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'LoadAPILogs' ) {
        my $Filter = $ParamObject->GetParam( Param => 'Filter' ) || 'all';
        my $Result = $Self->_LoadAPILogs(
            Filter => $Filter,
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

    # Handle AJAX get log details
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'GetLogDetails' ) {
        my $LogID = $ParamObject->GetParam( Param => 'LogID' );
        my $Result = $Self->_GetLogDetails(
            LogID => $LogID,
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

    # Handle form submission
    if ( $Self->{Subaction} && $Self->{Subaction} eq 'Save' ) {
        # Save Enabled flag and Environment selection
        my $Enabled     = $ParamObject->GetParam( Param => 'Enabled' ) || 0;
        my $Environment = $ParamObject->GetParam( Param => 'Environment' ) || 'reference';

        $LogObject->Log(
            Priority => 'notice',
            Message  => "Easy MSI Escalation Config: RAW Environment param = '$Environment'",
        );

        # Validate environment value
        if ( $Environment !~ /^(reference|production)$/ ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Easy MSI Escalation Config: Invalid environment '$Environment', defaulting to reference",
            );
            $Environment = 'reference';
        }

        my $Success = 1;

        $LogObject->Log(
            Priority => 'notice',
            Message  => "Easy MSI Escalation Config: Starting save process for user $Self->{UserID} (Environment: $Environment, Enabled: $Enabled)",
        );

        # Save Enabled setting
        my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
            Name   => 'EBondingIntegration::Enabled',
            Force  => 1,
            UserID => $Self->{UserID},
        );

        if ( !$ExclusiveLockGUID ) {
            $Success = 0;
            $LogObject->Log(
                Priority => 'error',
                Message  => "Easy MSI Escalation Config: Failed to lock setting EBondingIntegration::Enabled",
            );
        }

        if ($Success) {
            my $UpdateSuccess = $SysConfigObject->SettingUpdate(
                Name              => 'EBondingIntegration::Enabled',
                IsValid           => 1,
                EffectiveValue    => $Enabled,
                ExclusiveLockGUID => $ExclusiveLockGUID,
                UserID            => $Self->{UserID},
            );

            if ( !$UpdateSuccess ) {
                $Success = 0;
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Easy MSI Escalation Config: Failed to update setting EBondingIntegration::Enabled",
                );
            }
        }

        # Save Environment setting
        if ($Success) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Easy MSI Escalation Config: Attempting to save Environment = '$Environment'",
            );

            my $EnvLockGUID = $SysConfigObject->SettingLock(
                Name   => 'EBondingIntegration::Environment',
                Force  => 1,
                UserID => $Self->{UserID},
            );

            $LogObject->Log(
                Priority => 'notice',
                Message  => "Easy MSI Escalation Config: EnvLockGUID = " . ($EnvLockGUID || 'UNDEF'),
            );

            if ($EnvLockGUID) {
                my $EnvUpdateSuccess = $SysConfigObject->SettingUpdate(
                    Name              => 'EBondingIntegration::Environment',
                    IsValid           => 1,
                    EffectiveValue    => $Environment,
                    ExclusiveLockGUID => $EnvLockGUID,
                    UserID            => $Self->{UserID},
                );

                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "Easy MSI Escalation Config: EnvUpdateSuccess = " . ($EnvUpdateSuccess ? 'YES' : 'NO'),
                );

                if ( !$EnvUpdateSuccess ) {
                    $Success = 0;
                    $LogObject->Log(
                        Priority => 'error',
                        Message  => "Easy MSI Escalation Config: Failed to update setting EBondingIntegration::Environment",
                    );
                }
            }
            else {
                $Success = 0;
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Easy MSI Escalation Config: Failed to lock setting EBondingIntegration::Environment",
                );
            }
        }

        if ($Success) {
            # Deploy configuration
            my $DeploymentID = $SysConfigObject->ConfigurationDeploy(
                Comments    => "Easy MSI Escalation configuration updated",
                AllSettings => 1,
                Force       => 1,
                UserID      => $Self->{UserID},
            );

            if ($DeploymentID) {
                # Log successful configuration
                $LogObject->Log(
                    Priority => 'info',
                    Message  => "Easy MSI Escalation Config: Configuration saved successfully by user $Self->{UserID}",
                );

                # Redirect to success page
                return $LayoutObject->Redirect(
                    OP => "Action=$Self->{Action};Saved=1"
                );
            } else {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Easy MSI Escalation Config: Failed to deploy configuration",
                );
            }
        }

        # If we got here, something went wrong
        return $Self->_ShowForm(
            SaveError => 1,
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

    # Get current environment from SysConfig (default to reference)
    my $Environment = $ConfigObject->Get('EBondingIntegration::Environment') || 'reference';
    $Param{Environment} = $Environment;

    # Get credentials from hardcoded environment settings
    my $EnvCreds = $EnvironmentCredentials{$Environment} || $EnvironmentCredentials{reference};
    $Param{APIURL}      = $EnvCreds->{APIURL} || '';
    $Param{APIUser}     = $EnvCreds->{APIUser} || '';
    $Param{APIPassword} = $EnvCreds->{APIPassword} || '';

    # Build environment dropdown options
    $Param{EnvironmentStrg} = $LayoutObject->BuildSelection(
        Data => {
            reference  => 'Reference',
            production => 'Production',
        },
        Name        => 'Environment',
        SelectedID  => $Environment,
        Class       => 'Modernize',
        Translation => 1,
        Sort        => 'AlphanumericKey',
    );

    # Load enabled status from SysConfig (editable)
    $Param{Enabled}     = $ConfigObject->Get('EBondingIntegration::Enabled') || 0;

    # Credentials are always configured (hardcoded)
    $Param{ConfigMissing} = 0;
    $Param{ConfigWarning} = '';

    # Check if saved
    if ( $ParamObject->GetParam( Param => 'Saved' ) ) {
        $Param{Saved} = 1;
    }

    # Build output
    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();

    $LayoutObject->Block(
        Name => 'Overview',
        Data => \%Param,
    );

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminEBondingConfiguration',
        Data         => \%Param,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _TestConnection {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Get current environment and credentials
    my $Environment = $ConfigObject->Get('EBondingIntegration::Environment') || 'reference';
    my $EnvCreds = $EnvironmentCredentials{$Environment} || $EnvironmentCredentials{reference};

    my $APIURL      = $EnvCreds->{APIURL} || '';
    my $APIUser     = $EnvCreds->{APIUser} || '';
    my $APIPassword = $EnvCreds->{APIPassword} || '';

    # Validate credentials are configured
    if (!$APIURL || !$APIUser || !$APIPassword) {
        return {
            Success => 0,
            Message => "ServiceNow credentials not configured for environment: $Environment",
        };
    }

    # Test ServiceNow API connection
    eval {
        require HTTP::Request;
        require LWP::UserAgent;
        require MIME::Base64;
    };

    if ($@) {
        return {
            Success => 0,
            Message => 'Required Perl modules not available (HTTP::Request, LWP::UserAgent)',
        };
    }

    # Create basic auth header
    my $AuthString = MIME::Base64::encode_base64("$APIUser:$APIPassword", '');

    # Create user agent
    my $UserAgent = LWP::UserAgent->new(
        timeout => 10,
        ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 },
    );

    # Create request (GET with limit=1 to minimize data)
    my $Request = HTTP::Request->new(
        GET => "$APIURL?sysparm_limit=1"
    );
    $Request->header(
        'Authorization' => "Basic $AuthString",
        'Accept' => 'application/json',
    );

    # Send request
    my $Response = $UserAgent->request($Request);

    if ($Response->is_success) {
        $LogObject->Log(
            Priority => 'info',
            Message  => "Easy MSI Escalation Config: Connection test successful by user $Self->{UserID}",
        );

        return {
            Success => 1,
            Message => 'Connection successful! ServiceNow API is reachable.',
        };
    } else {
        my $ErrorMsg = $Response->status_line || 'Unknown error';

        $LogObject->Log(
            Priority => 'error',
            Message  => "Easy MSI Escalation Config: Connection test failed - $ErrorMsg",
        );

        return {
            Success => 0,
            Message => "Connection failed: $ErrorMsg",
        };
    }
}

sub _LoadAPILogs {
    my ( $Self, %Param ) = @_;

    my $DBObject   = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject  = $Kernel::OM->Get('Kernel::System::Log');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    my $Filter = $Param{Filter} || 'all';

    # Build SQL query with time filter
    my $SQL = 'SELECT id, create_time, incident_number, action, success, msi_ticket_number, '
            . 'error_message, response_status_code, request_payload, response_payload '
            . 'FROM ebonding_api_log WHERE 1=1 ';

    my @Binds;

    # Apply time filter
    if ( $Filter eq '24h' ) {
        $SQL .= "AND create_time >= NOW() - INTERVAL '24 hours' ";
    }
    elsif ( $Filter eq '7d' ) {
        $SQL .= "AND create_time >= NOW() - INTERVAL '7 days' ";
    }
    elsif ( $Filter eq '30d' ) {
        $SQL .= "AND create_time >= NOW() - INTERVAL '30 days' ";
    }
    # 'all' filter: no additional WHERE clause

    $SQL .= 'ORDER BY create_time DESC LIMIT 100';

    # Execute query
    my $Success = $DBObject->Prepare(
        SQL => $SQL,
    );

    if ( !$Success ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Failed to query Easy MSI Escalation API logs',
        );
        return {
            Success => 0,
            Message => 'Failed to load API logs',
            Logs    => [],
        };
    }

    # Fetch results
    my @Logs;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %LogEntry = (
            ID                 => $Row[0],
            CreateTime         => $Row[1],
            IncidentNumber     => $Row[2] || '',
            Action             => $Row[3] || '',
            Success            => $Row[4] ? 1 : 0,
            MSITicketNumber    => $Row[5] || '',
            ErrorMessage       => $Row[6] || '',
            ResponseStatusCode => $Row[7] || '',
            RequestPayload     => $Row[8] || '',
            ResponsePayload    => $Row[9] || '',
        );

        push @Logs, \%LogEntry;
    }

    $LogObject->Log(
        Priority => 'debug',
        Message  => "Loaded " . scalar(@Logs) . " Easy MSI Escalation API logs (filter: $Filter)",
    );

    return {
        Success => 1,
        Logs    => \@Logs,
        Count   => scalar(@Logs),
    };
}

sub _GetLogDetails {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $LogID = $Param{LogID};

    if ( !$LogID ) {
        return {
            Success => 0,
            Message => 'Missing log ID',
        };
    }

    # Query specific log entry
    my $Success = $DBObject->Prepare(
        SQL => 'SELECT request_payload, response_payload FROM ebonding_api_log WHERE id = ?',
        Bind => [ \$LogID ],
        Limit => 1,
    );

    if ( !$Success ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to query log details for ID $LogID",
        );
        return {
            Success => 0,
            Message => 'Failed to load log details',
        };
    }

    my @Row = $DBObject->FetchrowArray();

    if ( !@Row ) {
        return {
            Success => 0,
            Message => 'Log entry not found',
        };
    }

    return {
        Success         => 1,
        RequestPayload  => $Row[0] || '',
        ResponsePayload => $Row[1] || '',
    };
}

1;
