# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminSMSNotification;

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
    my $WebserviceObject = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');

    # Check permissions
    my $Access = 0;
    
    # Define allowed groups based on JIRA requirements:
    # - MSI Personnel (admin group)
    # - Customer Administrator (customer_admin group)
    # - NOCAdmin users (added for Miscellaneous menu access)
    
    my $AdminGroups = $ConfigObject->Get('SMSNotification::AdminGroups') || ['admin', 'MSIAdmin', 'NOCAdmin'];
    
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
        my %TestParams = (
            AccountSID        => $ParamObject->GetParam( Param => 'AccountSID' ) || '',
            AuthToken         => $ParamObject->GetParam( Param => 'AuthToken' ) || '',
            FromNumber        => $ParamObject->GetParam( Param => 'FromNumber' ) || '',
            DefaultRecipients => $ParamObject->GetParam( Param => 'DefaultRecipients' ) || '',
        );

        # Validation
        my $Result;
        if ( !$TestParams{AccountSID} || !$TestParams{AuthToken} || !$TestParams{FromNumber} ) {
            $Result = {
                Success => 0,
                Message => "Missing required parameters (Account SID, Auth Token, From Number).",
            };
        } elsif ( $TestParams{AccountSID} !~ /^AC[a-f0-9]{32}$/i ) {
            $Result = {
                Success => 0,
                Message => "Invalid Account SID format. Must start with 'AC' followed by 32 hex characters.",
            };
        } elsif ( length($TestParams{AuthToken}) != 32 ) {
            $Result = {
                Success => 0,
                Message => "Invalid Auth Token format. Must be exactly 32 characters.",
            };
        } elsif ( $TestParams{FromNumber} !~ /^\+[1-9]\d{1,14}$/ ) {
            $Result = {
                Success => 0,
                Message => "Invalid From Number format. Must be in E.164 format (e.g., +12345678900).",
            };
        } elsif ( !$TestParams{DefaultRecipients} ) {
            $Result = {
                Success => 0,
                Message => "No default recipients configured. Please add at least one phone number to test.",
            };
        } else {
            # Validate and send test SMS to default recipients
            my $CleanRecipients = $TestParams{DefaultRecipients};
            $CleanRecipients =~ s/\s+//g;  # Remove all whitespace
            my @Recipients = split /,/, $CleanRecipients;
            
            my @ValidRecipients;
            for my $Recipient (@Recipients) {
                if ( $Recipient && $Recipient =~ /^\+[1-9]\d{1,14}$/ ) {
                    push @ValidRecipients, $Recipient;
                } elsif ( $Recipient ) {
                    $Result = {
                        Success => 0,
                        Message => "Invalid recipient phone number format: $Recipient. Must be in E.164 format.",
                    };
                    last;
                }
            }
            
            if ( !$Result && !@ValidRecipients ) {
                $Result = {
                    Success => 0,
                    Message => "No valid recipients found in default recipients list.",
                };
            }
            
            if ( !$Result ) {
                # Send actual test SMS using TwilioSMS class
                my $TwilioSMSObject = $Kernel::OM->Get('Kernel::System::TwilioSMS');
                
                my $TestMessage = "[MSST SMS Test] SMS notification test from LSMP system. Configuration is working correctly.";
                
                my %SMSResult = $TwilioSMSObject->SendSMS(
                    Recipients => \@ValidRecipients,
                    Message    => $TestMessage,
                    AccountSID => $TestParams{AccountSID},
                    AuthToken  => $TestParams{AuthToken},
                    FromNumber => $TestParams{FromNumber},
                );
                
                if ( $SMSResult{Success} && $SMSResult{FailureCount} == 0 ) {
                    $Result = {
                        Success => 1,
                        Message => "Test SMS sent successfully to $SMSResult{SuccessCount} recipient(s).",
                    };
                } elsif ( $SMSResult{Success} && $SMSResult{FailureCount} > 0 ) {
                    $Result = {
                        Success => 0,
                        Message => "Mixed results: $SMSResult{SuccessCount} successful, $SMSResult{FailureCount} failed. Check failed numbers: " . join(', ', @{$SMSResult{FailedNumbers}}),
                    };
                } else {
                    $Result = {
                        Success => 0,
                        Message => $SMSResult{ErrorMessage} || "All test SMS failed. Please check your Twilio credentials and phone numbers.",
                    };
                }
            }
        }

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
        # Get form parameters
        my %FormData = (
            TwilioAccountSID  => $ParamObject->GetParam( Param => 'TwilioAccountSID' ) || '',
            TwilioAuthToken   => $ParamObject->GetParam( Param => 'TwilioAuthToken' ) || '',
            TwilioFromNumber  => $ParamObject->GetParam( Param => 'TwilioFromNumber' ) || '',
            DefaultRecipients => $ParamObject->GetParam( Param => 'DefaultRecipients' ) || '',
        );

        # Get priority settings
        for my $Priority ( 1 .. 5 ) {
            $FormData{"Priority${Priority}Enabled"} = $ParamObject->GetParam( Param => "Priority${Priority}Enabled" ) || 0;
        }

        # Validate form data
        my %Errors;
        
        if ( !$FormData{TwilioAccountSID} ) {
            $Errors{TwilioAccountSIDInvalid} = 'ServerError';
        }
        elsif ( $FormData{TwilioAccountSID} !~ /^AC[a-f0-9]{32}$/i ) {
            $Errors{TwilioAccountSIDInvalid} = 'ServerError';
        }

        if ( !$FormData{TwilioAuthToken} ) {
            $Errors{TwilioAuthTokenInvalid} = 'ServerError';
        }
        elsif ( length($FormData{TwilioAuthToken}) != 32 ) {
            $Errors{TwilioAuthTokenInvalid} = 'ServerError';
        }

        if ( !$FormData{TwilioFromNumber} ) {
            $Errors{TwilioFromNumberInvalid} = 'ServerError';
        }
        elsif ( $FormData{TwilioFromNumber} !~ /^\+[1-9]\d{1,14}$/ ) {
            $Errors{TwilioFromNumberInvalid} = 'ServerError';
        }

        # Validate Default Recipients if provided
        if ( $FormData{DefaultRecipients} ) {
            # Remove whitespace and split by comma
            my $CleanRecipients = $FormData{DefaultRecipients};
            $CleanRecipients =~ s/\s+//g;  # Remove all whitespace
            my @Recipients = split /,/, $CleanRecipients;
            
            for my $Recipient (@Recipients) {
                if ( $Recipient && $Recipient !~ /^\+[1-9]\d{1,14}$/ ) {
                    $Errors{DefaultRecipientsInvalid} = 'ServerError';
                    last;
                }
            }
        }

        # If no errors, save configuration
        if ( !%Errors ) {
            my $Success = 1;
            
            $LogObject->Log(
                Priority => 'info',
                Message  => "SMS Config: Starting save process for user $Self->{UserID}",
            );
            
            # Save SMS configuration to SysConfig
            my @ConfigSettings = (
                {
                    Name  => 'SMSNotification::TwilioAccountSID',
                    Value => $FormData{TwilioAccountSID},
                },
                {
                    Name  => 'SMSNotification::TwilioAuthToken',
                    Value => $FormData{TwilioAuthToken},
                },
                {
                    Name  => 'SMSNotification::TwilioFromNumber',
                    Value => $FormData{TwilioFromNumber},
                },
                {
                    Name  => 'SMSNotification::DefaultRecipients',
                    Value => $FormData{DefaultRecipients},
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
                        Message  => "SMS Config: Failed to lock setting $Setting->{Name}",
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
                        Message  => "SMS Config: Failed to update setting $Setting->{Name}",
                    );
                    last;
                }
            }


            # Save priority settings to SysConfig
            if ($Success) {
                for my $Priority ( 1 .. 5 ) {
                    my $SettingName = "SMSNotification::Priority::${Priority}::Enabled";
                    
                    # Lock setting
                    my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
                        Name   => $SettingName,
                        Force  => 1,
                        UserID => $Self->{UserID},
                    );

                    # Update setting
                    $SysConfigObject->SettingUpdate(
                        Name              => $SettingName,
                        IsValid           => 1,
                        EffectiveValue    => $FormData{"Priority${Priority}Enabled"},
                        ExclusiveLockGUID => $ExclusiveLockGUID,
                        UserID            => $Self->{UserID},
                    );
                }

                # Deploy configuration
                my $DeploymentID = $SysConfigObject->ConfigurationDeploy(
                    Comments    => "SMS Notification settings updated",
                    AllSettings => 1,
                    Force       => 1,
                    UserID      => $Self->{UserID},
                );

                if ($DeploymentID) {
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

    # Set default values from SysConfig
    $Param{TwilioAccountSID} //= $ConfigObject->Get('SMSNotification::TwilioAccountSID') || '';
    $Param{TwilioAuthToken}  //= $ConfigObject->Get('SMSNotification::TwilioAuthToken') || '';
    $Param{TwilioFromNumber} //= $ConfigObject->Get('SMSNotification::TwilioFromNumber') || '';
    $Param{DefaultRecipients} //= $ConfigObject->Get('SMSNotification::DefaultRecipients') || '';

    # Get priority settings from SysConfig
    for my $Priority ( 1 .. 5 ) {
        my $SettingName = "SMSNotification::Priority::${Priority}::Enabled";
        my $ConfigValue = $ConfigObject->Get($SettingName);
        # Default to enabled (1) if not configured
        $Param{"Priority${Priority}Enabled"} //= defined $ConfigValue ? $ConfigValue : 1;
    }

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

    # Build priority rows
    my @PriorityList = (
        { ID => 1, Name => 'P1-Critical' },
        { ID => 2, Name => 'P2-High' },
        { ID => 3, Name => 'P3-Medium' },
        { ID => 4, Name => 'P4-Low' },
        # ID 5 is deprecated with the P1-P4 system
    );

    for my $Priority (@PriorityList) {
        $LayoutObject->Block(
            Name => 'PriorityRow',
            Data => {
                %{$Priority},
                Checked => $Param{"Priority$Priority->{ID}Enabled"} ? 'checked="checked"' : '',
            },
        );
    }

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminSMSNotification',
        Data         => \%Param,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

1;