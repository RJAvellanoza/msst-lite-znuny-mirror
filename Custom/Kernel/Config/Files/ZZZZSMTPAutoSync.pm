# --
# Copyright (C) 2025 MSST-Lite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --
# Auto-sync SMTP settings to SendmailModule settings
# --

package Kernel::Config::Files::ZZZZSMTPAutoSync;

use strict;
use warnings;
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # Only sync if SMTPNotification settings exist
    if ( $Self->{'SMTPNotification::Host'} ) {
        
        # Get SMTP notification settings
        my $Host       = $Self->{'SMTPNotification::Host'} || '';
        my $Port       = $Self->{'SMTPNotification::Port'} || '';
        my $AuthUser   = $Self->{'SMTPNotification::AuthUser'} || '';
        my $AuthPass   = $Self->{'SMTPNotification::AuthPassword'} || '';
        my $Encryption = $Self->{'SMTPNotification::Encryption'} || 'none';
        my $Module     = $Self->{'SMTPNotification::Module'} || 'auto';
        
        # Determine correct SMTP module
        my $SMTPModule;
        if ( $Module ne 'auto' ) {
            $SMTPModule = $Module;
        }
        else {
            if ( $Encryption eq 'ssl' || $Port eq '465' ) {
                $SMTPModule = 'Kernel::System::Email::SMTPS';
            }
            elsif ( $Encryption eq 'starttls' || $Port eq '587' ) {
                $SMTPModule = 'Kernel::System::Email::SMTPTLS';
            }
            else {
                $SMTPModule = 'Kernel::System::Email::SMTP';
            }
        }
        
        # Override SendmailModule settings with SMTPNotification values
        $Self->{'SendmailModule'} = $SMTPModule;
        $Self->{'SendmailModule::Host'} = $Host;
        $Self->{'SendmailModule::Port'} = $Port;
        $Self->{'SendmailModule::AuthUser'} = $AuthUser;
        $Self->{'SendmailModule::AuthPassword'} = $AuthPass;
    }
    
    return 1;
}

1;