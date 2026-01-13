# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminApplicationLogs;

use strict;
use warnings;

use POSIX;
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
    my $JSONObject        = $Kernel::OM->Get('Kernel::System::JSON');
    my $ConfigObject      = $Kernel::OM->Get('Kernel::Config');
    my $GroupObject       = $Kernel::OM->Get('Kernel::System::Group');
    
    # Check permissions - admin or MSIAdmin group should have access
    my $HasAdminPermission = $GroupObject->PermissionCheck(
        UserID    => $Self->{UserID},
        GroupName => 'admin',
        Type      => 'rw',
    );
    
    my $HasMSIAdminPermission = $GroupObject->PermissionCheck(
        UserID    => $Self->{UserID},
        GroupName => 'MSIAdmin',
        Type      => 'rw',
    );

    if ( !$HasAdminPermission && !$HasMSIAdminPermission ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('You need admin or MSIAdmin permissions to access this module!'),
        );
    }

    # ------------------------------------------------------------ #
    # Test Syslog Connection (AJAX)
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'TestSyslogConnection' ) {

        # Get syslog server configuration directly from Config.pm
        my $SSHHost = $ConfigObject->Get('ApplicationLogs::SyslogSSHHost');
        my $SSHPort = $ConfigObject->Get('ApplicationLogs::SyslogSSHPort') || '22';
        my $SSHUser = $ConfigObject->Get('ApplicationLogs::SyslogSSHUser');
        my $SSHKeyPath = $ConfigObject->Get('ApplicationLogs::SyslogSSHKeyPath');

        my $Result = {
            Success => 0,
            Message => '',
        };

        if ( !$SSHHost || !$SSHUser || !$SSHKeyPath ) {
            $Result->{Message} = 'Syslog SSH configuration not found in Kernel/Config.pm. Please add ApplicationLogs::SyslogSSHHost, ApplicationLogs::SyslogSSHUser, and ApplicationLogs::SyslogSSHKeyPath settings to your Config.pm file.';
        }
        elsif ( !-f $SSHKeyPath ) {
            $Result->{Message} = Translatable('SSH key file not found: ') . $SSHKeyPath;
        }
        else {
            # Test SSH connection using key-based authentication
            my $TestResult = $Self->_TestSSHConnectionWithKey(
                Host     => $SSHHost,
                Port     => $SSHPort,
                User     => $SSHUser,
                KeyPath  => $SSHKeyPath,
                Service  => 'Syslog Server',
            );

            if ( $TestResult->{Success} ) {
                $Result->{Success} = 1;
                $Result->{Message} = Translatable('SSH connection to Syslog Server successful!');
            }
            else {
                $Result->{Message} = $TestResult->{ErrorMessage}
                    || Translatable('SSH connection failed. Please check your settings.');
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
    # Export Logs (Download Syslog File)
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'ExportLogs' ) {

        # Challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # Get date parameters from form
        my $StartDate = $ParamObject->GetParam( Param => 'StartDate' ) || '';
        my $EndDate   = $ParamObject->GetParam( Param => 'EndDate' ) || '';

        my $DownloadResult = $Self->_DownloadSyslogFile(
            StartDate => $StartDate,
            EndDate   => $EndDate,
        );

        if ( $DownloadResult->{Success} ) {
            # Return syslog ZIP file for download
            return $LayoutObject->Attachment(
                ContentType => 'application/zip',
                Content     => $DownloadResult->{FileContent},
                Filename    => $DownloadResult->{Filename},
                Type        => 'attachment',
                NoCache     => 1,
            );
        }
        else {
            # Show error and redirect back to form
            my $Output = $LayoutObject->Header();
            $Output .= $LayoutObject->NavigationBar();
            $Output .= $LayoutObject->Notify(
                Priority => 'Error',
                Info     => $DownloadResult->{ErrorMessage} || Translatable('Failed to download syslog file.'),
            );
            $Output .= $Self->_ShowForm();
            $Output .= $LayoutObject->Footer();
            return $Output;
        }
    }

    # ------------------------------------------------------------ #
    # Save - DISABLED: Configuration is managed in Config.pm
    # ------------------------------------------------------------ #
    # elsif ( $Self->{Subaction} eq 'Save' ) {
    #     # Configuration is now managed in Kernel/Config.pm
    #     # This subaction is disabled
    #     return $LayoutObject->Redirect(
    #         OP => "Action=AdminApplicationLogs"
    #     );
    # }

    # ------------------------------------------------------------ #
    # Show Form
    # ------------------------------------------------------------ #
    else {

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();

        $Output .= $Self->_ShowForm();
        $Output .= $LayoutObject->Footer();
        return $Output;
    }
}

sub _ShowForm {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # Load syslog server configuration directly from Config.pm
    $Param{SyslogSSHHost}     = $ConfigObject->Get('ApplicationLogs::SyslogSSHHost');
    $Param{SyslogSSHPort}     = $ConfigObject->Get('ApplicationLogs::SyslogSSHPort') || '22';
    $Param{SyslogSSHUser}     = $ConfigObject->Get('ApplicationLogs::SyslogSSHUser');
    $Param{SyslogSSHKeyPath}  = $ConfigObject->Get('ApplicationLogs::SyslogSSHKeyPath');

    # Check for missing configuration
    my @MissingFields;
    if (!$Param{SyslogSSHHost}) {
        push @MissingFields, 'ApplicationLogs::SyslogSSHHost';
        $Param{SyslogSSHHost} = 'NOT CONFIGURED';
    }
    if (!$Param{SyslogSSHUser}) {
        push @MissingFields, 'ApplicationLogs::SyslogSSHUser';
        $Param{SyslogSSHUser} = 'NOT CONFIGURED';
    }
    if (!$Param{SyslogSSHKeyPath}) {
        push @MissingFields, 'ApplicationLogs::SyslogSSHKeyPath';
        $Param{SyslogSSHKeyPath} = 'NOT CONFIGURED';
    }

    if (@MissingFields) {
        $Param{ConfigMissing} = 1;
        $Param{MissingFields} = join(', ', @MissingFields);
    }

    # Set default values for log paths from Config.pm
    $Param{SyslogLogPaths}    = $ConfigObject->Get('ApplicationLogs::SyslogLogPaths') || '/var/log/syslog';

    # Date range is set dynamically via form, not from Config.pm
    # These will be passed via hidden form fields when exporting
    $Param{StartDate} = $Param{StartDate} || '';
    $Param{EndDate}   = $Param{EndDate} || '';

    # Generate the form
    return $LayoutObject->Output(
        TemplateFile => 'AdminApplicationLogs',
        Data         => \%Param,
    );
}

sub _TestSSHConnection {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    my $Host     = $Param{Host} || '';
    my $Port     = $Param{Port} || '22';
    my $User     = $Param{User} || '';
    my $Password = $Param{Password} || '';
    my $Service  = $Param{Service} || 'Unknown';

    # Validate parameters
    if ( !$Host || !$User || !$Password ) {
        return {
            Success      => 0,
            ErrorMessage => 'Missing required SSH parameters (Host, User, and Password)',
        };
    }

    $LogObject->Log(
        Priority => 'info',
        Message  => "Testing SSH connection to $Service: $Host:$Port",
    );

    # Test actual SSH authentication with credentials using sshpass
    my $Success = 0;
    my $ErrorMessage = '';
    
    # Use sshpass to test SSH connection with password
    my $SSHCmd = "sshpass -p '$Password' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=no -p $Port $User\@$Host 'echo SUCCESS'";
    
    # Run the command and capture output
    my $Output = `$SSHCmd 2>&1`;
    my $ExitCode = $?;
    
    if ($ExitCode == 0 && $Output =~ /SUCCESS/) {
        $Success = 1;
    } else {
        # Analyze the error
        if ($Output =~ /Permission denied/) {
            $ErrorMessage = 'Authentication failed - incorrect password';
        } elsif ($Output =~ /No route to host|Connection refused/) {
            $ErrorMessage = 'Cannot connect to SSH service';
        } elsif ($Output =~ /Connection timed out/) {
            $ErrorMessage = 'Connection timeout';
        } elsif ($Output =~ /Host key verification failed/) {
            $ErrorMessage = 'Host key verification failed';
        } else {
            $ErrorMessage = $Output || 'SSH connection failed';
        }
    }
    
    if ($Success) {
        $LogObject->Log(
            Priority => 'info',
            Message  => "SSH connection to $Service ($Host:$Port) successful",
        );
        
        return {
            Success => 1,
        };
    }
    else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "SSH connection to $Service ($Host:$Port) failed: " . ($ErrorMessage || 'Connection failed'),
        );
        
        return {
            Success      => 0,
            ErrorMessage => $ErrorMessage || 'SSH connection failed',
        };
    }
}

sub _ExportApplicationLogs {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # Get configuration from Config.pm
    my $Config = {
        SyslogLogPaths => $ConfigObject->Get('ApplicationLogs::SyslogLogPaths') || '/var/log/syslog',
        StartDate      => $ConfigObject->Get('ApplicationLogs::StartDate'),
        EndDate        => $ConfigObject->Get('ApplicationLogs::EndDate'),
    };
    
    # Create temporary directory for logs
    my $TempDir = '/tmp/application_logs_' . time() . '_' . int(rand(1000));
    if ( !mkdir($TempDir, 0755) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to create temporary directory: $TempDir",
        );
        return {
            Success      => 0,
            ErrorMessage => 'Failed to create temporary directory for logs',
        };
    }

    my $Success = 1;
    my $ErrorMessage = '';

    # Skip local Znuny logs collection since they're already in syslog server
    $LogObject->Log(
        Priority => 'info',
        Message  => "Skipping local Znuny log collection - logs are centralized in syslog server",
    );

    # Collect Syslog logs
    if ( $Config->{SyslogLogPaths} ) {

        my $SyslogResult = $Self->_CollectSyslogLogs(
            Host      => $ConfigObject->Get('ApplicationLogs::SyslogSSHHost'),
            Port      => $ConfigObject->Get('ApplicationLogs::SyslogSSHPort') || '22',
            User      => $ConfigObject->Get('ApplicationLogs::SyslogSSHUser'),
            LogPaths  => $Config->{SyslogLogPaths},
            StartDate => $Config->{StartDate},
            EndDate   => $Config->{EndDate},
            TempDir   => $TempDir,
        );

        if ( !$SyslogResult->{Success} ) {
            # Don't fail entire export, just log the error
            $ErrorMessage .= "Syslog logs: " . ($SyslogResult->{ErrorMessage} || 'Unknown error') . " ";
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Syslog log collection failed, continuing: " . ($SyslogResult->{ErrorMessage} || 'Unknown error'),
            );
        }
    }

    # Check if we have any log files at all (including in subdirectories)
    my @LogFiles = `find '$TempDir' -type f -name "*.txt" -o -name "syslog*" -o -name "*.log" 2>/dev/null`;
    chomp(@LogFiles);
    if ( !@LogFiles ) {
        # No logs collected at all, clean up and return error
        system("rm -rf '$TempDir'");
        return {
            Success      => 0,
            ErrorMessage => "No logs could be collected from any source. " . $ErrorMessage,
        };
    }

    # Create ZIP file
    my $Timestamp = localtime();
    $Timestamp =~ s/[^\w\d]/_/g;
    my $ZipFilename = "application_logs_$Timestamp.zip";
    my $ZipPath = "/tmp/$ZipFilename";

    my $ZipCommand = "cd '$TempDir' && zip -q -r '$ZipPath' . 2>&1";
    my $ZipResult = `$ZipCommand`;
    my $ZipExitCode = $? >> 8;

    if ( $ZipExitCode != 0 ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to create ZIP file: $ZipResult",
        );
        system("rm -rf '$TempDir'");
        return {
            Success      => 0,
            ErrorMessage => 'Failed to create ZIP file',
        };
    }

    # Read ZIP file content
    my $FileContent;
    my $fh;
    if ( !open($fh, '<:raw', $ZipPath) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to read ZIP file: $ZipPath",
        );
        system("rm -rf '$TempDir'");
        unlink($ZipPath);
        return {
            Success      => 0,
            ErrorMessage => 'Failed to read ZIP file',
        };
    }

    local $/;
    $FileContent = <$fh>;
    close($fh);

    # Clean up
    system("rm -rf '$TempDir'");
    unlink($ZipPath);

    return {
        Success     => 1,
        FileContent => $FileContent,
        Filename    => $ZipFilename,
    };
}

sub _DownloadSyslogFile {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # Get SSH configuration directly from Config.pm
    my $Host = $ConfigObject->Get('ApplicationLogs::SyslogSSHHost');
    my $Port = $ConfigObject->Get('ApplicationLogs::SyslogSSHPort') || '22';
    my $User = $ConfigObject->Get('ApplicationLogs::SyslogSSHUser');
    my $KeyPath = $ConfigObject->Get('ApplicationLogs::SyslogSSHKeyPath');

    # Check if configuration exists
    if ( !$Host || !$User || !$KeyPath ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Syslog SSH configuration missing in Config.pm",
        );
        return {
            Success      => 0,
            ErrorMessage => 'Syslog SSH configuration not found. Please configure ApplicationLogs::SyslogSSHHost, ApplicationLogs::SyslogSSHUser, and ApplicationLogs::SyslogSSHKeyPath in Kernel/Config.pm',
        };
    }

    # For direct download, we expect only one log path (the main syslog file)
    my $LogPaths = $ConfigObject->Get('ApplicationLogs::SyslogLogPaths') || '/var/log/syslog';
    my @Paths = split(/\s*,\s*/, $LogPaths);

    # Use the first path (main syslog file)
    my $SyslogPath = $Paths[0];

    if ( !$SyslogPath ) {
        return {
            Success      => 0,
            ErrorMessage => 'No syslog path configured',
        };
    }

    $LogObject->Log(
        Priority => 'info',
        Message  => "Downloading syslog file from server $Host:$Port: $SyslogPath",
    );

    # Create temporary file path for direct download
    my $Timestamp = time();
    my $TempFile = "/tmp/syslog_download_$Timestamp.log";

    # Download the syslog file directly to temp file using SCP
    my $SCPCommand = "scp -i '$KeyPath' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -P $Port $User\@$Host:'$SyslogPath' '$TempFile' 2>&1";
    my $Result = `$SCPCommand`;
    my $ExitCode = $? >> 8;

    if ( $ExitCode != 0 ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to download syslog file from server: $Result",
        );
        unlink($TempFile) if -f $TempFile;
        return {
            Success      => 0,
            ErrorMessage => "Failed to download syslog file from server: $Result",
        };
    }

    # Check if file was downloaded successfully
    if ( !-f $TempFile ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Downloaded syslog file is missing: $TempFile",
        );
        return {
            Success      => 0,
            ErrorMessage => 'Downloaded syslog file is missing',
        };
    }

    # Log file size (empty files are OK for syslog)
    my $FileSize = -s $TempFile;
    $LogObject->Log(
        Priority => 'info',
        Message  => "Syslog file downloaded successfully: $TempFile ($FileSize bytes)",
    );

    # Apply date filtering if dates are specified (passed from form)
    my $StartDate = $Param{StartDate} || '';
    my $EndDate = $Param{EndDate} || '';

    if ( $StartDate && $EndDate ) {
        $LogObject->Log(
            Priority => 'info',
            Message  => "Applying date filter to syslog file: $StartDate to $EndDate",
        );

        $Self->_FilterLogsByDate(
            LogFile   => $TempFile,
            StartDate => $StartDate,
            EndDate   => $EndDate,
        );
    }

    # Categorize syslog by hostname
    $LogObject->Log(
        Priority => 'info',
        Message  => "Categorizing syslog entries by hostname",
    );

    # Create temp directory for categorized files
    my $CategorizedDir = "/tmp/syslog_categorized_" . time() . "_" . int(rand(1000));
    if ( !mkdir($CategorizedDir, 0755) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to create categorization directory: $CategorizedDir",
        );
        unlink($TempFile);
        return {
            Success      => 0,
            ErrorMessage => 'Failed to create categorization directory',
        };
    }

    # Parse syslog and categorize by hostname
    my %LogsByHost;
    my $LineCount = 0;

    if ( open(my $log_fh, '<', $TempFile) ) {
        while (my $line = <$log_fh>) {
            $LineCount++;
            my $hostname = 'unknown';

            # Try different syslog format patterns to extract hostname
            # Pattern 1: ISO 8601 with microseconds and timezone
            # Example: 2025-09-14T00:00:09.391671+00:00 syslog-dev systemd[1]:
            if ($line =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?[\+\-]\d{2}:\d{2}\s+(\S+)/) {
                $hostname = $1;
            }
            # Pattern 2: ISO 8601 without timezone
            # Example: 2025-09-14T00:00:09.391671 syslog-dev systemd[1]:
            elsif ($line =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?\s+(\S+)/) {
                $hostname = $1;
            }
            # Pattern 3: Traditional syslog format
            # Example: Jan 15 10:30:45 lsmp-db mysqld[5678]:
            elsif ($line =~ /^\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+(\S+)/) {
                $hostname = $1;
            }
            # Pattern 4: RFC 5424 format with priority
            # Example: <34>2025-09-14T00:00:09.391671+00:00 syslog-dev
            elsif ($line =~ /^<\d+>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?[\+\-]\d{2}:\d{2}\s+(\S+)/) {
                $hostname = $1;
            }

            # Store line in array for this hostname
            push @{$LogsByHost{$hostname}}, $line;
        }
        close($log_fh);

        $LogObject->Log(
            Priority => 'info',
            Message  => "Parsed $LineCount lines, found " . scalar(keys %LogsByHost) . " unique hostnames",
        );
    }
    else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to open syslog file for categorization: $TempFile",
        );
        rmdir($CategorizedDir);
        unlink($TempFile);
        return {
            Success      => 0,
            ErrorMessage => 'Failed to open syslog file for categorization',
        };
    }

    # Write separate files for each hostname
    for my $hostname (sort keys %LogsByHost) {
        my $SafeHostname = $hostname;
        # Sanitize hostname for use as filename (remove/replace problematic characters)
        $SafeHostname =~ s/[^\w\-\.]/_/g;
        $SafeHostname = 'unknown' if !$SafeHostname;

        my $HostFile = "$CategorizedDir/$SafeHostname.log";

        if ( open(my $out_fh, '>', $HostFile) ) {
            for my $line (@{$LogsByHost{$hostname}}) {
                print $out_fh $line;
            }
            close($out_fh);

            $LogObject->Log(
                Priority => 'info',
                Message  => "Created categorized file: $SafeHostname.log with " . scalar(@{$LogsByHost{$hostname}}) . " lines",
            );
        }
        else {
            $LogObject->Log(
                Priority => 'warning',
                Message  => "Failed to create categorized file for hostname: $hostname",
            );
        }
    }

    # Clean up original temp file
    unlink($TempFile);

    # Create ZIP file containing all categorized files
    my $ZipFilename = "syslog_categorized_" . POSIX::strftime('%Y%m%d_%H%M%S', localtime()) . ".zip";
    my $ZipPath = "/tmp/$ZipFilename";

    my $ZipCommand = "cd '$CategorizedDir' && zip -q -r '$ZipPath' . 2>&1";
    my $ZipResult = `$ZipCommand`;
    my $ZipExitCode = $? >> 8;

    if ( $ZipExitCode != 0 ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to create ZIP file: $ZipResult",
        );
        system("rm -rf '$CategorizedDir'");
        return {
            Success      => 0,
            ErrorMessage => 'Failed to create ZIP file',
        };
    }

    # Read ZIP file content
    my $FileContent;
    my $zip_fh;
    if ( !open($zip_fh, '<:raw', $ZipPath) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to read ZIP file: $ZipPath",
        );
        system("rm -rf '$CategorizedDir'");
        unlink($ZipPath);
        return {
            Success      => 0,
            ErrorMessage => 'Failed to read ZIP file',
        };
    }

    local $/;
    $FileContent = <$zip_fh>;
    close($zip_fh);

    # Clean up
    system("rm -rf '$CategorizedDir'");
    unlink($ZipPath);

    $LogObject->Log(
        Priority => 'info',
        Message  => "Successfully created syslog ZIP archive: $ZipFilename (" . length($FileContent) . " bytes)",
    );

    return {
        Success     => 1,
        FileContent => $FileContent,
        Filename    => $ZipFilename,
    };
}

sub _CollectZnunyLogs {
    my ( $Self, $TempDir ) = @_;
    
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    $LogObject->Log(
        Priority => 'info',
        Message  => "Collecting local Znuny logs",
    );
    
    # Define Znuny log file patterns - use actual Znuny log naming
    my @LogPaths = (
        '/opt/znuny-6.5.15/var/log/Daemon/*ERR.log',
        '/opt/znuny-6.5.15/var/log/Daemon/*OUT.log', 
        '/opt/znuny-6.5.15/var/log/*.log',
        '/opt/znuny-6.5.15/var/log/*.txt',
    );
    
    # Try Apache logs but handle permission errors gracefully
    my @OptionalLogs = (
        '/var/log/apache2/error.log',
        '/var/log/apache2/access.log',
    );
    
    my $AllLogs = '';
    my $FilesFound = 0;
    
    # Process required Znuny logs
    for my $Pattern (@LogPaths) {
        my @Files = glob($Pattern);
        for my $File (@Files) {
            if (-r $File) {
                $FilesFound++;
                $AllLogs .= "\n" . "="x50 . "\n";
                $AllLogs .= "LOG FILE: $File\n";
                $AllLogs .= "="x50 . "\n";
                
                # Read last 1000 lines to avoid huge files
                my $Content = `tail -n 1000 '$File' 2>/dev/null`;
                $AllLogs .= $Content || "[Empty or unreadable]\n";
            }
        }
    }
    
    # Process optional logs (Apache, etc) - don't fail if permission denied
    for my $File (@OptionalLogs) {
        if (-r $File) {
            $FilesFound++;
            $AllLogs .= "\n" . "="x50 . "\n";
            $AllLogs .= "LOG FILE: $File (Optional)\n";
            $AllLogs .= "="x50 . "\n";
            
            my $Content = `tail -n 500 '$File' 2>/dev/null`;
            $AllLogs .= $Content || "[Empty or unreadable]\n";
        } else {
            # Add note about optional file being inaccessible
            $AllLogs .= "\n" . "="x50 . "\n";
            $AllLogs .= "LOG FILE: $File (Optional - Permission Denied)\n";
            $AllLogs .= "="x50 . "\n";
            $AllLogs .= "This log file could not be accessed due to permission restrictions.\n";
        }
    }
    
    # Always create a log file even if no files found, for debugging
    if ($FilesFound == 0) {
        $AllLogs = "ZNUNY LOG COLLECTION DEBUG\n" . "="x50 . "\n";
        $AllLogs .= "No readable log files found.\n";
        $AllLogs .= "Checked patterns:\n";
        for my $Pattern (@LogPaths) {
            $AllLogs .= "  - $Pattern\n";
            my @Files = glob($Pattern);
            if (@Files) {
                for my $File (@Files) {
                    my $readable = -r $File ? "READABLE" : "NO PERMISSION";
                    $AllLogs .= "    Found: $File ($readable)\n";
                }
            } else {
                $AllLogs .= "    No files match this pattern\n";
            }
        }
        $AllLogs .= "\nOptional files checked:\n";
        for my $File (@OptionalLogs) {
            my $readable = -r $File ? "READABLE" : "NO PERMISSION";
            my $exists = -e $File ? "EXISTS" : "MISSING";
            $AllLogs .= "  - $File ($exists, $readable)\n";
        }
    }
    
    # Write to temp file
    my $OutputFile = "$TempDir/znuny_logs.txt";
    my $fh;
    if (!open($fh, '>', $OutputFile)) {
        return {
            Success => 0,
            ErrorMessage => "Cannot write Znuny logs to $OutputFile: $!",
        };
    }
    
    print $fh $AllLogs;
    close($fh);
    
    $LogObject->Log(
        Priority => 'info',
        Message  => "Znuny logs collected successfully: $FilesFound files",
    );
    
    return {
        Success => 1,
        Message => "Znuny logs collected: $FilesFound files" . ($FilesFound == 0 ? " (debug info included)" : ""),
    };
}


sub _CollectSyslogLogs {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $Host      = $Param{Host} || $ConfigObject->Get('ApplicationLogs::SyslogSSHHost');
    my $Port      = $Param{Port} || $ConfigObject->Get('ApplicationLogs::SyslogSSHPort') || '22';
    my $User      = $Param{User} || $ConfigObject->Get('ApplicationLogs::SyslogSSHUser');
    my $KeyPath   = $ConfigObject->Get('ApplicationLogs::SyslogSSHKeyPath');
    my $LogPaths  = $Param{LogPaths} || '';
    my $StartDate = $Param{StartDate} || '';
    my $EndDate   = $Param{EndDate} || '';
    my $TempDir   = $Param{TempDir} || '';

    # Check if configuration exists
    if ( !$Host || !$User || !$KeyPath ) {
        return {
            Success      => 0,
            ErrorMessage => 'Syslog SSH configuration missing in Config.pm',
        };
    }

    # Create syslog directory
    my $ServiceDir = "$TempDir/syslog";
    if ( !mkdir($ServiceDir, 0755) ) {
        return {
            Success      => 0,
            ErrorMessage => "Failed to create directory for syslog logs",
        };
    }

    # Split multiple log paths
    my @Paths = split(/\s*,\s*/, $LogPaths);

    for my $Path (@Paths) {
        next if !$Path;

        $LogObject->Log(
            Priority => 'info',
            Message  => "Collecting syslog logs from $Host:$Port:$Path (Date range: $StartDate to $EndDate)",
        );

        # Download file from remote server using SCP
        my $SCPCommand = "scp -i '$KeyPath' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -P $Port $User\@$Host:'$Path' '$ServiceDir/' 2>&1";
        my $Result = `$SCPCommand`;
        my $ExitCode = $? >> 8;

        if ( $ExitCode != 0 ) {
            $LogObject->Log(
                Priority => 'warning',
                Message  => "Failed to download syslog file from server ($Path): $Result",
            );
            # Continue with other paths - don't fail entire collection
        }
        else {
            # Apply date filtering if dates are specified
            if ( $StartDate && $EndDate ) {
                $Self->_FilterLogsByDate(
                    LogFile   => "$ServiceDir/" . basename($Path),
                    StartDate => $StartDate,
                    EndDate   => $EndDate,
                );
            }
        }
    }

    # Check if any files were collected
    my $FileCount = `find '$ServiceDir' -type f | wc -l`;
    chomp($FileCount);

    if ( $FileCount && $FileCount > 0 ) {
        $LogObject->Log(
            Priority => 'info',
            Message  => "Successfully collected $FileCount syslog log files",
        );
        return { Success => 1 };
    }
    else {
        $LogObject->Log(
            Priority => 'warning',
            Message  => "No syslog log files collected",
        );
        return {
            Success      => 0,
            ErrorMessage => "No log files found or accessible on syslog server",
        };
    }
}

sub _FilterLogsByDate {
    my ( $Self, %Param ) = @_;

    my $LogFile   = $Param{LogFile} || '';
    my $StartDate = $Param{StartDate} || '';
    my $EndDate   = $Param{EndDate} || '';

    return if !$LogFile || !-f $LogFile;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    $LogObject->Log(
        Priority => 'info',
        Message  => "Filtering log file $LogFile by date range: $StartDate to $EndDate",
    );

    # Create temporary file for filtered content
    my $TempFile = "$LogFile.filtered";

    open my $in_fh, '<', $LogFile or return;
    open my $out_fh, '>', $TempFile or do { close $in_fh; return; };

    my $FilteredLines = 0;
    my $TotalLines = 0;

    while ( my $line = <$in_fh> ) {
        $TotalLines++;

        # Try to extract date from log line
        # First try ISO 8601 format: "2025-09-14T00:00:09.391671+00:00"
        if ( $line =~ /^(\d{4})-(\d{2})-(\d{2})T/ ) {
            my $year = $1;
            my $month = $2;
            my $day = $3;

            my $log_date = sprintf('%04d-%02d-%02d', $year, $month, $day);

            # Check if log date is within range
            if ( $log_date ge $StartDate && $log_date le $EndDate ) {
                print $out_fh $line;
                $FilteredLines++;
            }
        }
        # Fallback to old syslog format: "Jan 15 10:30:45 hostname program: message"
        elsif ( $line =~ /^(\w{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})/ ) {
            my $month_name = $1;
            my $day = $2;
            my $hour = $3;
            my $min = $4;
            my $sec = $5;

            # Convert month name to number
            my %months = (
                Jan => 1, Feb => 2, Mar => 3, Apr => 4, May => 5, Jun => 6,
                Jul => 7, Aug => 8, Sep => 9, Oct => 10, Nov => 11, Dec => 12
            );

            my $month = $months{$month_name};
            my $current_year = (localtime())[5] + 1900;  # Get current year

            if ( $month ) {
                my $log_date = sprintf('%04d-%02d-%02d', $current_year, $month, $day);

                # Check if log date is within range
                if ( $log_date ge $StartDate && $log_date le $EndDate ) {
                    print $out_fh $line;
                    $FilteredLines++;
                }
            }
            else {
                # If we can't parse the date, include the line
                print $out_fh $line;
                $FilteredLines++;
            }
        }
        else {
            # If line doesn't match expected format, include it
            print $out_fh $line;
            $FilteredLines++;
        }
    }

    close $in_fh;
    close $out_fh;

    # Replace original file with filtered version
    if ( $FilteredLines > 0 ) {
        system("mv '$TempFile' '$LogFile'");
        $LogObject->Log(
            Priority => 'info',
            Message  => "Filtered $LogFile: $TotalLines total lines, $FilteredLines matching date range",
        );
    }
    else {
        unlink $TempFile;
        $LogObject->Log(
            Priority => 'warning',
            Message  => "No lines matched date range in $LogFile, keeping original file",
        );
    }

    return 1;
}

sub _TestSSHConnectionWithKey {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my $Host     = $Param{Host} || '';
    my $Port     = $Param{Port} || '22';
    my $User     = $Param{User} || '';
    my $KeyPath  = $Param{KeyPath} || '';
    my $Service  = $Param{Service} || 'Unknown';

    # Validate parameters
    if ( !$Host || !$User || !$KeyPath ) {
        return {
            Success      => 0,
            ErrorMessage => 'Missing required SSH parameters (Host, User, and KeyPath)',
        };
    }

    if ( !-f $KeyPath ) {
        return {
            Success      => 0,
            ErrorMessage => 'SSH key file not found: ' . $KeyPath,
        };
    }

    # Check SSH key file permissions
    my $mode = (stat($KeyPath))[2] & 07777;
    if ( $mode != 0600 && $mode != 0640 && $mode != 0400 ) {
        return {
            Success      => 0,
            ErrorMessage => sprintf('SSH key file has incorrect permissions (%04o). Private keys must have 600, 640, or 400 permissions. Run: chmod 640 %s', $mode, $KeyPath),
        };
    }

    $LogObject->Log(
        Priority => 'info',
        Message  => "Testing SSH connection to $Service: $Host:$Port using key $KeyPath",
    );

    # Test SSH connection with key
    my $Success = 0;
    my $ErrorMessage = '';

    # Use SSH with key authentication
    my $SSHCmd = "ssh -i '$KeyPath' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -p $Port $User\@$Host 'echo SUCCESS'";

    # Run the command and capture output
    my $Output = `$SSHCmd 2>&1`;
    my $ExitCode = $? >> 8;

    if ($ExitCode == 0 && $Output =~ /SUCCESS/) {
        $Success = 1;
    } else {
        # Analyze the error
        if ($Output =~ /bad permissions|Permissions \d+ for .* are too open/) {
            $ErrorMessage = 'SSH key file has incorrect permissions. Private key must have 600 permissions (owner read/write only)';
        } elsif ($Output =~ /Load key.*invalid format/) {
            $ErrorMessage = 'SSH key file format error or corrupted';
        } elsif ($Output =~ /Permission denied/) {
            $ErrorMessage = 'Authentication failed - SSH key not authorized or incorrect key';
        } elsif ($Output =~ /No route to host|Connection refused/) {
            $ErrorMessage = 'Cannot connect to SSH service';
        } elsif ($Output =~ /Connection timed out/) {
            $ErrorMessage = 'Connection timeout';
        } elsif ($Output =~ /Host key verification failed/) {
            $ErrorMessage = 'Host key verification failed';
        } elsif ($Output =~ /No such file or directory/) {
            $ErrorMessage = 'SSH key file not found';
        } else {
            $ErrorMessage = $Output || 'SSH connection failed';
        }
    }

    if ($Success) {
        $LogObject->Log(
            Priority => 'info',
            Message  => "SSH connection to $Service ($Host:$Port) successful using key",
        );

        return {
            Success => 1,
        };
    }
    else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "SSH connection to $Service ($Host:$Port) failed: " . ($ErrorMessage || 'Connection failed'),
        );

        return {
            Success      => 0,
            ErrorMessage => $ErrorMessage || 'SSH connection failed',
        };
    }
}

1;