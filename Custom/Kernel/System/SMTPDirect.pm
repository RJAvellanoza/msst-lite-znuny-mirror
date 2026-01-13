# --
# Copyright (C) 2025 MSST-Lite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::SMTPDirect;

use strict;
use warnings;

use Net::SMTP;
use MIME::Base64;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub SendEmail {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    # Check required parameters
    for my $Needed (qw(To Subject Body)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "SMTPDirect: Need $Needed!",
            );
            return;
        }
    }

    # Get SMTP configuration from SMTPNotification settings
    my $SMTPHost   = $ConfigObject->Get('SMTPNotification::Host') || $ConfigObject->Get('SendmailModule::Host');
    my $SMTPPort   = $ConfigObject->Get('SMTPNotification::Port') || $ConfigObject->Get('SendmailModule::Port') || 25;
    my $SMTPUser   = $ConfigObject->Get('SMTPNotification::AuthUser') || $ConfigObject->Get('SendmailModule::AuthUser');
    my $SMTPPass   = $ConfigObject->Get('SMTPNotification::AuthPassword') || $ConfigObject->Get('SendmailModule::AuthPassword');
    my $Encryption = $ConfigObject->Get('SMTPNotification::Encryption') || 'none';
    my $FromEmail  = $Param{From} || $ConfigObject->Get('SMTPNotification::From') || $ConfigObject->Get('AdminEmail');

    if ( !$SMTPHost ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'SMTPDirect: No SMTP host configured!',
        );
        return;
    }

    # Connect to SMTP server
    my $SMTP;
    eval {
        $SMTP = Net::SMTP->new(
            $SMTPHost,
            Port    => $SMTPPort,
            Timeout => 30,
            Debug   => $Param{Debug} || 0,
        );
    };

    if ( !$SMTP ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "SMTPDirect: Cannot connect to $SMTPHost:$SMTPPort - $@",
        );
        return;
    }

    # Say hello
    $SMTP->hello( $ConfigObject->Get('FQDN') || 'localhost' );

    # Start TLS if needed
    if ( $Encryption eq 'starttls' || ( $Encryption eq 'auto' && $SMTPPort == 587 ) ) {
        if ( !$SMTP->starttls() ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => 'SMTPDirect: STARTTLS failed',
            );
            $SMTP->quit();
            return;
        }
        # Say hello again after STARTTLS
        $SMTP->hello( $ConfigObject->Get('FQDN') || 'localhost' );
    }

    # Authenticate if credentials provided
    if ( $SMTPUser && $SMTPPass ) {
        if ( !$SMTP->auth( $SMTPUser, $SMTPPass ) ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => 'SMTPDirect: Authentication failed',
            );
            $SMTP->quit();
            return;
        }
    }

    # Prepare email addresses
    my @ToAddresses = ref $Param{To} eq 'ARRAY' ? @{ $Param{To} } : ( $Param{To} );
    
    # Send email
    if ( !$SMTP->mail($FromEmail) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "SMTPDirect: Failed to set sender: " . $SMTP->message(),
        );
        $SMTP->quit();
        return;
    }

    # Add recipients
    my $RecipientError;
    for my $Recipient (@ToAddresses) {
        if ( !$SMTP->to($Recipient) ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "SMTPDirect: Failed to add recipient $Recipient: " . $SMTP->message(),
            );
            $RecipientError = 1;
        }
    }

    if ($RecipientError) {
        $SMTP->quit();
        return;
    }

    # Send data
    if ( !$SMTP->data() ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "SMTPDirect: Failed to start data: " . $SMTP->message(),
        );
        $SMTP->quit();
        return;
    }

    # Build email headers and body
    my $Charset  = $Param{Charset} || 'utf-8';
    my $MimeType = $Param{MimeType} || 'text/plain';
    
    # Send headers
    $SMTP->datasend("From: $FromEmail\n");
    $SMTP->datasend("To: " . join( ', ', @ToAddresses ) . "\n");
    $SMTP->datasend("Subject: $Param{Subject}\n");
    $SMTP->datasend("MIME-Version: 1.0\n");
    $SMTP->datasend("Content-Type: $MimeType; charset=$Charset\n");
    $SMTP->datasend("Content-Transfer-Encoding: 8bit\n");
    $SMTP->datasend("X-Mailer: MSST-Lite SMTPDirect\n");
    
    # Add custom headers if provided
    if ( $Param{Headers} && ref $Param{Headers} eq 'HASH' ) {
        for my $Header ( keys %{ $Param{Headers} } ) {
            $SMTP->datasend("$Header: $Param{Headers}->{$Header}\n");
        }
    }
    
    # Empty line between headers and body
    $SMTP->datasend("\n");
    
    # Send body
    my @Lines = split( /\n/, $Param{Body} );
    for my $Line (@Lines) {
        # Handle lines starting with dot
        if ( $Line =~ /^\./ ) {
            $Line = ".$Line";
        }
        $SMTP->datasend("$Line\n");
    }

    # Finish sending
    if ( !$SMTP->dataend() ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "SMTPDirect: Failed to end data: " . $SMTP->message(),
        );
        $SMTP->quit();
        return;
    }

    # Close connection
    $SMTP->quit();

    $LogObject->Log(
        Priority => 'info',
        Message  => "SMTPDirect: Email sent successfully to " . join( ', ', @ToAddresses ),
    );

    return 1;
}

1;