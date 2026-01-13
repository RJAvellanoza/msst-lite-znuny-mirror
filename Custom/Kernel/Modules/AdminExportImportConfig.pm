# --
# Copyright (C) 2025 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminExportImportConfig;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);
use JSON::XS;

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
    my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    
    # Check permissions - admin or MSIAdmin group only (NOCAdmin excluded)
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

    # Get ExportImportConfig system module
    my $ExportImportConfigObject = $Kernel::OM->Get('Kernel::System::ExportImportConfig');
    
    if ( !$ExportImportConfigObject ) {
        return $Self->_ShowMainPage(
            SystemModuleNotAvailable => 1,
            Warning => Translatable('The ExportImportConfig system module is not available.'),
        );
    }

    # ------------------------------------------------------------ #
    # AJAX Progress Tracking
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'GetProgress' ) {
        # Security: Add CSRF protection for AJAX endpoint
        my $ChallengeToken = $ParamObject->GetParam( Param => 'ChallengeToken' );
        
        # Validate CSRF token
        if ( !$ChallengeToken || !$LayoutObject->ValidateChallengeToken( ChallengeToken => $ChallengeToken ) ) {
            return $LayoutObject->Attachment(
                ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
                Content     => JSON::XS->new->encode({
                    Error => 'Invalid or missing CSRF token',
                    Status => 'error',
                }),
                Type        => 'inline',
                NoCache     => 1,
            );
        }
        
        my $ProgressID = $ParamObject->GetParam( Param => 'ProgressID' );
        
        my $Progress = $ExportImportConfigObject->GetProgress(
            ProgressID => $ProgressID,
        );
        
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => JSON::XS->new->encode($Progress),
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # ------------------------------------------------------------ #
    # Export Configuration
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Export' ) {
        $LayoutObject->ChallengeTokenCheck();

        # Log the export operation
        $LogObject->Log(
            Priority => 'notice',
            Message  => "User $Self->{UserID} initiated configuration export",
        );

        # Perform the export (exports all configured components)
        my $Result = $ExportImportConfigObject->ExportConfiguration(
            UserID => $Self->{UserID},
        );

        if ( !$Result || !$Result->{Success} ) {
            my $ErrorMessage = $Result->{Message} || Translatable('Export failed due to an unknown error.');
            
            $LogObject->Log(
                Priority => 'error',
                Message  => "Configuration export failed for user $Self->{UserID}: $ErrorMessage",
            );
            
            return $Self->_ShowMainPage(
                ExportError => $ErrorMessage,
            );
        }

        # Read the compressed file for download
        my $MainObject = $Kernel::OM->Get('Kernel::System::Main');
        my $FileContent = $MainObject->FileRead(
            Location => $Result->{FilePath},
            Mode     => 'binmode',
        );

        if ( !$FileContent ) {
            return $Self->_ShowMainPage(
                ExportError => Translatable('Failed to read exported file.'),
            );
        }

        # Send the file to the browser for download
        return $LayoutObject->Attachment(
            Filename    => $Result->{FileName},
            ContentType => 'application/gzip',
            Content     => ${$FileContent},  # Dereference the scalar ref
            Type        => 'attachment',
        );
    }

    # ------------------------------------------------------------ #
    # Import Configuration
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Import' ) {
        $LayoutObject->ChallengeTokenCheck();

        # Get upload file using GetUploadAll - this actually handles binary correctly
        my %UploadStuff = $ParamObject->GetUploadAll(
            Param => 'ImportFile',
        );
        
        if ( !%UploadStuff || !$UploadStuff{Filename} ) {
            return $Self->_ShowMainPage(
                ImportError => Translatable('Please select an exported configuration file to import.'),
            );
        }
        
        my %UploadData = (
            Filename => $UploadStuff{Filename},
            Content  => $UploadStuff{Content},
        );
        
        if ( !$UploadData{Content} ) {
            return $Self->_ShowMainPage(
                ImportError => Translatable('Failed to read uploaded file content.'),
            );
        }

        # Validate file extension (accept both .gz and .gzip)
        $LogObject->Log(
            Priority => 'info',
            Message  => "Upload filename: '$UploadData{Filename}'",
        );
        if ( $UploadData{Filename} !~ /\.(gz|gzip)$/i ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Import failed: Invalid file extension for '$UploadData{Filename}'",
            );
            return $Self->_ShowMainPage(
                ImportError => Translatable('Invalid file extension. Please upload a .gz or .gzip exported configuration file.'),
            );
        }

        # Log the import operation
        $LogObject->Log(
            Priority => 'notice',
            Message  => "User $Self->{UserID} initiated configuration import from file: $UploadData{Filename}",
        );

        # Write temp file for import
        my $MainObject = $Kernel::OM->Get('Kernel::System::Main');
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
        my $TempDir = $ConfigObject->Get('TempDir');
        
        # Security: Sanitize filename and prevent path traversal
        my $RandomID = $MainObject->GenerateRandomString(
            Length => 32,
        );
        my $TempFile = "$TempDir/import_${RandomID}.gz";
        
        # The content from GetUploadAll might be in UTF-8, we need raw bytes
        # Ensure we have binary content
        my $BinaryContent = $UploadData{Content};
        
        # If content looks like it's been UTF-8 encoded, decode it back to bytes
        if (utf8::is_utf8($BinaryContent)) {
            utf8::encode($BinaryContent);
        }
        
        # Security: Validate file content before writing (check magic numbers for gzip)
        my $FileHeader = substr($BinaryContent, 0, 2);
        my $HeaderHex = unpack('H*', $FileHeader);
        $LogObject->Log(
            Priority => 'info',
            Message  => "Upload file header (hex): $HeaderHex, size: " . length($BinaryContent) . " bytes",
        );
        if ( $FileHeader ne "\x1f\x8b" ) {  # Gzip magic number (first 2 bytes)
            $LogObject->Log(
                Priority => 'error',
                Message  => "Import failed: Invalid gzip magic bytes. Got: $HeaderHex (expected: 1f8b)",
            );
            return $Self->_ShowMainPage(
                ImportError => Translatable('Invalid file content. Please upload a valid gzip exported configuration file.'),
            );
        }
        
        my $WriteSuccess = $MainObject->FileWrite(
            Location => $TempFile,
            Content  => \$BinaryContent,
            Mode     => 'binmode',
        );
        
        if (!$WriteSuccess) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Failed to write temp file: $TempFile",
            );
            return $Self->_ShowMainPage(
                ImportError => Translatable('Failed to write temporary file for import.'),
            );
        }
        
        # Verify file was written and is valid
        if (!-f $TempFile) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Temp file does not exist after write: $TempFile",
            );
            return $Self->_ShowMainPage(
                ImportError => Translatable('Temporary file was not created.'),
            );
        }
        
        my $FileSize = -s $TempFile;

        # Validate the exported configuration file first
        my $ValidationResult = $ExportImportConfigObject->ValidateImport(
            FilePath => $TempFile,  # Fixed: Changed from Filepath to FilePath
        );

        if ( !$ValidationResult || !$ValidationResult->{Success} ) {
            unlink $TempFile;
            my $ErrorMessage = $ValidationResult->{Message} || Translatable('Exported configuration file validation failed.');
            
            $LogObject->Log(
                Priority => 'error',
                Message  => "Import validation failed for user $Self->{UserID}: $ErrorMessage",
            );
            
            return $Self->_ShowMainPage(
                ImportError => $ErrorMessage,
            );
        }

        # Perform the import
        my $ImportResult = $ExportImportConfigObject->ImportConfiguration(
            FilePath => $TempFile,
            UserID   => $Self->{UserID},
        );

        # Clean up temp file
        unlink $TempFile;

        if ( !$ImportResult || !ref($ImportResult) || !$ImportResult->{Success} ) {
            my $ErrorMessage = (ref($ImportResult) && $ImportResult->{Message}) ? $ImportResult->{Message} : Translatable('Import failed due to an unknown error.');
            
            $LogObject->Log(
                Priority => 'error',
                Message  => "Configuration import failed for user $Self->{UserID}: $ErrorMessage",
            );
            
            return $Self->_ShowMainPage(
                ImportError => $ErrorMessage,
            );
        }
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "Import completed successfully, redirecting to ImportSuccess=1",
        );

        # Success - redirect with success message
        return $LayoutObject->Redirect(
            OP => "Action=AdminExportImportConfig;ImportSuccess=1"
        );
    }


    # ------------------------------------------------------------ #
    # Default: Show Main Page
    # ------------------------------------------------------------ #
    else {
        return $Self->_ShowMainPage();
    }
}

sub _ShowMainPage {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    
    # Check for success messages
    if ( $ParamObject->GetParam( Param => 'ImportSuccess' ) ) {
        $Param{SuccessMessage} = Translatable('Configuration imported successfully.');
    }

    # Show what will be exported/imported (informational only)
    $Param{ExportInfo} = Translatable('The following configurations will be exported: SMS Settings, SMTP Settings, Zabbix Integration Settings, Ticket Prefixes');

    # Generate output
    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();
    
    # Show notifications
    $Output .= $LayoutObject->Notify( Info => $Param{SuccessMessage} ) if $Param{SuccessMessage};
    $Output .= $LayoutObject->Notify( Priority => 'Error', Info => $Param{ExportError} ) if $Param{ExportError};
    $Output .= $LayoutObject->Notify( Priority => 'Error', Info => $Param{ImportError} ) if $Param{ImportError};
    $Output .= $LayoutObject->Notify( Priority => 'Warning', Info => $Param{Warning} ) if $Param{Warning};
    
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminExportImportConfig',
        Data         => \%Param,
    );
    $Output .= $LayoutObject->Footer();
    
    return $Output;
}

1;

=head1 NAME

Kernel::Modules::AdminExportImportConfig - Simplified admin interface for configuration export/import

=head1 DESCRIPTION

Simplified frontend controller for configuration export/import. Handles GetProgress (AJAX), Export, and Import subactions.
Admin-only access with validation and progress tracking.

=cut