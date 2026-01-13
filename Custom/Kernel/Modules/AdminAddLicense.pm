# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminAddLicense;

use strict;
use warnings;
use JSON;
use Crypt::CBC;
use Crypt::Rijndael;

use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject        = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject         = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $AdminAddLicenseObject = $Kernel::OM->Get('Kernel::System::AdminAddLicense');

    # ------------------------------------------------------------ #
    # change
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Change' ) {
        my $ID   = $ParamObject->GetParam( Param => 'ID' ) || '';
        my %Data = $AdminAddLicenseObject->AdminAddLicenseGet(
            ID => $ID,
        );

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Self->_Edit(
            Action => 'Change',
            %Data,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminAddLicense',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # change action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'ChangeAction' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my @NewIDs = $ParamObject->GetArray( Param => 'IDs' );
        my ( %GetParam, %Errors );
        for my $Parameter (qw(ID Name Comment ValidID)) {
            $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # get attachment
        my %UploadStuff = $ParamObject->GetUploadAll(
            Param => 'FileUpload',
        );

        # check needed data
        for my $Needed (qw(Name ValidID)) {
            if ( !$GetParam{$Needed} ) {
                $Errors{ $Needed . 'Invalid' } = 'ServerError';
            }
        }

        # if no errors occurred
        if ( !%Errors ) {

            # update attachment
            my $Update = $AdminAddLicenseObject->AdminAddLicenseUpdate(
                %GetParam,
                %UploadStuff,
                UserID => $Self->{UserID},
            );
            if ($Update) {

                # if the user would like to continue editing the attachment, just redirect to the edit screen
                if (
                    defined $ParamObject->GetParam( Param => 'ContinueAfterSave' )
                    && ( $ParamObject->GetParam( Param => 'ContinueAfterSave' ) eq '1' )
                    )
                {
                    my $ID = $ParamObject->GetParam( Param => 'ID' ) || '';
                    return $LayoutObject->Redirect( OP => "Action=$Self->{Action};Subaction=Change;ID=$ID" );
                }
                else {

                    # otherwise return to overview
                    return $LayoutObject->Redirect( OP => "Action=$Self->{Action}" );
                }
            }
        }

        # something has gone wrong
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Notify( Priority => 'Error' );
        $Self->_Edit(
            Action => 'Change',
            Errors => \%Errors,
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminAddLicense',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # add
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Add' ) {
        my %GetParam;
        $GetParam{Name} = $ParamObject->GetParam( Param => 'Name' );
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Self->_Edit(
            Action => 'Add',
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminAddLicense',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # add action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'AddAction' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my @NewIDs = $ParamObject->GetArray( Param => 'IDs' );
        my ( %GetParam, %Errors );
        # for my $Parameter (qw(ame Comment ValidID)) {
        #     $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        # }

        # get attachment
        my %UploadStuff = $ParamObject->GetUploadAll(
            Param => 'FileUpload',
        );

        # Validate file upload
        if (%UploadStuff && $UploadStuff{Filename}) {
            # Check if file has .lic extension
            if ($UploadStuff{Filename} !~ /\.lic$/i) {
                $Errors{FileUploadInvalid} = 'ServerError';
                $Errors{InvalidFileType} = 'Only .lic files are allowed';
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "Invalid file type uploaded: $UploadStuff{Filename}. Only .lic files are allowed.",
                );
            }
            
            # Check file size (max 1MB for license files)
            elsif (length($UploadStuff{Content}) > 1048576) {
                $Errors{FileUploadInvalid} = 'ServerError';
                $Errors{FileSizeTooLarge} = 'License file is too large';
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "License file too large: " . length($UploadStuff{Content}) . " bytes (max 1MB allowed)",
                );
            }
            
            # Check minimum file size (at least 32 bytes for IV + minimal encrypted content)
            elsif (length($UploadStuff{Content}) < 32) {
                $Errors{FileUploadInvalid} = 'ServerError';
                $Errors{FileSizeTooSmall} = 'License file is too small to be valid';
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "License file too small: " . length($UploadStuff{Content}) . " bytes",
                );
            }
        }

        # get encryption key from database
        my $EncryptionKeyObject = $Kernel::OM->Get('Kernel::System::EncryptionKey');
        my $key = $EncryptionKeyObject->GetKey(
            KeyName => 'license_aes_key',
        );

        if (!$key) {
            $Errors{FileUploadInvalid} = 'ServerError';
            $Errors{KeyError} = 'Encryption key not found in database';
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "License AES encryption key not found in database!",
            );
        }

        my $plaintext;
        # Only attempt decryption if no errors so far
        if ($key && !%Errors) {
            # Detect license format and decrypt accordingly
            my $content = $UploadStuff{Content};
            my $iv;
            my $ciphertext;
            
            # Check if content is base64 encoded (new format)
            # More robust base64 detection - check for base64 characters and proper padding
            my $content_trimmed = $content;
            $content_trimmed =~ s/\s+//g; # Remove any whitespace
            
            if ($content_trimmed =~ /^[A-Za-z0-9+\/]+=*$/ && length($content_trimmed) % 4 == 0) {
                # Base64 format - decode first
                eval {
                    require MIME::Base64;
                    my $decoded = MIME::Base64::decode_base64($content_trimmed);
                    
                    # Verify decoding produced valid binary data
                    if (length($decoded) == 0) {
                        die "Base64 decoding produced empty result";
                    }
                    
                    # Extract IV (first 16 bytes) and ciphertext
                    if (length($decoded) > 16) {
                        $iv = substr($decoded, 0, 16);
                        $ciphertext = substr($decoded, 16);
                    }
                    else {
                        $Errors{FileUploadInvalid} = 'ServerError';
                        $Errors{InvalidLicenseFormat} = 'License file is too short or corrupted';
                    }
                };
                if ($@) {
                    $Errors{FileUploadInvalid} = 'ServerError';
                    $Errors{InvalidBase64} = 'License file contains invalid base64 data';
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message  => "Failed to decode base64 license: $@",
                    );
                }
            }
            else {
                # Binary format - IV is first 16 bytes
                if (length($content) > 16) {
                    $iv = substr($content, 0, 16);
                    $ciphertext = substr($content, 16);
                }
                else {
                    $Errors{FileUploadInvalid} = 'ServerError';
                    $Errors{InvalidLicenseFormat} = 'License file is too short or corrupted';
                }
            }
            
            # Decrypt if we have valid IV and ciphertext
            if ($iv && $ciphertext && !%Errors) {
                eval {
                    # --- Create AES cipher ---
                    my $cipher = Crypt::CBC->new(
                        -cipher      => 'Crypt::Rijndael',
                        -key         => $key,
                        -iv          => $iv,
                        -literal_key => 1,
                        -header      => 'none',
                        -keysize     => 32,
                    );

                    # --- Decrypt content ---
                    $plaintext = $cipher->decrypt($ciphertext);
                };
                if ($@) {
                    $Errors{FileUploadInvalid} = 'ServerError';
                    $Errors{DecryptionFailed} = 'Failed to decrypt license file';
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message  => "License decryption failed: $@",
                    );
                }
            }
        }

        # check needed data
        if ( !%UploadStuff ) {
            $Errors{FileUploadInvalid} = 'ServerError';
        }

        my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');
        my $JSONText;
        my $JSON;
        my $LicenseData;

        # Only process if no errors so far
        if (!%Errors && $plaintext) {
            # --- Strip out binary prefix before JSON (up to the first '{' character) ---
            $plaintext =~ s/^[^\{]*//;  # Remove everything before the first '{'
            
            # Check if we have valid JSON structure
            if ($plaintext !~ /^\s*\{.*\}\s*$/s) {
                $Errors{FileUploadInvalid} = 'ServerError';
                $Errors{InvalidJSONStructure} = 'Decrypted content does not contain valid JSON';
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "License file decrypted but contains invalid data structure. May be encrypted with wrong key.",
                );
            }
            else {
                $JSONText = $plaintext;
                $GetParam{Content} = $plaintext;
                $GetParam{ContentType} = 'application/json';
                $GetParam{Filename} = $UploadStuff{Filename};

                eval {
                     $JSON = $JSONObject->Decode(
                        Data => $JSONText,
                    );

                    my $ref_type = ref($JSON);
                    
                    # Check for proper license structure
                    if (!$JSON || ref($JSON) ne 'HASH' || !exists $JSON->{msstLiteLicense}) {
                        die "Invalid license structure - missing msstLiteLicense key";
                    }

                    foreach my $key ( keys %{$JSON} ) {
                        my $value = $JSON->{$key};
                        
                        if (ref($value) ne 'HASH') {
                            die "Invalid license structure - msstLiteLicense must be a hash";
                        }

                        foreach my $key ( keys %{$value} ) {
                            # Sanitize null values - handle both string "null" and actual null/undef
                            if (!defined $value->{$key} || 
                                $value->{$key} eq '' ||
                                (defined $value->{$key} && lc($value->{$key}) eq 'null')) {
                                $GetParam{$key} = '';
                                $value->{$key} = '';  # Also update the original data for validation
                            } else {
                                $GetParam{$key} = $value->{$key};
                            }
                        }

                        # Store license data for validation
                        $LicenseData = $value if ref($value) eq 'HASH';
                        
                        # Handle both contractNumber and mcn for backward compatibility
                        if ($LicenseData) {
                            if ($LicenseData->{contractNumber} && !$LicenseData->{mcn}) {
                                $GetParam{mcn} = $LicenseData->{contractNumber};
                                $LicenseData->{mcn} = $LicenseData->{contractNumber};
                            } elsif ($LicenseData->{mcn} && !$LicenseData->{contractNumber}) {
                                $GetParam{contractNumber} = $LicenseData->{mcn};
                                $LicenseData->{contractNumber} = $LicenseData->{mcn};
                            }
                            
                            # Adjust endDate to include full day (23:59:59) if it's in date-only format
                            if ($GetParam{endDate} && $GetParam{endDate} =~ /^\d{4}[-\/]\d{2}[-\/]\d{2}$/) {
                                $GetParam{endDate} .= ' 23:59:59';
                            }
                            # Also adjust startDate to start of day (00:00:00) if needed
                            if ($GetParam{startDate} && $GetParam{startDate} =~ /^\d{4}[-\/]\d{2}[-\/]\d{2}$/) {
                                $GetParam{startDate} .= ' 00:00:00';
                            }
                        }
                    }
                      # Convert JSON string to Perl hashref/arrayref
                    1;
                } or do {
                    $Errors{FileUploadInvalid} = 'ServerError';
                    $Errors{JSONInvalid} = 'Invalid JSON content';
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message  => "Failed to parse license JSON: $@",
                    );
                };
            }
        }
        elsif (!%Errors && !$plaintext) {
            # Decryption succeeded but produced empty result
            $Errors{FileUploadInvalid} = 'ServerError';
            $Errors{DecryptionEmpty} = 'License decryption produced empty result';
        }

        # Validate license dates if JSON was successfully parsed
        if (!%Errors && !$Errors{JSONInvalid} && $LicenseData) {
            # First check required fields (accept either contractNumber or mcn)
            my @RequiredFields = qw(UID contractCompany endCustomer macAddress startDate endDate);
            my @MissingFields;
            
            # Check for either contractNumber or mcn
            if ((!defined $LicenseData->{contractNumber} || $LicenseData->{contractNumber} eq '' || lc($LicenseData->{contractNumber}) eq 'null') &&
                (!defined $LicenseData->{mcn} || $LicenseData->{mcn} eq '' || lc($LicenseData->{mcn}) eq 'null')) {
                push @MissingFields, 'contractNumber/mcn';
            }
            
            foreach my $field (@RequiredFields) {
                if (!defined $LicenseData->{$field} || 
                    $LicenseData->{$field} eq '' ||
                    lc($LicenseData->{$field}) eq 'null') {
                    push @MissingFields, $field;
                }
            }
            
            if (@MissingFields) {
                $Errors{LicenseMissingFields} = 'ServerError';
                $Errors{LicenseMissingFieldsList} = join(', ', @MissingFields);
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "License is missing or has invalid values for required fields: " . join(', ', @MissingFields),
                );
            }
            
            # Validate field content for suspicious characters
            if (!%Errors && !@MissingFields) {
                # Check for potentially malicious content in text fields
                my @TextFields = qw(contractCompany endCustomer contractNumber mcn systemTechnology lsmpSiteID);
                for my $field (@TextFields) {
                    if ($LicenseData->{$field} && $LicenseData->{$field} =~ /[<>\"\'\\]|javascript:|data:|vbscript:|file:|\.\.\//) {
                        $Errors{LicenseSuspiciousContent} = 'ServerError';
                        $Errors{LicenseSuspiciousField} = $field;
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => "License field '$field' contains suspicious content",
                        );
                        last;
                    }
                }
                
                # Validate MAC address format
                if ($LicenseData->{macAddress} && 
                    $LicenseData->{macAddress} !~ /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/) {
                    $Errors{LicenseInvalidMACFormat} = 'ServerError';
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message  => "License has invalid MAC address format: " . $LicenseData->{macAddress},
                    );
                }
            }
            
            my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
            my $CurrentTime = $TimeObject->SystemTime();
            
            # Parse dates from license
            my $StartDate = $LicenseData->{startDate} || '';
            my $EndDate = $LicenseData->{endDate} || '';
            
            if ($StartDate && $EndDate) {
                # Convert dates to system time for comparison
                # Handle both YYYY-MM-DD and YYYY/MM/DD formats
                my ($StartYear, $StartMonth, $StartDay) = split(/[-\/]/, $StartDate);
                my ($EndYear, $EndMonth, $EndDay) = split(/[-\/]/, $EndDate);
                
                if ($StartYear && $StartMonth && $StartDay && $EndYear && $EndMonth && $EndDay) {
                    my $StartTime = $TimeObject->Date2SystemTime(
                        Year   => $StartYear,
                        Month  => $StartMonth,
                        Day    => $StartDay,
                        Hour   => 0,
                        Minute => 0,
                        Second => 0,
                    );
                    
                    my $EndTime = $TimeObject->Date2SystemTime(
                        Year   => $EndYear,
                        Month  => $EndMonth,
                        Day    => $EndDay,
                        Hour   => 23,
                        Minute => 59,
                        Second => 59,
                    );
                    
                    # Check if license is expired
                    if ($CurrentTime > $EndTime) {
                        $Errors{LicenseExpired} = 'ServerError';
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => "Cannot import expired license (expired on $EndDate)",
                        );
                    }
                    # Check if license is not yet valid
                    elsif ($CurrentTime < $StartTime) {
                        $Errors{LicenseNotYetValid} = 'ServerError';
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => "Cannot import license that is not yet valid (starts on $StartDate)",
                        );
                    }
                    # Check for suspiciously far future dates (more than 10 years)
                    elsif ($EndTime > ($CurrentTime + 315360000)) { # 10 years in seconds
                        $Errors{LicenseSuspiciousDate} = 'ServerError';
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => "License has suspiciously far future date: $EndDate",
                        );
                    }
                    # Check if start date is after end date
                    elsif ($StartTime > $EndTime) {
                        $Errors{LicenseInvalidDateRange} = 'ServerError';
                        $Kernel::OM->Get('Kernel::System::Log')->Log(
                            Priority => 'error',
                            Message  => "License start date ($StartDate) is after end date ($EndDate)",
                        );
                    }
                }
                else {
                    $Errors{LicenseInvalidDates} = 'ServerError';
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message  => "License has invalid date format",
                    );
                }
            }
            else {
                $Errors{LicenseMissingDates} = 'ServerError';
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "License is missing start or end date",
                );
            }
        }
        
        # Validate MAC address if JSON was successfully parsed and no other errors
        if (!%Errors && $LicenseData && $LicenseData->{macAddress}) {
            # Get server's MAC address
            my $ServerMAC = $Self->_GetServerMACAddress();
            
            if ($ServerMAC) {
                # Normalize MAC addresses for comparison (remove colons/hyphens and convert to lowercase)
                my $LicenseMAC = lc($LicenseData->{macAddress});
                $LicenseMAC =~ s/[:-]//g;
                
                my $NormalizedServerMAC = lc($ServerMAC);
                $NormalizedServerMAC =~ s/[:-]//g;
                
                # Timing-safe MAC comparison to prevent timing attacks
                if (!$Self->_TimingSafeCompare($LicenseMAC, $NormalizedServerMAC)) {
                    $Errors{LicenseInvalidMAC} = 'ServerError';
                    $Errors{LicenseMACMismatch} = "License MAC address does not match server MAC address";
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message  => "License MAC address does not match server MAC address",
                    );
              
                    # Log MAC validation debug info to Apache error log
                    my $LogMessage = "[ZNUNY LICENSE DEBUG] MAC validation failed - Server MAC: $NormalizedServerMAC, License MAC: $LicenseMAC, Raw Server MAC: $ServerMAC";
                    
                    # Try to use Apache2::RequestUtil if available
                    eval {
                        require Apache2::RequestUtil;
                        require Apache2::Log;
                        my $r = Apache2::RequestUtil->request();
                        if ($r) {
                            $r->log_error($LogMessage);
                        }
                    };
                    
                   
                }
            }
            else {
                $Errors{ServerMACError} = 'ServerError';
                $Errors{ServerMACNotFound} = "Unable to determine server MAC address";
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "Unable to determine server MAC address for license validation",
                );
            }
        }


        # if no errors occurred
        if ( !%Errors ) {

            # add state
            my %inputArgs = (%GetParam, %UploadStuff);
            
            my $AdminAddLicenseID = $AdminAddLicenseObject->AdminAddLicenseAdd(
                %inputArgs,
                UserID => $Self->{UserID},
            );
            if ($AdminAddLicenseID) {
                return $LayoutObject->Redirect(
                    OP => "Action=AdminAddLicense",
                );
            }
        }

        # something has gone wrong
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Notify( Priority => 'Error' );
        $Self->_Edit(
            Action => 'Add',
            Errors => \%Errors,
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminAddLicense',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # delete action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Delete' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $ID     = $ParamObject->GetParam( Param => 'ID' );
        my $Delete = $AdminAddLicenseObject->AdminAddLicenseDelete(
            ID => $ID,
        );

        return $LayoutObject->Attachment(
            ContentType => 'text/html',
            Content     => ($Delete) ? $ID : 0,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # ------------------------------------------------------------ #
    # download action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Download' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $ID = $ParamObject->GetParam( Param => 'ID' );

        my %Data = $AdminAddLicenseObject->AdminAddLicenseGet(
            ID => $ID,
        );
        if ( !%Data ) {
            return $LayoutObject->ErrorScreen();
        }

        return $LayoutObject->Attachment(
            %Data,
            Type => 'attachment',
        );
    }

    # ------------------------------------------------------------
    # overview
    # ------------------------------------------------------------
    else {
        $Self->_Overview();
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminAddLicense',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

}

sub _Edit {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    $LayoutObject->Block(
        Name => 'Overview',
        Data => \%Param,
    );

    $LayoutObject->Block(
        Name => 'ActionList',
    );
    $LayoutObject->Block(
        Name => 'ActionOverview',
    );

    # get valid list
    my %ValidList        = $Kernel::OM->Get('Kernel::System::Valid')->ValidList();
    my %ValidListReverse = reverse %ValidList;

    $Param{ValidOption} = $LayoutObject->BuildSelection(
        Data       => \%ValidList,
        Name       => 'ValidID',
        SelectedID => $Param{ValidID} || $ValidListReverse{valid},
        Class      => 'Modernize Validate_Required ' . ( $Param{Errors}->{'ValidIDInvalid'} || '' ),
    );

    # add class for validation
    if ( $Param{Action} eq 'Add' ) {
        $Param{ValidateContent} = "Validate_Required";
    }

    $LayoutObject->Block(
        Name => 'OverviewUpdate',
        Data => {
            %Param,
            %{ $Param{Errors} },
        },
    );

    return 1;
}

sub _Overview {
    my ( $Self, %Param ) = @_;

    my $LayoutObject        = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $AdminAddLicenseObject = $Kernel::OM->Get('Kernel::System::AdminAddLicense');

    # Check if we were redirected here due to invalid license
    my $LicenseStatus = 'Unknown';
    my $ShowLicenseWarning = 0;
    
    # Get the license list to determine current status
    my %List = $AdminAddLicenseObject->AdminAddLicenseList(
        UserID => 1,
        Valid  => 0,
    );
    
    if (%List && $List{license_status}) {
        $LicenseStatus = $List{license_status};
        $ShowLicenseWarning = ($LicenseStatus ne 'Valid') ? 1 : 0;
    }
    else {
        # No license found
        $LicenseStatus = 'NotFound';
        $ShowLicenseWarning = 1;
    }

    $LayoutObject->Block(
        Name => 'Overview',
        Data => {
            %Param,
            LicenseStatus => $LicenseStatus,
            ShowLicenseWarning => $ShowLicenseWarning,
        },
    );
    
    # Show license warning block if needed
    if ($ShowLicenseWarning) {
        $LayoutObject->Block(
            Name => 'LicenseWarning',
            Data => {
                LicenseStatus => $LicenseStatus,
            },
        );
    }
    
    $LayoutObject->Block(
        Name => 'ActionList',
    );
    $LayoutObject->Block(
        Name => 'ActionAdd',
    );
    $LayoutObject->Block(
        Name => 'Filter',
    );
    $LayoutObject->Block(
        Name => 'OverviewResult',
        Data => \%Param,
    );
    
    if (%List) {
        $LayoutObject->Block(
                Name => 'OverviewResultRow',
                Data => {
                    %List,
                },
            );
    }
    else {
        $LayoutObject->Block(
            Name => 'NoDataFoundMsg',
            Data => {},
        );
    }
    return 1;
        

    # if there are any results, they are shown
    # if (%List) {

    #     # get valid list
    #     for my $ID ( sort { $List{$a} cmp $List{$b} } keys %List ) {
    #         my %Data = $AdminAddLicenseObject->AdminAddLicenseGet(
    #             ID => $ID,
    #         );

    #         $LayoutObject->Block(
    #             Name => 'OverviewResultRow',
    #             Data => {
    #                 Valid => $ValidList{ $Data{ValidID} },
    #                 %Data,
    #             },
    #         );
    #     }
    # }

    # otherwise a no data message is displayed
    
}

sub _GetServerMACAddress {
    my ( $Self, %Param ) = @_;
    
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Try to get MAC address using ip command
    my $MACAddress;
    
    # Try ip addr command first (modern Linux)
    my $IPCommand = `which ip 2>/dev/null`;
    chomp($IPCommand);
    
    if ($IPCommand) {
        # Get the first non-loopback interface MAC address
        my $Output = `ip addr show 2>/dev/null | grep -E "link/ether" | grep -v "veth" | head -1`;
        if ($Output && $Output =~ /link\/ether\s+([0-9a-fA-F:]+)/) {
            $MACAddress = $1;
            $LogObject->Log(
                Priority => 'info',
                Message  => "Found MAC address using ip command: $MACAddress",
            );
            return $MACAddress;
        }
    }
    
    # Fallback to ifconfig if ip command fails
    my $IfconfigCommand = `which ifconfig 2>/dev/null`;
    chomp($IfconfigCommand);
    
    if ($IfconfigCommand) {
        my $Output = `ifconfig -a 2>/dev/null | grep -E "ether|HWaddr" | grep -v "veth" | head -1`;
        if ($Output && $Output =~ /(?:ether|HWaddr)\s+([0-9a-fA-F:]+)/) {
            $MACAddress = $1;
            $LogObject->Log(
                Priority => 'info',
                Message  => "Found MAC address using ifconfig: $MACAddress",
            );
            return $MACAddress;
        }
    }
    
    # Try reading from /sys/class/net as last resort
    if (-d '/sys/class/net') {
        opendir(my $dh, '/sys/class/net') or return;
        my @interfaces = grep { !/^(lo|veth)/ && -d "/sys/class/net/$_" } readdir($dh);
        closedir($dh);
        
        for my $interface (@interfaces) {
            my $mac_file = "/sys/class/net/$interface/address";
            if (-r $mac_file) {
                if (open(my $fh, '<', $mac_file)) {
                    $MACAddress = <$fh>;
                    close($fh);
                    chomp($MACAddress) if $MACAddress;
                    if ($MACAddress && $MACAddress =~ /^[0-9a-fA-F:]+$/) {
                        $LogObject->Log(
                            Priority => 'info',
                            Message  => "Found MAC address from /sys/class/net: $MACAddress",
                        );
                        return $MACAddress;
                    }
                }
            }
        }
    }
    
    $LogObject->Log(
        Priority => 'error',
        Message  => "Unable to determine server MAC address",
    );
    
    return;
}

sub _TimingSafeCompare {
    my ( $Self, $String1, $String2 ) = @_;
    
    # Ensure both strings are defined
    return 0 if !defined $String1 || !defined $String2;
    
    # Convert to bytes for comparison
    my @Bytes1 = unpack('C*', $String1);
    my @Bytes2 = unpack('C*', $String2);
    
    # Pad shorter array with zeros to make equal length
    my $MaxLen = @Bytes1 > @Bytes2 ? @Bytes1 : @Bytes2;
    push @Bytes1, (0) x ($MaxLen - @Bytes1) if @Bytes1 < $MaxLen;
    push @Bytes2, (0) x ($MaxLen - @Bytes2) if @Bytes2 < $MaxLen;
    
    # Compare using XOR to avoid early termination
    my $Result = 0;
    for (my $i = 0; $i < $MaxLen; $i++) {
        $Result |= ($Bytes1[$i] || 0) ^ ($Bytes2[$i] || 0);
    }
    
    # Also check length difference
    $Result |= @Bytes1 ^ @Bytes2;
    
    return $Result == 0 ? 1 : 0;
}

1;

