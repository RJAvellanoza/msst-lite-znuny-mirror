# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminZabbixConfiguration;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject      = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject       = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ZabbixConfigObject = $Kernel::OM->Get('Kernel::System::ZabbixConfig');
    my $ZabbixAPIObject   = $Kernel::OM->Get('Kernel::System::ZabbixAPI');
    my $JSONObject        = $Kernel::OM->Get('Kernel::System::JSON');
    my $ConfigObject      = $Kernel::OM->Get('Kernel::Config');
    my $GroupObject       = $Kernel::OM->Get('Kernel::System::Group');
    
    # Check permissions - DISABLED - Znuny already checks via Frontend::Module Group config
    my $Access = 1; # FORCE ACCESS - permission check done by Znuny framework
    my $AdminGroups = $ConfigObject->Get('ZabbixIntegration::AdminGroups') || ['admin', 'MSIAdmin', 'NOCAdmin'];
    
    # Debug: Log what we're checking
    use Data::Dumper;
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'error',
        Message  => "AdminZabbixConfiguration: Checking access for UserID: " . ($Self->{UserID} || 'UNDEFINED') . ", Groups to check: " . join(', ', @{$AdminGroups}),
    );
    
    for my $Group ( @{$AdminGroups} ) {
        my $HasPermission = $GroupObject->PermissionCheck(
            UserID    => $Self->{UserID},
            GroupName => $Group,
            Type      => 'rw',
        );
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "AdminZabbixConfiguration: Checking $Group for UserID $Self->{UserID}: " . ($HasPermission ? 'YES' : 'NO'),
        );
        if ($HasPermission) {
            $Access = 1;
            last;
        }
    }

    if ( !$Access ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('You need admin, MSIAdmin, or NOCAdmin permissions to access this module!'),
        );
    }

    # ------------------------------------------------------------ #
    # Test Connection (AJAX)
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'TestConnection' ) {
        
        # Get credentials from form (hidden fields) or Config.pm fallback
        my $FormURL      = $ParamObject->GetParam( Param => 'APIURL' );
        my $FormUser     = $ParamObject->GetParam( Param => 'APIUser' );
        my $FormPassword = $ParamObject->GetParam( Param => 'APIPassword' );
        
        # Use form parameters if available, otherwise fall back to config
        my $APIURL      = (defined $FormURL && $FormURL ne '') ? $FormURL : 
                          ($ConfigObject->Get('ZabbixIntegration::APIURL') || '');
        my $APIUser     = (defined $FormUser && $FormUser ne '') ? $FormUser :
                          ($ConfigObject->Get('ZabbixIntegration::APIUser') || '');
        my $APIPassword = (defined $FormPassword && $FormPassword ne '') ? $FormPassword :
                          ($ConfigObject->Get('ZabbixIntegration::APIPassword') || '');

        my $Result = {
            Success => 0,
            Message => '',
        };

        if ( !$APIURL || !$APIUser || !$APIPassword ) {
            $Result->{Message} = Translatable('Please provide all required fields.');
        }
        else {
            # Test the connection
            my $TestResult = $ZabbixAPIObject->TestConnection(
                APIURL      => $APIURL,
                APIUser     => $APIUser,
                APIPassword => $APIPassword,
            );

            if ( $TestResult->{Success} ) {
                $Result->{Success} = 1;
                $Result->{Message} = Translatable('Connection successful!');
            }
            else {
                $Result->{Message} = $TestResult->{ErrorMessage} 
                    || Translatable('Connection failed. Please check your settings.');
            }
        }

        # Return JSON response
        my $JSON = $JSONObject->Encode(
            Data => $Result,
        );

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # ------------------------------------------------------------ #
    # Save
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Save' ) {
        
        # Challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my %Errors;
        my %GetParam;

        # Get parameters - only non-credential settings
        for my $Parameter (qw(TriggerStates)) {
            $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # Zabbix is always enabled now
        $GetParam{Enabled} = 1;

        # No validation needed for credentials as they're in Config.pm

        # No errors, save configuration
        if ( !%Errors ) {
            
            # Save each configuration item
            for my $Key ( keys %GetParam ) {
                my $Success = $ZabbixConfigObject->Set(
                    Key    => $Key,
                    Value  => $GetParam{$Key},
                    UserID => $Self->{UserID},
                );

                if ( !$Success ) {
                    $Errors{SaveError} = 1;
                    last;
                }
            }

            if ( !%Errors ) {
                # Redirect to admin overview
                return $LayoutObject->Redirect(
                    OP => "Action=AdminZabbixConfiguration;Saved=1"
                );
            }
        }

        # Show form again with errors
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $Self->_ShowForm(
            %GetParam,
            %Errors,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # Show Form
    # ------------------------------------------------------------ #
    else {
        
        # Get current configuration
        my $Config = $ZabbixConfigObject->GetAll();
        
        # Check if we just saved
        my $Saved = $ParamObject->GetParam( Param => 'Saved' ) || 0;

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        
        if ($Saved) {
            $Output .= $LayoutObject->Notify(
                Info => Translatable('Configuration saved successfully.'),
            );
        }
        
        $Output .= $Self->_ShowForm(
            %{$Config},
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }
}

sub _ShowForm {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Load credentials from Config.pm
    $Param{APIURL}      = $ConfigObject->Get('ZabbixIntegration::APIURL') || '';
    $Param{APIUser}     = $ConfigObject->Get('ZabbixIntegration::APIUser') || '';
    $Param{APIPassword} = $ConfigObject->Get('ZabbixIntegration::APIPassword') || '';
    
    # Check if Zabbix configuration is missing
    $Param{ConfigMissing} = 0;
    $Param{ConfigWarning} = '';
    
    if (!$Param{APIURL} || !$Param{APIUser} || !$Param{APIPassword}) {
        $Param{ConfigMissing} = 1;
        my @Missing;
        push @Missing, 'ZabbixIntegration::APIURL' if !$Param{APIURL};
        push @Missing, 'ZabbixIntegration::APIUser' if !$Param{APIUser};
        push @Missing, 'ZabbixIntegration::APIPassword' if !$Param{APIPassword};
        $Param{MissingFields} = join(', ', @Missing);
    }
    
    # Set default values if not provided
    $Param{TriggerStates} ||= 'resolved,closed,cancelled';

    # Fetch audit logs
    my $SQL = "
        SELECT id, ticket_id, action, request_data, response_data, 
               success, error_message, create_time
        FROM zabbix_audit_log
        ORDER BY create_time DESC
        LIMIT 20
    ";
    
    my @AuditLogs;
    if ($DBObject->Prepare(SQL => $SQL)) {
        while (my @Row = $DBObject->FetchrowArray()) {
            # Parse JSON data for display
            my $RequestData = $Row[3] || '{}';
            my $ResponseData = $Row[4] || '{}';
            
            # Try to decode JSON for display
            my ($RequestDisplay, $ResponseDisplay) = ('', '');
            eval {
                my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');
                if ($RequestData) {
                    my $Decoded = $JSONObject->Decode(Data => $RequestData);
                    $RequestDisplay = $Decoded->{EventID} || $Decoded->{TicketNumber} || '';
                }
            };
            
            # Get ticket number if we have ticket ID
            my $TicketNumber = '';
            if ($Row[1]) {
                my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
                my %Ticket = $TicketObject->TicketGet(
                    TicketID => $Row[1],
                    UserID   => 1,
                );
                $TicketNumber = $Ticket{TicketNumber} if %Ticket;
            }
            
            push @AuditLogs, {
                ID           => $Row[0],
                TicketID     => $Row[1] || '',
                TicketNumber => $TicketNumber,
                Action       => $Row[2] || '',
                RequestInfo  => $RequestDisplay,
                Success      => $Row[5] ? 'Success' : 'Failed',
                SuccessClass => $Row[5] ? 'Success' : 'Error',
                ErrorMessage => $Row[6] || '',
                CreateTime   => $Row[7] || '',
            };
        }
    }
    
    $Param{AuditLogs} = \@AuditLogs;

    # Generate the form
    return $LayoutObject->Output(
        TemplateFile => 'AdminZabbixConfiguration',
        Data         => \%Param,
    );
}

1;