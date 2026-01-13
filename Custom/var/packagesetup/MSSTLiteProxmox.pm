# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package var::packagesetup::MSSTLiteProxmox;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Cache',
    'Kernel::Config',
);

=head1 NAME

var::packagesetup::MSSTLiteProxmox - Code to execute during MSI Support Remote Access/Proxmox integration package installation

=head1 DESCRIPTION

All code to execute during MSI Support Remote Access/Proxmox integration package installation and uninstallation.
Handles adding Proxmox API configuration to Config.pm.

=head1 PUBLIC INTERFACE

=head2 new()

Create an object

    my $CodeObject = var::packagesetup::MSSTLiteProxmox->new();

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
        Message  => 'MSSTLiteProxmox: Starting MSI Support Remote Access/Proxmox integration installation',
    );

    # Add Proxmox configuration to Config.pm
    $Self->_AddProxmoxConfigToConfigPm();

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteProxmox: MSI Support Remote Access/Proxmox integration installation completed',
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
        Message  => 'MSSTLiteProxmox: MSI Support Remote Access/Proxmox integration uninstallation completed',
    );

    # Note: We don't remove the configuration from Config.pm on uninstall
    # to preserve user settings if they reinstall later

    return 1;
}

=head2 _AddProxmoxConfigToConfigPm()

Add Proxmox configuration entries to Config.pm file

=cut

sub _AddProxmoxConfigToConfigPm {
    my ( $Self, %Param ) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    my $Home = $ConfigObject->Get('Home');
    my $ConfigFile = "$Home/Kernel/Config.pm";
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => "MSSTLiteProxmox: Adding MSI Support Remote Access/Proxmox configuration to Config.pm",
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
            Message  => "MSSTLiteProxmox: Cannot read Config.pm: $!",
        );
        return;
    }
    
    # Check if Proxmox configuration already exists
    if ($ConfigContent =~ /MSISupportRemoteAccessConfiguration::ProxmoxHost/) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLiteProxmox: MSI Support Remote Access configuration already exists in Config.pm",
        );
        return 1;
    }
    
    # Prepare the Proxmox configuration block
    my $ProxmoxConfig = q{
    # ---------------------------------------------------- #
    # MSI Support Remote Access / Proxmox Configuration   #
    # ---------------------------------------------------- #
    # Configure these settings for Proxmox API access
    # These values are required for container control functionality
    
    # Proxmox API Host (hostname or IP address)
    $Self->{'MSISupportRemoteAccessConfiguration::ProxmoxHost'}        = '';  # e.g., 'proxmox.example.com' or '192.168.1.100'
    
    # Proxmox API Port (default: 8006)
    $Self->{'MSISupportRemoteAccessConfiguration::ProxmoxPort'}        = '8006';
    
    # Proxmox API Token ID (format: user@realm!token-name)
    $Self->{'MSISupportRemoteAccessConfiguration::ProxmoxTokenID'}     = '';  # e.g., 'root@pam!api-token'
    
    # Proxmox API Token Secret
    $Self->{'MSISupportRemoteAccessConfiguration::ProxmoxTokenSecret'} = '';  # e.g., 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    
    # Note: ContainerNode and ContainerID are configured via the web interface
    # and stored in SysConfig, not here in Config.pm
    
    # ---------------------------------------------------- #
    # End of MSI Support Remote Access Configuration      #
    # ---------------------------------------------------- #
};
    
    # Find the position to insert (before "return 1;" in the Load subroutine)
    # We want to insert after Zabbix configuration if it exists, or before the end marker
    my $InsertPosition;
    
    # First try to insert after Zabbix configuration if it exists
    if ($ConfigContent =~ /(    # -{10,}.*?End of Zabbix Integration Configuration.*?# -{10,}.*?\n)/s) {
        my $AfterZabbix = $1;
        $ConfigContent =~ s/\Q$AfterZabbix\E/$AfterZabbix$ProxmoxConfig\n/;
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLiteProxmox: Inserted MSI Support Remote Access configuration after Zabbix configuration",
        );
    }
    # Otherwise insert before the "end of your own config" marker
    elsif ($ConfigContent =~ /(    # -{10,}.*?end of your own config.*?# -{10,}.*?)(    return 1;)/s) {
        my $BeforeReturn = $1;
        my $ReturnStatement = $2;
        my $InsertPoint = $BeforeReturn . $ReturnStatement;
        my $NewContent = $ProxmoxConfig . "\n" . $InsertPoint;
        $ConfigContent =~ s/\Q$InsertPoint\E/$NewContent/;
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLiteProxmox: Inserted MSI Support Remote Access configuration before end marker",
        );
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLiteProxmox: Cannot find proper insertion point in Config.pm",
        );
        return;
    }
    
    # Write the updated content back to Config.pm
    if (open(my $FH, '>', $ConfigFile)) {
        print $FH $ConfigContent;
        close($FH);
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLiteProxmox: Successfully added MSI Support Remote Access configuration to Config.pm",
        );
        
        # Clear config cache to pick up new settings
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
            Type => 'Config',
        );
        
        return 1;
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLiteProxmox: Cannot write to Config.pm: $!",
        );
        return;
    }
}

1;