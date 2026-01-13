# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::TwilioSMS;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::Config',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # Load required modules once during object creation for better performance
    # These are optional dependencies - system will still work if modules are missing
    # Loading them here instead of in SendSMS avoids repeated module loading overhead
    eval {
        require LWP::UserAgent;
        require MIME::Base64;
        require URI::Escape;
    };
    if ($@) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "TwilioSMS: Failed to load required modules: $@",
        );
        # Track that modules failed to load to prevent crashes in SendSMS
        $Self->{ModulesLoaded} = 0;
    }
    else {
        # Modules loaded successfully
        $Self->{ModulesLoaded} = 1;
    }

    return $Self;
}

=head2 GetConfiguration()

Get Twilio SMS configuration from system configuration

    my %Config = $TwilioSMSObject->GetConfiguration();

Returns:
    %Config = (
        AccountSID        => 'ACxxxxx...',
        AuthToken         => 'xxxxx...',
        FromNumber        => '+1234567890',
        DefaultRecipients => '+1111111111,+2222222222',
        Success           => 1,
        ErrorMessage      => '',
    );

=cut

sub GetConfiguration {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my %Config = (
        AccountSID        => $ConfigObject->Get('SMSNotification::TwilioAccountSID') || '',
        AuthToken         => $ConfigObject->Get('SMSNotification::TwilioAuthToken') || '',
        FromNumber        => $ConfigObject->Get('SMSNotification::TwilioFromNumber') || '',
        DefaultRecipients => $ConfigObject->Get('SMSNotification::DefaultRecipients') || '',
        Success           => 1,
        ErrorMessage      => '',
    );

    # Validate required fields
    if ( !$Config{AccountSID} || !$Config{AuthToken} || !$Config{FromNumber} ) {
        return (
            Success      => 0,
            ErrorMessage => 'Twilio configuration incomplete. Please check Account SID, Auth Token, and From Number in System Configuration.',
        );
    }

    return %Config;
}

=head2 SendSMS()

Send SMS message to one or more recipients

    my %Result = $TwilioSMSObject->SendSMS(
        Recipients => ['+1234567890', '+0987654321'],  # Array ref of phone numbers
        Message    => 'Your SMS message text',
        # Optional parameters:
        AccountSID => 'ACxxxxx...',  # Will use config if not provided
        AuthToken  => 'xxxxx...',    # Will use config if not provided  
        FromNumber => '+1111111111', # Will use config if not provided
    );

Returns:
    %Result = (
        Success      => 1,
        SuccessCount => 2,
        FailureCount => 0,
        FailedNumbers => [],
        ErrorMessage => '',
        Details => [
            {
                Recipient => '+1234567890',
                Success   => 1,
                MessageSID => 'SMxxxxx...',
                Error     => '',
            },
            {
                Recipient => '+0987654321',
                Success   => 1,
                MessageSID => 'SMxxxxx...',
                Error     => '',
            },
        ],
    );

=cut

sub SendSMS {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Check if required modules were loaded successfully
    if (!$Self->{ModulesLoaded}) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'TwilioSMS: Cannot send SMS - required modules (LWP::UserAgent, MIME::Base64, URI::Escape) not available',
        );
        return (
            Success      => 0,
            ErrorMessage => 'SMS functionality unavailable - required Perl modules not installed',
        );
    }
    
    # Log that SendSMS was called
    $LogObject->Log(
        Priority => 'info',
        Message  => "TwilioSMS::SendSMS called with " . scalar(@{$Param{Recipients} || []}) . " recipients",
    );

    # Check required parameters
    if ( !$Param{Recipients} || ref $Param{Recipients} ne 'ARRAY' || !@{$Param{Recipients}} ) {
        return (
            Success      => 0,
            ErrorMessage => 'Recipients parameter is required and must be an array reference with at least one phone number.',
        );
    }

    if ( !$Param{Message} ) {
        return (
            Success      => 0,
            ErrorMessage => 'Message parameter is required.',
        );
    }

    # Get configuration if not provided
    my %Config;
    if ( $Param{AccountSID} && $Param{AuthToken} && $Param{FromNumber} ) {
        %Config = (
            AccountSID => $Param{AccountSID},
            AuthToken  => $Param{AuthToken},
            FromNumber => $Param{FromNumber},
            Success    => 1,
        );
    } else {
        %Config = $Self->GetConfiguration();
        if ( !$Config{Success} ) {
            return (
                Success      => 0,
                ErrorMessage => $Config{ErrorMessage},
            );
        }
    }

    # Modules are now loaded in constructor for better performance
    my $ua = LWP::UserAgent->new( timeout => 30 );
    my $url = "https://api.twilio.com/2010-04-01/Accounts/$Config{AccountSID}/Messages.json";

    my $auth = MIME::Base64::encode_base64("$Config{AccountSID}:$Config{AuthToken}");
    chomp $auth;

    # Twilio will automatically handle long messages by splitting them into segments
    # Each segment costs separately, but allows full message delivery
    # Standard SMS: 160 chars, Unicode: 70 chars, Concatenated: 153/67 chars per segment
    my $Message = $Param{Message};

    my $SuccessCount = 0;
    my $FailureCount = 0;
    my @FailedNumbers;
    my @Details;

    # Send SMS to each recipient individually
    for my $Recipient ( @{$Param{Recipients}} ) {
        # Validate phone number format
        if ( $Recipient !~ /^\+[1-9]\d{1,14}$/ ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Invalid phone number format: $Recipient. Must be in E.164 format. Skipping.",
            );
            
            push @Details, {
                Recipient  => $Recipient,
                Success    => 0,
                MessageSID => '',
                Error      => 'Invalid phone number format. Must be in E.164 format.',
            };
            
            push @FailedNumbers, $Recipient;
            $FailureCount++;
            next;
        }

        $LogObject->Log(
            Priority => 'notice',
            Message  => "TwilioSMS: Sending SMS to $Recipient",
        );

        # Prepare request content
        my $content = sprintf("From=%s&To=%s&Body=%s",
            URI::Escape::uri_escape($Config{FromNumber}),
            URI::Escape::uri_escape($Recipient),
            URI::Escape::uri_escape($Message)
        );

        # Make API request
        my $response = $ua->post($url,
            'Authorization' => "Basic $auth",
            'Content-Type'  => 'application/x-www-form-urlencoded',
            Content         => $content
        );

        if ( $response->is_success ) {
            # Parse response to get message SID
            my $ResponseContent = $response->content;
            my $MessageSID = '';
            if ( $ResponseContent =~ /"sid":"([^"]+)"/ ) {
                $MessageSID = $1;
            }

            $LogObject->Log(
                Priority => 'info',
                Message  => "TwilioSMS: SMS sent successfully to $Recipient (SID: $MessageSID)",
            );

            push @Details, {
                Recipient  => $Recipient,
                Success    => 1,
                MessageSID => $MessageSID,
                Error      => '',
            };

            $SuccessCount++;
        } else {
            my $ErrorMsg = $response->status_line;
            if ( $response->content ) {
                $ErrorMsg .= " - " . $response->content;
            }

            $LogObject->Log(
                Priority => 'error',
                Message  => "TwilioSMS: Failed to send SMS to $Recipient: $ErrorMsg",
            );

            push @Details, {
                Recipient  => $Recipient,
                Success    => 0,
                MessageSID => '',
                Error      => $ErrorMsg,
            };

            push @FailedNumbers, $Recipient;
            $FailureCount++;
        }
    }

    # Determine overall success
    my $OverallSuccess = $SuccessCount > 0 ? 1 : 0;
    my $ErrorMessage = '';

    if ( $FailureCount > 0 && $SuccessCount == 0 ) {
        $ErrorMessage = 'All SMS sends failed.';
    } elsif ( $FailureCount > 0 ) {
        $ErrorMessage = "Some SMS sends failed. Failed recipients: " . join(', ', @FailedNumbers);
    }

    return (
        Success       => $OverallSuccess,
        SuccessCount  => $SuccessCount,
        FailureCount  => $FailureCount,
        FailedNumbers => \@FailedNumbers,
        ErrorMessage  => $ErrorMessage,
        Details       => \@Details,
    );
}

=head2 ParseRecipients()

Parse comma-separated recipients string into validated array

    my @Recipients = $TwilioSMSObject->ParseRecipients(
        Recipients => '+1234567890, +0987654321, invalid-number',
    );

Returns array of valid phone numbers in E.164 format.
Invalid numbers are logged but excluded from results.

=cut

sub ParseRecipients {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    return () if !$Param{Recipients};

    # Remove whitespace and split by comma
    my $CleanRecipients = $Param{Recipients};
    $CleanRecipients =~ s/\s+//g;  # Remove all whitespace
    my @RawRecipients = split /,/, $CleanRecipients;

    my @ValidRecipients;
    for my $Recipient (@RawRecipients) {
        if ( $Recipient && $Recipient =~ /^\+[1-9]\d{1,14}$/ ) {
            push @ValidRecipients, $Recipient;
        } elsif ( $Recipient ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "TwilioSMS: Invalid recipient phone number format: $Recipient",
            );
        }
    }

    return @ValidRecipients;
}

1;