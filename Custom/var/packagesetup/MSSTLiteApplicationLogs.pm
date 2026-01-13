# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package var::packagesetup::MSSTLiteApplicationLogs;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Cache',
);

=head1 NAME

var::packagesetup::MSSTLiteApplicationLogs - Code to execute during ApplicationLogs integration package installation

=head1 DESCRIPTION

All code to execute during ApplicationLogs integration package installation and uninstallation.
Handles adding ApplicationLogs configuration to Config.pm.

=head1 PUBLIC INTERFACE

=head2 new()

Create an object

    my $CodeObject = var::packagesetup::MSSTLiteApplicationLogs->new();

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
        Message  => 'MSSTLiteApplicationLogs: Starting ApplicationLogs integration installation',
    );

    # Add ApplicationLogs configuration to Config.pm
    $Self->_AddApplicationLogsConfigToConfigPm();

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteApplicationLogs: ApplicationLogs integration installation completed',
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
        Message  => 'MSSTLiteApplicationLogs: Starting ApplicationLogs integration uninstallation',
    );

    # Note: We don't remove the configuration from Config.pm on uninstall
    # to preserve user settings if they reinstall later

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteApplicationLogs: ApplicationLogs integration uninstallation completed',
    );

    return 1;
}

=head2 _AddApplicationLogsConfigToConfigPm()

Add ApplicationLogs configuration entries to Config.pm file

=cut

sub _AddApplicationLogsConfigToConfigPm {
    my ( $Self, %Param ) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $Home = $ConfigObject->Get('Home');
    my $ConfigFile = "$Home/Kernel/Config.pm";

    $LogObject->Log(
        Priority => 'notice',
        Message  => "MSSTLiteApplicationLogs: Adding ApplicationLogs configuration to Config.pm",
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
            Message  => "MSSTLiteApplicationLogs: Cannot read Config.pm: $!",
        );
        return;
    }

    # Check if ApplicationLogs configuration already exists
    if ($ConfigContent =~ /ApplicationLogs::SyslogSSHHost/) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLiteApplicationLogs: ApplicationLogs configuration already exists in Config.pm",
        );
        return 1;
    }

    # Prepare the ApplicationLogs configuration block
    my $ApplicationLogsConfig = q{
    # ---------------------------------------------------- #
    # Application Logs Configuration                       #
    # ---------------------------------------------------- #
    # Configure these settings for remote log collection
    # These values are used for SSH access to remote syslog servers

    # Syslog Server SSH Host (hostname or IP address)
    $Self->{'ApplicationLogs::SyslogSSHHost'}      = '10.23.1.74';

    # Syslog Server SSH Port
    $Self->{'ApplicationLogs::SyslogSSHPort'}      = '22';

    # Syslog Server SSH Username
    $Self->{'ApplicationLogs::SyslogSSHUser'}      = 'root';

    # Syslog Server SSH Key Path
    $Self->{'ApplicationLogs::SyslogSSHKeyPath'}   = '/opt/znuny-6.5.15/keys/syslog_server.key';

    # Syslog Server Log Paths (comma-separated)
    $Self->{'ApplicationLogs::SyslogLogPaths'}     = '/var/log/syslog';

    # ---------------------------------------------------- #
    # End of Application Logs Configuration                #
    # ---------------------------------------------------- #
};

    # Find the position to insert (before "return 1;" in the Load subroutine)
    if ($ConfigContent =~ /(    # -{10,}.*?end of your own config.*?# -{10,}.*?)(    return 1;)/s) {
        my $BeforeReturn = $1;
        my $ReturnStatement = $2;
        my $InsertPoint = $BeforeReturn . $ReturnStatement;
        my $NewContent = $ApplicationLogsConfig . "\n" . $InsertPoint;
        $ConfigContent =~ s/\Q$InsertPoint\E/$NewContent/;

        # Write the updated content back to Config.pm
        if (open(my $FH, '>', $ConfigFile)) {
            print $FH $ConfigContent;
            close($FH);

            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLiteApplicationLogs: Successfully added ApplicationLogs configuration to Config.pm",
            );

            # Clear config cache to pick up new settings
            $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
                Type => 'Config',
            );

            return 1;
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLiteApplicationLogs: Cannot write to Config.pm: $!",
            );
            return;
        }
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLiteApplicationLogs: Cannot find proper insertion point in Config.pm",
        );
        return;
    }
}

1;