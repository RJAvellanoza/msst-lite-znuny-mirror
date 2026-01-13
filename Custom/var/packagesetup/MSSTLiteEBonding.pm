# --
# Copyright (C) 2025 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package var::packagesetup::MSSTLiteEBonding;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::Log',
);

=head1 NAME

var::packagesetup::MSSTLiteEBonding - Code to execute during eBonding ServiceNow integration package installation

=head1 DESCRIPTION

All code to execute during eBonding ServiceNow integration package installation and uninstallation.
Handles automatic addition of configuration entries to Config.pm file.

=head1 PUBLIC INTERFACE

=head2 new()

Create an object

    my $CodeObject = var::packagesetup::MSSTLiteEBonding->new();

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
        Message  => 'MSSTLiteEBonding: Starting eBonding ServiceNow integration installation',
    );

    # Add eBonding configuration to Config.pm
    $Self->_AddEBondingConfigToConfigPm();

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteEBonding: eBonding ServiceNow integration installation completed',
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
        Message  => 'MSSTLiteEBonding: Starting eBonding ServiceNow integration uninstallation',
    );

    # Configuration entries will remain in Config.pm for manual removal by administrator

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteEBonding: eBonding ServiceNow integration uninstallation completed',
    );

    return 1;
}

=head2 _AddEBondingConfigToConfigPm()

Add eBonding ServiceNow configuration entries to Config.pm file

=cut

sub _AddEBondingConfigToConfigPm {
    my ( $Self, %Param ) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $Home = $ConfigObject->Get('Home');
    my $ConfigFile = "$Home/Kernel/Config.pm";

    $LogObject->Log(
        Priority => 'notice',
        Message  => "MSSTLiteEBonding: Adding eBonding ServiceNow configuration to Config.pm",
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
            Message  => "MSSTLiteEBonding: Cannot read Config.pm: $!",
        );
        return;
    }

    # Check if eBonding configuration already exists and remove it
    if ($ConfigContent =~ /EBondingIntegration::APIURL/) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLiteEBonding: Removing old eBonding configuration to update it",
        );

        # Remove the old block completely (tested pattern that works)
        $ConfigContent =~ s/\n\n    # -+\s*#\n    # eBonding ServiceNow Integration Configuration.*?# End of eBonding ServiceNow Integration Configuration.*?# -+\s*#\n\n//s;
    }

    # Prepare the eBonding configuration block
    my $EBondingConfig = <<'END_CONFIG';

    # ---------------------------------------------------- #
    # eBonding ServiceNow Integration Configuration       #
    # ---------------------------------------------------- #
    # Configure these settings with your ServiceNow API credentials
    # These values are required for the eBonding integration to work

    # Enable/Disable eBonding ServiceNow Integration (1=enabled, 0=disabled)
    # NOTE: This is now controlled via System Configuration web interface
    # $Self->{'EBondingIntegration::Enabled'}     = '1';

    # ServiceNow API URL (e.g., 'https://your-instance.service-now.com/api/now/table/u_inbound_incident')
    $Self->{'EBondingIntegration::APIURL'}      = 'https://cmsosnowdev.service-now.com/api/now/table/u_inbound_incident';

    # ServiceNow API Username
    $Self->{'EBondingIntegration::APIUser'}     = 'lsmp.integration.dev';

    # ServiceNow API Password
    $Self->{'EBondingIntegration::APIPassword'} = 'Hw]HZR35h^hUyez+{LEZqwnNw1z.2x@eSmRW<1,.';

    # ---------------------------------------------------- #
    # End of eBonding ServiceNow Integration Configuration #
    # ---------------------------------------------------- #
END_CONFIG

    # Find the position to insert (before "return 1;" in the Load subroutine)
    if ($ConfigContent =~ /(    # -{10,}.*?end of your own config.*?# -{10,}.*?)(    return 1;)/s) {
        my $BeforeReturn = $1;
        my $ReturnStatement = $2;
        my $InsertPoint = $BeforeReturn . $ReturnStatement;
        my $NewContent = $EBondingConfig . "\n" . $InsertPoint;
        $ConfigContent =~ s/\Q$InsertPoint\E/$NewContent/;

        # Write the updated content back to Config.pm
        if (open(my $FH, '>', $ConfigFile)) {
            print $FH $ConfigContent;
            close($FH);

            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLiteEBonding: Successfully added eBonding ServiceNow configuration to Config.pm",
            );

            # Clear config cache to pick up new settings
            $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
                Type => 'Config',
            );

            return 1;
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLiteEBonding: Cannot write to Config.pm: $!",
            );
            return;
        }
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLiteEBonding: Cannot find proper insertion point in Config.pm",
        );
        return;
    }
}

1;
