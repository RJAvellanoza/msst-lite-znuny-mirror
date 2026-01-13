# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package var::packagesetup::MSSTLiteZabbix;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Cache',
);

=head1 NAME

var::packagesetup::MSSTLiteZabbix - Code to execute during Zabbix integration package installation

=head1 DESCRIPTION

All code to execute during Zabbix integration package installation and uninstallation.
Handles database table creation and removal for Zabbix configuration and integration.

=head1 PUBLIC INTERFACE

=head2 new()

Create an object

    my $CodeObject = var::packagesetup::MSSTLiteZabbix->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # Allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 CodeInstall()

Run the code install part

    my $Result = $CodeObject->CodeInstall();

=cut

sub CodeInstall {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteZabbix: Starting Zabbix integration installation',
    );

    # Create Zabbix configuration tables
    $Self->_CreateZabbixConfigTables();
    
    # Initialize default Zabbix configuration
    $Self->_InitializeZabbixConfig();
    
    # Add Zabbix configuration to Config.pm
    $Self->_AddZabbixConfigToConfigPm();

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteZabbix: Zabbix integration installation completed',
    );

    return 1;
}

=head2 CodeReinstall()

Run the code reinstall part

    my $Result = $CodeObject->CodeReinstall();

=cut

sub CodeReinstall {
    my ( $Self, %Param ) = @_;

    # Same as CodeInstall
    return $Self->CodeInstall(%Param);
}

=head2 CodeUpgrade()

Run the code upgrade part

    my $Result = $CodeObject->CodeUpgrade();

=cut

sub CodeUpgrade {
    my ( $Self, %Param ) = @_;

    # Same as CodeInstall
    return $Self->CodeInstall(%Param);
}

=head2 CodeUninstall()

Run the code uninstall part

    my $Result = $CodeObject->CodeUninstall();

=cut

sub CodeUninstall {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteZabbix: Starting Zabbix integration uninstallation',
    );

    # Remove Zabbix configuration tables (handled by SOMP DatabaseUninstall)
    # Tables will be dropped automatically by the main package uninstall
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteZabbix: Zabbix integration uninstallation completed',
    );

    return 1;
}

=head2 _CreateZabbixConfigTables()

Create Zabbix integration database tables if they don't exist

=cut

sub _CreateZabbixConfigTables {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteZabbix: Creating Zabbix configuration tables',
    );

    # Check if zabbix_config table exists
    my $TablesExist = 1;
    eval {
        $DBObject->Prepare(SQL => 'SELECT 1 FROM zabbix_config LIMIT 1');
    };
    if ($@) {
        $TablesExist = 0;
    }

    if (!$TablesExist) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLiteZabbix: Zabbix tables do not exist, they should be created by DatabaseInstall section',
        );
    } else {
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLiteZabbix: Zabbix configuration tables already exist',
        );
    }

    return 1;
}

=head2 _InitializeZabbixConfig()

Initialize default Zabbix configuration values

=cut

sub _InitializeZabbixConfig {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteZabbix: Initializing Zabbix configuration',
    );

    # Default configuration values are already handled by DatabaseInstall section
    # in the main SOPM file (lines 456-495 in MSSTLite.sopm)
    
    # Verify that configuration was initialized
    my $SQL = 'SELECT COUNT(*) FROM zabbix_config';
    return if !$DBObject->Prepare(SQL => $SQL);

    my $Count = 0;
    while (my @Row = $DBObject->FetchrowArray()) {
        $Count = $Row[0] || 0;
    }

    if ($Count > 0) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLiteZabbix: Found $Count Zabbix configuration entries",
        );
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'MSSTLiteZabbix: No Zabbix configuration entries found - check DatabaseInstall section',
        );
    }

    return 1;
}

=head2 _AddZabbixConfigToConfigPm()

Add Zabbix configuration entries to Config.pm file

=cut

sub _AddZabbixConfigToConfigPm {
    my ( $Self, %Param ) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    my $Home = $ConfigObject->Get('Home');
    my $ConfigFile = "$Home/Kernel/Config.pm";
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => "MSSTLiteZabbix: Adding Zabbix configuration to Config.pm",
    );
    
    # Read the current Config.pm
    my $ConfigContent = '';
    if (open(my $FH, '<', $ConfigFile)) {
        local $/;
        $ConfigContent = <$FH>;
        close($FH);
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLiteZabbix: Cannot read Config.pm: $!",
        );
        return;
    }
    
    # Check if Zabbix configuration already exists
    if ($ConfigContent =~ /ZabbixIntegration::APIURL/) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLiteZabbix: Zabbix configuration already exists in Config.pm",
        );
        return 1;
    }
    
    # Prepare the Zabbix configuration block
    my $ZabbixConfig = q{
    # ---------------------------------------------------- #
    # Zabbix Integration Configuration                    #
    # ---------------------------------------------------- #
    # Configure these settings with your Zabbix API credentials
    # These values are required for the Zabbix integration to work
    
    # Zabbix API URL (e.g., 'https://your-zabbix-server/api_jsonrpc.php')
    $Self->{'ZabbixIntegration::APIURL'}      = '';
    
    # Zabbix API Username
    $Self->{'ZabbixIntegration::APIUser'}     = '';
    
    # Zabbix API Password
    $Self->{'ZabbixIntegration::APIPassword'} = '';
    
    # ---------------------------------------------------- #
    # End of Zabbix Integration Configuration             #
    # ---------------------------------------------------- #
};
    
    # Find the position to insert (before "return 1;" in the Load subroutine)
    if ($ConfigContent =~ /(    # -{10,}.*?end of your own config.*?# -{10,}.*?)(    return 1;)/s) {
        my $BeforeReturn = $1;
        my $ReturnStatement = $2;
        my $InsertPoint = $BeforeReturn . $ReturnStatement;
        my $NewContent = $ZabbixConfig . "\n" . $InsertPoint;
        $ConfigContent =~ s/\Q$InsertPoint\E/$NewContent/;
        
        # Write the updated content back to Config.pm
        if (open(my $FH, '>', $ConfigFile)) {
            print $FH $ConfigContent;
            close($FH);
            
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLiteZabbix: Successfully added Zabbix configuration to Config.pm",
            );
            
            # Clear config cache to pick up new settings
            $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
                Type => 'Config',
            );
            
            return 1;
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLiteZabbix: Cannot write to Config.pm: $!",
            );
            return;
        }
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLiteZabbix: Cannot find proper insertion point in Config.pm",
        );
        return;
    }
}

=head2 GetZabbixConfig()

Get Zabbix configuration value by key

    my $Value = $PackageSetup->GetZabbixConfig(
        Key => 'APIURL',
    );

=cut

sub GetZabbixConfig {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    if ( !$Param{Key} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'MSSTLiteZabbix: Need Key!',
        );
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Get configuration value
    return if !$DBObject->Prepare(
        SQL  => 'SELECT config_value, encrypted FROM zabbix_config WHERE config_key = ?',
        Bind => [ \$Param{Key} ],
    );

    my %Config;
    while (my @Row = $DBObject->FetchrowArray()) {
        %Config = (
            Value     => $Row[0] || '',
            Encrypted => $Row[1] || 0,
        );
    }

    # Decrypt value if needed
    if ($Config{Encrypted} && $Config{Value}) {
        eval {
            my $EncryptionObject = $Kernel::OM->Get('Kernel::System::EncryptionKey');
            $Config{Value} = $EncryptionObject->Decrypt(
                Data => $Config{Value},
            );
        };
        if ($@) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "MSSTLiteZabbix: Failed to decrypt config value for key '$Param{Key}': $@",
            );
            return;
        }
    }

    return $Config{Value};
}

=head2 SetZabbixConfig()

Set Zabbix configuration value by key

    my $Success = $PackageSetup->SetZabbixConfig(
        Key       => 'APIURL',
        Value     => 'https://zabbix.example.com/api_jsonrpc.php',
        Encrypted => 0,  # optional, default 0
    );

=cut

sub SetZabbixConfig {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    if ( !$Param{Key} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'MSSTLiteZabbix: Need Key!',
        );
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $Value    = $Param{Value} || '';
    my $Encrypted = $Param{Encrypted} || 0;

    # Encrypt value if needed
    if ($Encrypted && $Value) {
        eval {
            my $EncryptionObject = $Kernel::OM->Get('Kernel::System::EncryptionKey');
            $Value = $EncryptionObject->Encrypt(
                Data => $Value,
            );
        };
        if ($@) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "MSSTLiteZabbix: Failed to encrypt config value for key '$Param{Key}': $@",
            );
            return;
        }
    }

    # Check if key exists
    return if !$DBObject->Prepare(
        SQL  => 'SELECT id FROM zabbix_config WHERE config_key = ?',
        Bind => [ \$Param{Key} ],
    );

    my $ConfigID;
    while (my @Row = $DBObject->FetchrowArray()) {
        $ConfigID = $Row[0];
    }

    my $Success;
    if ($ConfigID) {
        # Update existing configuration
        $Success = $DBObject->Do(
            SQL => 'UPDATE zabbix_config SET config_value = ?, encrypted = ?, change_time = current_timestamp, change_by = ? WHERE id = ?',
            Bind => [ \$Value, \$Encrypted, \1, \$ConfigID ],
        );
    } else {
        # Insert new configuration
        $Success = $DBObject->Do(
            SQL => 'INSERT INTO zabbix_config (config_key, config_value, encrypted, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
            Bind => [ \$Param{Key}, \$Value, \$Encrypted, \1, \1 ],
        );
    }

    if ($Success) {
        # Clear cache
        $Kernel::OM->Get('Kernel::System::Cache')->Delete(
            Type => 'ZabbixConfig',
            Key  => $Param{Key},
        );
    }

    return $Success;
}


1;
