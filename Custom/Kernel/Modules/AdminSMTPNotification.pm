# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminSMTPNotification;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::AuthSession',
    'Kernel::System::Group',
    'Kernel::System::Log',
    'Kernel::System::Valid',
    'Kernel::System::Web::Request',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ConfigObject       = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject       = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject        = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $SessionObject      = $Kernel::OM->Get('Kernel::System::AuthSession');
    my $GroupObject        = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject          = $Kernel::OM->Get('Kernel::System::Log');

    # Check permissions
    my $Access = 0;
    my $AdminGroups = $ConfigObject->Get('SMTPNotification::AdminGroups') || ['admin', 'MSIAdmin', 'NOCAdmin'];
    
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
    
    if (!$Access) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('You need to be a member of admin or NOCAdmin group to access this module!'),
        );
    }

    # ------------------------------------------------------------ #
    # save configuration
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Save' ) {
        
        # Challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my %GetParam;
        
        # Get parameters
        for my $Parameter (
            qw(SMTPEnabled Host Port AuthUser AuthPassword Encryption Module From Recipients
            Priority1 Priority2 Priority3 Priority4 Priority5)
            )
        {
            $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        my %Errors;
        
        # Validate required fields
        if (!$GetParam{Host}) {
            $Errors{HostInvalid} = 'ServerError';
        }
        if (!$GetParam{Port} || $GetParam{Port} !~ /^\d+$/) {
            $Errors{PortInvalid} = 'ServerError';
        }
        if (!$GetParam{From} || $GetParam{From} !~ /^.+@.+\..+$/) {
            $Errors{FromInvalid} = 'ServerError';
        }
        if ($GetParam{Encryption} && $GetParam{Encryption} !~ /^(none|ssl|starttls)$/) {
            $Errors{EncryptionInvalid} = 'ServerError';
        }

        # If errors, show form again
        if (%Errors) {
            $Self->_Edit(
                Action => 'Save',
                Errors => \%Errors,
                %GetParam,
            );
            my $Output = $LayoutObject->Header();
            $Output .= $LayoutObject->NavigationBar();
            $Output .= $LayoutObject->Output(
                TemplateFile => 'AdminSMTPNotification',
                Data         => \%GetParam,
            );
            $Output .= $LayoutObject->Footer();
            return $Output;
        }

        # Save configuration
        my $Success = 1;
        
        # Determine the correct SMTP module
        my $SMTPModule;
        if ($GetParam{Module} && $GetParam{Module} ne 'auto') {
            $SMTPModule = $GetParam{Module};
        } else {
            # Auto-detect based on encryption and port
            if ($GetParam{Encryption} eq 'ssl' || $GetParam{Port} eq '465') {
                $SMTPModule = 'Kernel::System::Email::SMTPS';
            } elsif ($GetParam{Encryption} eq 'starttls' || $GetParam{Port} eq '587') {
                $SMTPModule = 'Kernel::System::Email::SMTPTLS';
            } else {
                $SMTPModule = 'Kernel::System::Email::SMTP';
            }
        }
        
        # Save SMTP settings
        for my $Setting (
            { Key => 'SMTPNotification::Enabled',      Value => $GetParam{SMTPEnabled} ? '1' : '0' },
            { Key => 'SMTPNotification::Host',         Value => $GetParam{Host} },
            { Key => 'SMTPNotification::Port',         Value => $GetParam{Port} },
            { Key => 'SMTPNotification::AuthUser',     Value => $GetParam{AuthUser} },
            { Key => 'SMTPNotification::AuthPassword', Value => $GetParam{AuthPassword} },
            { Key => 'SMTPNotification::Encryption',   Value => $GetParam{Encryption} || 'none' },
            { Key => 'SMTPNotification::Module',       Value => $GetParam{Module} || 'auto' },
            { Key => 'SMTPNotification::From',         Value => $GetParam{From} },
            { Key => 'SMTPNotification::Recipients',   Value => $GetParam{Recipients} },
            { Key => 'SMTPNotification::Priority::1',  Value => $GetParam{Priority1} ? '1' : '0' },
            { Key => 'SMTPNotification::Priority::2',  Value => $GetParam{Priority2} ? '1' : '0' },
            { Key => 'SMTPNotification::Priority::3',  Value => $GetParam{Priority3} ? '1' : '0' },
            { Key => 'SMTPNotification::Priority::4',  Value => $GetParam{Priority4} ? '1' : '0' },
            { Key => 'SMTPNotification::Priority::5',  Value => $GetParam{Priority5} ? '1' : '0' },
            )
        {
            $ConfigObject->Set(
                Key   => $Setting->{Key},
                Value => $Setting->{Value},
            );
            
            # Also update in SysConfig
            my $ExclusiveLockGUID = $Kernel::OM->Get('Kernel::System::SysConfig')->SettingLock(
                Name   => $Setting->{Key},
                Force  => 1,
                UserID => $Self->{UserID},
            );
            
            $Success = $Kernel::OM->Get('Kernel::System::SysConfig')->SettingUpdate(
                Name              => $Setting->{Key},
                IsValid           => 1,
                EffectiveValue    => $Setting->{Value},
                ExclusiveLockGUID => $ExclusiveLockGUID,
                UserID            => $Self->{UserID},
            );
            
            if (!$Success) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Could not update setting $Setting->{Key}!",
                );
            }
        }
        
        # Also update SendmailModule settings to keep them in sync
        my %SendmailSettings = (
            'SendmailModule'               => $SMTPModule,
            'SendmailModule::Host'         => $GetParam{Host},
            'SendmailModule::Port'         => $GetParam{Port},
            'SendmailModule::AuthUser'     => $GetParam{AuthUser},
            'SendmailModule::AuthPassword' => $GetParam{AuthPassword},
        );
        
        # Update SendmailModule settings
        for my $SendmailSetting (keys %SendmailSettings) {
            next if !$SendmailSettings{$SendmailSetting};
            
            my $ExclusiveLockGUID = $Kernel::OM->Get('Kernel::System::SysConfig')->SettingLock(
                Name   => $SendmailSetting,
                Force  => 1,
                UserID => $Self->{UserID},
            );
            
            if ($ExclusiveLockGUID) {
                $Success = $Kernel::OM->Get('Kernel::System::SysConfig')->SettingUpdate(
                    Name              => $SendmailSetting,
                    IsValid           => 1,
                    EffectiveValue    => $SendmailSettings{$SendmailSetting},
                    ExclusiveLockGUID => $ExclusiveLockGUID,
                    UserID            => $Self->{UserID},
                );
                
                if (!$Success) {
                    $LogObject->Log(
                        Priority => 'error',
                        Message  => "Could not update SendmailModule setting $SendmailSetting!",
                    );
                }
            }
        }
        
        # Deploy configuration
        if ($Success) {
            my $DeploySuccess = $Kernel::OM->Get('Kernel::System::SysConfig')->ConfigurationDeploy(
                Comments    => "SMTP Notification configuration update with SendmailModule sync",
                AllSettings => 1,
                UserID      => $Self->{UserID},
                Force       => 1,
            );
            
            if (!$DeploySuccess) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Could not deploy SMTP notification configuration!",
                );
            }
        }

        # Redirect to overview
        return $LayoutObject->Redirect(
            OP => "Action=AdminSMTPNotification;Saved=1"
        );
    }

    # ------------------------------------------------------------ #
    # test connection
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'TestConnection' ) {
        
        # Challenge token check
        $LayoutObject->ChallengeTokenCheck();
        
        my %TestResult;
        
        # Get current configuration
        my $Host       = $ConfigObject->Get('SMTPNotification::Host');
        my $Port       = $ConfigObject->Get('SMTPNotification::Port');
        my $AuthUser   = $ConfigObject->Get('SMTPNotification::AuthUser');
        my $AuthPass   = $ConfigObject->Get('SMTPNotification::AuthPassword');
        my $Encryption = $ConfigObject->Get('SMTPNotification::Encryption');
        my $Module     = $ConfigObject->Get('SMTPNotification::Module') || 'auto';
        
        # Determine which module to test
        my $TestModule;
        if ($Module ne 'auto') {
            $TestModule = $Module;
        } else {
            if ($Encryption eq 'ssl' || $Port eq '465') {
                $TestModule = 'Kernel::System::Email::SMTPS';
            } elsif ($Encryption eq 'starttls' || $Port eq '587') {
                $TestModule = 'Kernel::System::Email::SMTPTLS';
            } else {
                $TestModule = 'Kernel::System::Email::SMTP';
            }
        }
        
        # Try to connect to SMTP server
        eval {
            require Net::SMTP;
            
            my $SMTP;
            if ($TestModule =~ /SMTPS$/ || $Encryption eq 'ssl') {
                require Net::SMTP::SSL;
                $SMTP = Net::SMTP::SSL->new(
                    $Host,
                    Port    => $Port,
                    Timeout => 10,
                );
            }
            else {
                $SMTP = Net::SMTP->new(
                    $Host,
                    Port    => $Port,
                    Timeout => 10,
                );
                
                if ($SMTP && ($TestModule =~ /SMTPTLS$/ || $Encryption eq 'starttls')) {
                    $SMTP->starttls();
                }
            }
            
            if ($SMTP) {
                if ($AuthUser && $AuthPass) {
                    $SMTP->auth($AuthUser, $AuthPass);
                }
                $SMTP->quit();
                $TestResult{Success} = 1;
                $TestResult{Message} = Translatable('Connection successful!');
            }
            else {
                $TestResult{Success} = 0;
                $TestResult{Message} = Translatable('Could not connect to SMTP server!');
            }
        };
        
        if ($@) {
            $TestResult{Success} = 0;
            $TestResult{Message} = "Error: $@";
        }
        
        # Return JSON response
        my $JSON = $LayoutObject->JSONEncode(
            Data => \%TestResult,
        );
        
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # ------------------------------------------------------------ #
    # show configuration form
    # ------------------------------------------------------------ #
    else {
        my $Saved = $ParamObject->GetParam( Param => 'Saved' ) || 0;
        
        $Self->_Edit(
            Action => 'Change',
            Saved  => $Saved,
        );
        
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminSMTPNotification',
        );
        $Output .= $LayoutObject->Footer();
        
        return $Output;
    }
}

sub _Edit {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # Get current configuration
    $Param{SMTPEnabled}   = $Param{SMTPEnabled}   // $ConfigObject->Get('SMTPNotification::Enabled');
    $Param{Host}          = $Param{Host}          // $ConfigObject->Get('SMTPNotification::Host');
    $Param{Port}          = $Param{Port}          // $ConfigObject->Get('SMTPNotification::Port');
    $Param{AuthUser}      = $Param{AuthUser}      // $ConfigObject->Get('SMTPNotification::AuthUser');
    $Param{AuthPassword}  = $Param{AuthPassword}  // $ConfigObject->Get('SMTPNotification::AuthPassword');
    $Param{Encryption}    = $Param{Encryption}    // $ConfigObject->Get('SMTPNotification::Encryption');
    $Param{Module}        = $Param{Module}        // $ConfigObject->Get('SMTPNotification::Module') || 'auto';
    $Param{From}          = $Param{From}          // $ConfigObject->Get('SMTPNotification::From');
    $Param{Recipients}    = $Param{Recipients}    // $ConfigObject->Get('SMTPNotification::Recipients');
    
    # Priority settings
    for my $Priority (1..5) {
        my $Key = "Priority$Priority";
        my $ConfigValue = $ConfigObject->Get("SMTPNotification::Priority::$Priority");
        # Default to enabled (1) if not configured
        $Param{$Key} = $Param{$Key} // (defined $ConfigValue ? $ConfigValue : 1);
    }
    
    # Build encryption selection
    $Param{EncryptionStrg} = $LayoutObject->BuildSelection(
        Data => {
            'none'     => 'None',
            'ssl'      => 'SSL/TLS',
            'starttls' => 'STARTTLS',
        },
        Name       => 'Encryption',
        SelectedID => $Param{Encryption} || 'none',
        Class      => 'Modernize',
    );
    
    # Build module selection
    $Param{ModuleStrg} = $LayoutObject->BuildSelection(
        Data => {
            'auto'                           => 'Automatic (based on encryption)',
            'Kernel::System::Email::SMTP'   => 'SMTP (standard)',
            'Kernel::System::Email::SMTPS'  => 'SMTPS (SSL)',
            'Kernel::System::Email::SMTPTLS' => 'SMTPTLS (STARTTLS)',
        },
        Name       => 'Module',
        SelectedID => $Param{Module} || 'auto',
        Class      => 'Modernize',
    );
    
    $LayoutObject->Block(
        Name => 'Overview',
        Data => \%Param,
    );
    
    if ($Param{Saved}) {
        $LayoutObject->Block(
            Name => 'SavedMessage',
        );
    }
    
    return 1;
}

1;