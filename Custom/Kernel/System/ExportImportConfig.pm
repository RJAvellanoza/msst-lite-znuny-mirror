# --
# Copyright (C) 2025 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::ExportImportConfig;

use strict;
use warnings;

use MIME::Base64;
use Digest::SHA qw(sha256_hex);
use File::Basename;
use File::Path qw(make_path);
use IO::Compress::Gzip qw(gzip);
use IO::Uncompress::Gunzip qw(gunzip);
use JSON::XS;
use Crypt::CBC;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::EncryptionKey',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::SysConfig',
    'Kernel::System::Time',
);

=head1 NAME

Kernel::System::ExportImportConfig - Simplified Export/Import Configuration Management (MVP)

=head1 DESCRIPTION

Simplified MVP version (~500 lines) that exports/imports critical configurations with safety mechanisms.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    $Self->{BackupDirectory} = $ConfigObject->Get('Home') . '/var/backups/config';
    
    if ( !-d $Self->{BackupDirectory} ) {
        make_path($Self->{BackupDirectory}, { mode => 0770 });
    }
    
    $Self->{CacheType} = 'ExportImportProgress';
    $Self->{CacheTTL}  = 60 * 60;

    return $Self;
}

sub ExportConfiguration {
    my ( $Self, %Param ) = @_;

    return { Success => 0, Message => 'Need UserID!' } if !$Param{UserID};

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $ProgressID = 'export_' . time() . '_' . int(rand(10000));
    $Self->_UpdateProgress( ID => $ProgressID, Step => 'Starting export', Percent => 0 );

    my $Result;
    eval {
        my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $TimeObject->SystemTime2Date(
            SystemTime => $TimeObject->SystemTime(),
        );
        # Use the required filename format: Znuny_ConfigurationExport_YYYYMMDD.gzip
        my $FileName = sprintf("Znuny_ConfigurationExport_%04d%02d%02d",
            $Year, $Month, $Day);
        my $TempFileName = sprintf("temp_%04d%02d%02d_%02d%02d%02d.json",
            $Year, $Month, $Day, $Hour, $Min, $Sec);
        my $FilePath = "$Self->{BackupDirectory}/$TempFileName";
        my $CompressedFilePath = "$Self->{BackupDirectory}/${FileName}.gzip";

        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Collecting configuration', Percent => 30 );
        
        my %ConfigData = (
            Metadata => {
                Version    => '1.0',
                Created    => $TimeObject->CurrentTimestamp(),
                CreatedBy  => $Param{UserID},
                SystemInfo => {
                    ZNUNYVersion => $ConfigObject->Get('Version') || '6.5',
                    FQDN         => $ConfigObject->Get('FQDN') || 'localhost',
                    SystemID     => $ConfigObject->Get('SystemID') || '10',
                },
            },
            Configurations => {
                SMSSettings    => $Self->_ExportSMSSettings(),
                SMTPSettings   => $Self->_ExportSMTPSettings(),
                SysConfig      => $Self->_ExportCriticalSysConfig(),
                ZabbixConfig   => $Self->_ExportZabbixConfig(),
                TicketPrefixes => $Self->_ExportTicketPrefixes(),
            },
        );

        my $JSON = JSON::XS->new->utf8->pretty->encode(\%ConfigData);
        
        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Encrypting configuration data', Percent => 60 );
        
        # Encrypt the entire JSON configuration
        my $EncryptedJSON = $Self->_EncryptConfiguration($JSON);
        if (!$EncryptedJSON) {
            $Self->_UpdateProgress( 
                ID => $ProgressID, 
                Step => 'Export failed: Encryption error', 
                Percent => 100, 
                Status => 'error' 
            );
            return { 
                Success => 0, 
                Message => 'Failed to encrypt configuration data' 
            };
        }
        
        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Compressing backup', Percent => 80 );
        
        # Compress encrypted data directly in memory (no intermediate file)
        my $CompressedData;
        gzip \$EncryptedJSON => \$CompressedData
            or die "Compression failed: $IO::Compress::Gzip::GzipError";
        
        my $MainObject = $Kernel::OM->Get('Kernel::System::Main');
        $MainObject->FileWrite( Location => $CompressedFilePath, Content => \$CompressedData, Mode => 'binmode' );
        
        my $FileContent = $MainObject->FileRead( Location => $CompressedFilePath, Mode => 'binmode' );
        my $FileHash = sha256_hex(${$FileContent});
        my $FileSize = -s $CompressedFilePath;

        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Export completed', Percent => 100, Status => 'completed' );

        $LogObject->Log( Priority => 'info', Message => "Configuration exported: $CompressedFilePath" );

        $Result = {
            Success  => 1,
            FileName => basename($CompressedFilePath),
            FilePath => $CompressedFilePath,
            FileSize => $FileSize,
            FileHash => $FileHash,
            Message  => 'Configuration exported successfully',
        };
    };
    
    if ($@) {
        my $Error = $@;
        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Export failed', Percent => 0, Status => 'error', Error => $Error );
        $LogObject->Log( Priority => 'error', Message => "Export failed: $Error" );
        return { Success => 0, Message => "Export failed: $Error" };
    }
    
    # Return the result from the eval block
    return $Result || { Success => 0, Message => 'Unexpected error in export' };
}

sub ImportConfiguration {
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(FilePath UserID)) {
        return { Success => 0, Message => "Need $Needed!" } if !$Param{$Needed};
    }

    my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
    my $MainObject    = $Kernel::OM->Get('Kernel::System::Main');
    my $DBObject      = $Kernel::OM->Get('Kernel::System::DB');
    my $CacheObject   = $Kernel::OM->Get('Kernel::System::Cache');
    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
    
    my $ProgressID = 'import_' . time() . '_' . int(rand(10000));
    $Self->_UpdateProgress( ID => $ProgressID, Step => 'Starting import', Percent => 0 );

    return { Success => 0, Message => "File not found: $Param{FilePath}" } if !-f $Param{FilePath};

    my $Result;
    
    eval {
        # Validate backup file
        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Validating backup file', Percent => 10 );
        my $ValidationResult = $Self->ValidateImport( FilePath => $Param{FilePath} );
        if (!$ValidationResult || !$ValidationResult->{Success}) {
            my $ErrMsg = $ValidationResult->{Message} || 'Validation failed';
            die $ErrMsg;
        }
        
        # Create pre-import backup
        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Creating pre-import backup', Percent => 20 );
        
        my $OrigBackupDir = $Self->{BackupDirectory};
        $Self->{BackupDirectory} = $Self->{BackupDirectory} . '/pre-import';
        if (!-d $Self->{BackupDirectory}) {
            File::Path::make_path($Self->{BackupDirectory}, { mode => 0770 });
        }
        
        my $BackupResult = $Self->ExportConfiguration( UserID => $Param{UserID} );
        $Self->{BackupDirectory} = $OrigBackupDir;
        
        if (!$BackupResult || !$BackupResult->{Success}) {
            my $ErrMsg = $BackupResult->{Message} || 'Pre-import backup failed';
            die "Failed to create pre-import backup: $ErrMsg";
        }
        
        my $PreImportBackup = $BackupResult->{FilePath};
        
        # Read and decrypt configuration
        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Reading configuration', Percent => 30 );
        my $CompressedContent = $MainObject->FileRead( Location => $Param{FilePath}, Mode => 'binmode' );
        
        my $EncryptedContent;
        gunzip $CompressedContent => \$EncryptedContent
            or die "Failed to decompress: $IO::Uncompress::Gunzip::GunzipError";
        
        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Decrypting configuration data', Percent => 40 );
        
        # Try to decrypt the configuration, fallback to unencrypted if it fails
        my $JSONContent = $Self->_DecryptConfiguration($EncryptedContent);
        
        if (!$JSONContent) {
            # Fallback: treat as unencrypted (backward compatibility)
            $JSONContent = $EncryptedContent;
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'info',
                Message  => 'Configuration appears to be unencrypted, proceeding without decryption (backward compatibility)',
            );
        }
        
        my $ConfigData = JSON::XS->new->utf8->decode($JSONContent);
        
        # Get exclusive lock for configuration changes
        my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
            LockAll => 1,
            Force   => 1,
            UserID  => $Param{UserID}
        );
        
        if (!$ExclusiveLockGUID) {
            die "Failed to obtain SysConfig lock for import";
        }
        
        # Begin transaction
        $DBObject->Do(SQL => 'BEGIN');
        
        my $ImportSuccess = 1;
        my @ImportErrors;
        
        # Import components
        my %ImportSteps = (
            SMSSettings    => { Step => 'Importing SMS settings', Percent => 50 },
            SMTPSettings   => { Step => 'Importing SMTP settings', Percent => 60 },
            SysConfig      => { Step => 'Importing SysConfig', Percent => 70 },
            ZabbixConfig   => { Step => 'Importing Zabbix configuration', Percent => 75 },
            TicketPrefixes => { Step => 'Importing ticket prefixes', Percent => 80 },
        );
        
        for my $Component (qw(SMSSettings SMTPSettings SysConfig ZabbixConfig TicketPrefixes)) {
            next if !$ConfigData->{Configurations}{$Component};
            
            $Self->_UpdateProgress( ID => $ProgressID, %{$ImportSteps{$Component}} );
            
            eval {
                my $Method = "_Import$Component";
                $Self->$Method($ConfigData->{Configurations}{$Component}, $Param{UserID}, $ExclusiveLockGUID);
            };
            if ($@) {
                push @ImportErrors, "$Component: $@";
                $ImportSuccess = 0;
                last;
            }
        }
        
        if ($ImportSuccess) {
            # Commit database changes
            $DBObject->Do(SQL => 'COMMIT');
            
            # Deploy configuration changes
            $Self->_UpdateProgress( ID => $ProgressID, Step => 'Deploying configuration', Percent => 90 );
            
            my $DeployResult = $SysConfigObject->ConfigurationDeploy(
                Comments          => "Imported from: " . basename($Param{FilePath}),
                UserID            => $Param{UserID},
                Force             => 1,
                AllSettings       => 1,
                NoValidation      => 1,
                ExclusiveLockGUID => $ExclusiveLockGUID,
            );
            
            if (!$DeployResult) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Configuration deployment failed after import"
                );
            }
            
            # Clear all caches
            $CacheObject->CleanUp();
            
            # Force reload of configuration to trigger auto-sync
            # This is needed because ZZZZSMTPAutoSync.pm needs to run with the new values
            $Kernel::OM->ObjectsDiscard(
                Objects => ['Kernel::Config'],
            );
            
            # Reinitialize config to trigger Load() in all config files including ZZZZSMTPAutoSync.pm
            my $NewConfigObject = $Kernel::OM->Get('Kernel::Config');
            
            $Result = {
                Success         => 1,
                Message         => 'Configuration imported and deployed successfully',
                PreImportBackup => $PreImportBackup,
            };
        }
        else {
            # Rollback database changes
            $DBObject->Do(SQL => 'ROLLBACK');
            
            # Unlock settings
            if ($ExclusiveLockGUID) {
                $SysConfigObject->SettingUnlock(
                    UnlockAll => 1,
                    ExclusiveLockGUID => $ExclusiveLockGUID,
                );
            }
            
            die "Import failed: " . join(', ', @ImportErrors);
        }
        
        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Import completed', Percent => 100, Status => 'completed' );
    };
    
    if ($@) {
        my $Error = $@;
        $Self->_UpdateProgress( ID => $ProgressID, Step => 'Import failed', Percent => 0, Status => 'error', Error => $Error );
        $LogObject->Log( Priority => 'error', Message => "Import failed: $Error" );
        return { Success => 0, Message => $Error };
    }
    
    return $Result || { Success => 0, Message => 'Import failed' };
}

sub ValidateImport {
    my ( $Self, %Param ) = @_;

    return { Success => 0, Message => 'Need FilePath!' } if !$Param{FilePath};
    return { Success => 0, Message => "File not found: $Param{FilePath}" } if !-f $Param{FilePath};

    # Check file size (max 50MB)
    my $FileSize = -s $Param{FilePath};
    my $MaxSize = 50 * 1024 * 1024;
    
    return { Success => 0, Message => sprintf("File too large: %.2f MB (max: 50 MB)", $FileSize / (1024*1024)) }
        if $FileSize > $MaxSize;

    # Read and decompress
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');
    my $CompressedContent = $MainObject->FileRead( Location => $Param{FilePath}, Mode => 'binmode' );
    
    return { Success => 0, Message => 'Failed to read file' } if !$CompressedContent;
    
    my $EncryptedContent;
    my $GunzipSuccess = gunzip $CompressedContent => \$EncryptedContent;
    
    return { Success => 0, Message => 'Invalid file format: Not a valid GZIP file' }
        if !$GunzipSuccess || !$EncryptedContent;
    
    # Check decompressed size (max 100MB for encrypted content)
    my $DecompressedSize = length($EncryptedContent);
    my $MaxDecompressedSize = 100 * 1024 * 1024;
    
    return { Success => 0, Message => sprintf("Decompressed file too large: %.2f MB (max: 100 MB)", $DecompressedSize / (1024*1024)) }
        if $DecompressedSize > $MaxDecompressedSize;
    
    # Try to decrypt the configuration, fallback to unencrypted if it fails
    my $JSONContent = $Self->_DecryptConfiguration($EncryptedContent);
    
    if (!$JSONContent) {
        # Fallback: treat as unencrypted (backward compatibility)
        $JSONContent = $EncryptedContent;
    }
    
    # Parse JSON
    my $Data;
    eval { $Data = JSON::XS->new->utf8->decode($JSONContent); };
    
    return { Success => 0, Message => 'Invalid file content: Not valid JSON after decryption' }
        if $@ || !$Data;
    
    # Validate structure
    return { Success => 0, Message => 'Invalid backup structure' }
        if !$Data->{Metadata} || !$Data->{Configurations};
    
    # Check version compatibility
    my @Warnings;
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $CurrentVersion = $ConfigObject->Get('Version') || '6.5';
    my $BackupVersion = $Data->{Metadata}{SystemInfo}{ZNUNYVersion} || 'Unknown';
    
    if ($CurrentVersion ne $BackupVersion) {
        my ($CurrentMajor) = $CurrentVersion =~ /^(\d+\.\d+)/;
        my ($BackupMajor) = $BackupVersion =~ /^(\d+\.\d+)/;
        
        push @Warnings, "Version mismatch: Backup from $BackupVersion, current system $CurrentVersion"
            if $CurrentMajor && $BackupMajor && $CurrentMajor ne $BackupMajor;
    }
    
    return {
        Success  => 1,
        Message  => 'File is valid',
        Metadata => $Data->{Metadata},
        Warnings => \@Warnings,
    };
}

sub GetProgress {
    my ( $Self, %Param ) = @_;

    return { Step => 'Unknown', Percent => 0, Status => 'error', Error => 'Need ID!' }
        if !$Param{ID};

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    
    my $Progress = $CacheObject->Get( Type => $Self->{CacheType}, Key => $Param{ID} );
    
    return $Progress || { Step => 'Not started', Percent => 0, Status => 'unknown', Error => '' };
}

# Private methods

sub _UpdateProgress {
    my ( $Self, %Param ) = @_;

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    
    $CacheObject->Set(
        Type  => $Self->{CacheType},
        Key   => $Param{ID},
        Value => {
            Step    => $Param{Step} || '',
            Percent => $Param{Percent} || 0,
            Status  => $Param{Status} || 'running',
            Error   => $Param{Error} || '',
        },
        TTL => $Self->{CacheTTL},
    );
    
    return 1;
}

sub _ExportSMSSettings {
    my ( $Self ) = @_;
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    my %Settings = (
        TwilioAccountSID => $ConfigObject->Get('SMSNotification::TwilioAccountSID') || '',
        TwilioAuthToken  => $ConfigObject->Get('SMSNotification::TwilioAuthToken') || '',
        TwilioFromNumber => $ConfigObject->Get('SMSNotification::TwilioFromNumber') || '',
    );
    
    # Get priority enabled/disabled settings for SMS (these are just "0" or "1" strings)
    for my $Priority (1..4) {
        $Settings{"Priority$Priority"} = $ConfigObject->Get("SMSNotification::Priority::${Priority}::Enabled") || '0';
    }
    
    # Get default SMS recipients
    $Settings{DefaultRecipients} = $ConfigObject->Get("SMSNotification::DefaultRecipients") || [];
    
    return \%Settings;
}

sub _ExportSMTPSettings {
    my ( $Self ) = @_;
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    my %Settings = (
        SendmailModule       => $ConfigObject->Get('SendmailModule') || '',
        SendmailHost         => $ConfigObject->Get('SendmailModule::Host') || '',
        SendmailPort         => $ConfigObject->Get('SendmailModule::Port') || '',
        SendmailAuthUser     => $ConfigObject->Get('SendmailModule::AuthUser') || '',
        SendmailAuthPassword => $ConfigObject->Get('SendmailModule::AuthPassword') || '',
    );
    
    # Get priority enabled/disabled settings (these are just "0" or "1" strings)
    for my $Priority (1..4) {
        $Settings{"Priority$Priority"} = $ConfigObject->Get("SMTPNotification::Priority::${Priority}") || '0';
    }
    
    # Get global recipients setting
    $Settings{Recipients} = $ConfigObject->Get("SMTPNotification::Recipients") || '';
    
    return \%Settings;
}


sub _ExportCriticalSysConfig {
    my ( $Self ) = @_;
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    my @CriticalConfigs = qw(
        LicenseCheck::Enabled
        LicenseCheck::BlockAPI
    );
    
    my %SysConfig;
    for my $Key (@CriticalConfigs) {
        my $Value = $ConfigObject->Get($Key);
        $SysConfig{$Key} = $Value if defined $Value;
    }
    
    return \%SysConfig;
}

sub _ExportZabbixConfig {
    my ( $Self ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    
    # Get all Zabbix configuration from database
    $DBObject->Prepare(
        SQL => 'SELECT config_key, config_value FROM zabbix_config',
    );
    
    my %ZabbixConfig;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $ZabbixConfig{$Row[0]} = $Row[1] || '';
    }
    
    return \%ZabbixConfig;
}

sub _ExportTicketPrefixes {
    my ( $Self ) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    
    # Get all ticket prefixes
    $DBObject->Prepare(
        SQL => 'SELECT type, prefix FROM ticket_prefix WHERE valid_id = 1',
    );
    
    my %Prefixes;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Prefixes{$Row[0]} = $Row[1] || '';
    }
    
    # Also get initial counter value
    $DBObject->Prepare(
        SQL => 'SELECT counter FROM ticket_initial_counter ORDER BY id DESC LIMIT 1',
    );
    
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Prefixes{InitialCounter} = $Row[0] || '0';
    }
    
    return \%Prefixes;
}

sub _ImportSMSSettings {
    my ( $Self, $Data, $UserID, $ExclusiveLockGUID ) = @_;

    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
    
    # Use the provided lock instead of getting a new one
    die "No lock provided for SMS import" if !$ExclusiveLockGUID;
    
    # Import Twilio settings
    my %TwilioMap = (
        TwilioAccountSID => 'SMSNotification::TwilioAccountSID',
        TwilioAuthToken  => 'SMSNotification::TwilioAuthToken',
        TwilioFromNumber => 'SMSNotification::TwilioFromNumber',
    );
    
    for my $Key (keys %TwilioMap) {
        next if !$Data->{$Key};
        
        my $Success = $SysConfigObject->SettingUpdate(
            Name              => $TwilioMap{$Key},
            IsValid           => 1,
            EffectiveValue    => $Data->{$Key},
            ExclusiveLockGUID => $ExclusiveLockGUID,
            UserID            => $UserID,
        );
        
        if (!$Success) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Failed to update SMS setting $TwilioMap{$Key}",
            );
        }
    }
    
    # Import priority settings (simple 0/1 enabled values)
    for my $Priority (1..4) {
        my $PriorityValue = $Data->{"Priority$Priority"};
        next if !defined $PriorityValue;
        
        # Handle both old format (hash) and new format (string)
        my $EnabledValue = $PriorityValue;
        if (ref($PriorityValue) eq 'HASH') {
            # Old format - extract the Enabled value
            $EnabledValue = $PriorityValue->{Enabled} || '0';
        }
        
        $SysConfigObject->SettingUpdate(
            Name              => "SMSNotification::Priority::${Priority}::Enabled",
            IsValid           => 1,
            EffectiveValue    => $EnabledValue,
            ExclusiveLockGUID => $ExclusiveLockGUID,
            UserID            => $UserID,
        );
    }
    
    # Import default recipients if present
    if (defined $Data->{DefaultRecipients}) {
        $SysConfigObject->SettingUpdate(
            Name              => "SMSNotification::DefaultRecipients",
            IsValid           => 1,
            EffectiveValue    => $Data->{DefaultRecipients},
            ExclusiveLockGUID => $ExclusiveLockGUID,
            UserID            => $UserID,
        );
    }
    
    return 1;
}

sub _ImportSMTPSettings {
    my ( $Self, $Data, $UserID, $ExclusiveLockGUID ) = @_;

    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Use the provided lock instead of getting a new one
    die "No lock provided for SMTP import" if !$ExclusiveLockGUID;
    
    # Determine SMTP module type based on port or existing module
    my $SMTPModule = $Data->{SendmailModule} || 'Kernel::System::Email::SMTP';
    if (!$Data->{SendmailModule} && $Data->{SendmailPort}) {
        if ($Data->{SendmailPort} eq '465') {
            $SMTPModule = 'Kernel::System::Email::SMTPS';
        } elsif ($Data->{SendmailPort} eq '587') {
            $SMTPModule = 'Kernel::System::Email::SMTPTLS';
        }
    }
    
    # Update SMTPNotification settings (these take precedence via ZZZZSMTPAutoSync.pm)
    my @SMTPNotificationSettings = (
        { Key => 'SMTPNotification::Host',         Value => $Data->{SendmailHost} || '' },
        { Key => 'SMTPNotification::Port',         Value => $Data->{SendmailPort} || '' },
        { Key => 'SMTPNotification::AuthUser',     Value => $Data->{SendmailAuthUser} || '' },
        { Key => 'SMTPNotification::AuthPassword', Value => $Data->{SendmailAuthPassword} || '' },
        { Key => 'SMTPNotification::Module',       Value => $SMTPModule },
        { Key => 'SMTPNotification::Recipients',   Value => $Data->{Recipients} || '' },
    );
    
    # Determine encryption type
    my $Encryption = 'none';
    if ($SMTPModule =~ /SMTPS$/) {
        $Encryption = 'ssl';
    } elsif ($SMTPModule =~ /SMTPTLS$/) {
        $Encryption = 'starttls';
    }
    push @SMTPNotificationSettings, { Key => 'SMTPNotification::Encryption', Value => $Encryption };
    
    # Add priority settings
    for my $Priority (1..4) {
        my $PriorityValue = $Data->{"Priority$Priority"};
        next if !defined $PriorityValue;
        
        # Handle both old format (hash) and new format (string)
        my $EnabledValue = $PriorityValue;
        if (ref($PriorityValue) eq 'HASH') {
            $EnabledValue = $PriorityValue->{Enabled} || '0';
        }
        
        push @SMTPNotificationSettings, { 
            Key => "SMTPNotification::Priority::${Priority}", 
            Value => $EnabledValue 
        };
    }
    
    # Update all SMTPNotification settings
    for my $Setting (@SMTPNotificationSettings) {
        next if !defined $Setting->{Value};
        
        # Set in runtime config first
        $ConfigObject->Set(
            Key   => $Setting->{Key},
            Value => $Setting->{Value},
        );
        
        # Update in SysConfig
        eval {
            $SysConfigObject->SettingUpdate(
                Name              => $Setting->{Key},
                IsValid           => 1,
                EffectiveValue    => $Setting->{Value},
                ExclusiveLockGUID => $ExclusiveLockGUID,
                UserID            => $UserID,
            );
        };
        if ($@) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Failed to update SMTP setting $Setting->{Key}: $@",
            );
        }
    }
    
    # Also update SendmailModule settings for compatibility
    my %SendmailSettings = (
        'SendmailModule'               => $SMTPModule,
        'SendmailModule::Host'         => $Data->{SendmailHost} || '',
        'SendmailModule::Port'         => $Data->{SendmailPort} || '',
        'SendmailModule::AuthUser'     => $Data->{SendmailAuthUser} || '',
        'SendmailModule::AuthPassword' => $Data->{SendmailAuthPassword} || '',
    );
    
    for my $SendmailSetting (keys %SendmailSettings) {
        next if !$SendmailSettings{$SendmailSetting};
        
        eval {
            $SysConfigObject->SettingUpdate(
                Name              => $SendmailSetting,
                IsValid           => 1,
                EffectiveValue    => $SendmailSettings{$SendmailSetting},
                ExclusiveLockGUID => $ExclusiveLockGUID,
                UserID            => $UserID,
            );
        };
        if ($@) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Failed to update SendmailModule setting $SendmailSetting: $@",
            );
        }
    }
    
    return 1;
}

sub _ImportSysConfig {
    my ( $Self, $Data, $UserID, $ExclusiveLockGUID ) = @_;

    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
    
    # Use the provided lock instead of getting a new one
    die "No lock provided for SysConfig import" if !$ExclusiveLockGUID;
    
    for my $Key (keys %{$Data}) {
        $SysConfigObject->SettingUpdate(
            Name              => $Key,
            IsValid           => 1,
            EffectiveValue    => $Data->{$Key},
            ExclusiveLockGUID => $ExclusiveLockGUID,
            UserID            => $UserID,
        );
    }
    
    return 1;
}

sub _ImportZabbixConfig {
    my ( $Self, $Data, $UserID, $ExclusiveLockGUID ) = @_;
    
    my $ZabbixConfigObject = $Kernel::OM->Get('Kernel::System::ZabbixConfig');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Use the ZabbixConfig module's Set method, just like AdminZabbixConfiguration does
    for my $Key (keys %{$Data}) {
        my $Success = $ZabbixConfigObject->Set(
            Key    => $Key,
            Value  => $Data->{$Key},
            UserID => $UserID,
        );
        
        if (!$Success) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Failed to import Zabbix config key: $Key",
            );
        }
    }
    
    return 1;
}

sub _ImportTicketPrefixes {
    my ( $Self, $Data, $UserID, $ExclusiveLockGUID ) = @_;
    
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Import ticket prefixes
    for my $Type (keys %{$Data}) {
        next if $Type eq 'InitialCounter';
        
        # Check if prefix exists
        my $Exists = $DBObject->Prepare(
            SQL => 'SELECT id FROM ticket_prefix WHERE type = ?',
            Bind => [ \$Type ],
        );
        
        my $HasRow = 0;
        while (my @Row = $DBObject->FetchrowArray()) {
            $HasRow = 1;
        }
        
        if ($HasRow) {
            # Update existing prefix
            $DBObject->Do(
                SQL => 'UPDATE ticket_prefix SET prefix = ? WHERE type = ?',
                Bind => [ \$Data->{$Type}, \$Type ],
            );
        } else {
            # Insert new prefix
            $DBObject->Do(
                SQL => 'INSERT INTO ticket_prefix (type, prefix, valid_id, create_time, create_by) VALUES (?, ?, 1, current_timestamp, ?)',
                Bind => [ \$Type, \$Data->{$Type}, \$UserID ],
            );
        }
    }
    
    # Import initial counter if present
    if (defined $Data->{InitialCounter}) {
        $DBObject->Do(
            SQL => 'UPDATE ticket_initial_counter SET counter = ? WHERE id = (SELECT MAX(id) FROM ticket_initial_counter)',
            Bind => [ \$Data->{InitialCounter} ],
        );
    }
    
    return 1;
}

sub _EncryptConfiguration {
    my ( $Self, $JSONData ) = @_;
    
    my $EncryptionKeyObject = $Kernel::OM->Get('Kernel::System::EncryptionKey');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Use the same encryption key as license management
    my $Key = $EncryptionKeyObject->GetKey(KeyName => 'license_aes_key');
    if (!$Key) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'License AES key not found - cannot encrypt configuration data. Please ensure license system is properly initialized.',
        );
        return;
    }
    
    my $Cipher;
    eval {
        $Cipher = Crypt::CBC->new( 
            -key    => $Key, 
            -cipher => 'Rijndael', 
            -header => 'salt',
            -pbkdf  => 'pbkdf2',
        );
    };
    if ($@ || !$Cipher) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to create cipher for encryption: $@",
        );
        return;
    }
    
    # Encrypt the entire JSON data
    my $EncryptedData;
    eval {
        $EncryptedData = $Cipher->encrypt($JSONData);
    };
    if ($@ || !$EncryptedData) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to encrypt configuration data: $@",
        );
        return;
    }
    
    $LogObject->Log(
        Priority => 'info',
        Message  => 'Successfully encrypted entire configuration data',
    );
    
    return $EncryptedData;
}

sub _DecryptConfiguration {
    my ( $Self, $EncryptedData ) = @_;
    
    my $EncryptionKeyObject = $Kernel::OM->Get('Kernel::System::EncryptionKey');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Use the same encryption key as license management
    my $Key = $EncryptionKeyObject->GetKey(KeyName => 'license_aes_key');
    if (!$Key) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'License AES key not found - cannot decrypt configuration data.',
        );
        return;
    }
    
    my $Cipher;
    eval {
        $Cipher = Crypt::CBC->new( 
            -key    => $Key, 
            -cipher => 'Rijndael', 
            -header => 'salt',
            -pbkdf  => 'pbkdf2',
        );
    };
    if ($@ || !$Cipher) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to create cipher for decryption: $@",
        );
        return;
    }
    
    # Decrypt the entire data
    my $JSONData;
    eval {
        $JSONData = $Cipher->decrypt($EncryptedData);
    };
    if ($@ || !$JSONData) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to decrypt configuration data: $@",
        );
        return;
    }
    
    $LogObject->Log(
        Priority => 'info',
        Message  => 'Successfully decrypted entire configuration data',
    );
    
    return $JSONData;
}


1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST project (GPL).

=cut