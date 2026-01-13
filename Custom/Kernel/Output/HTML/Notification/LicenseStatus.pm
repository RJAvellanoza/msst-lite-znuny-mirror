# --
# Kernel/Output/HTML/Notification/LicenseStatus.pm - License status notification
# Copyright (C) 2025 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::Notification::LicenseStatus;

use parent 'Kernel::Output::HTML::Base';

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
);

sub Run {
    my ( $Self, %Param ) = @_;
    
    # Get objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    # Check if license checking is enabled
    return '' if !$ConfigObject->Get('LicenseCheck::Enabled');
    
    # Get license status from LayoutObject (set by PreApplication module)
    my $LicenseStatus = $LayoutObject->{UserLicenseStatus} || '';
    
    # No notification for valid licenses or no status
    return '' if !$LicenseStatus || $LicenseStatus eq 'Valid';
    
    # Skip notification on certain pages
    my $Action = $Param{Action} || '';
    return '' if $Action eq 'AdminAddLicense';
    
    # Determine message and priority based on status
    my ($Message, $Priority);
    
    if ($LicenseStatus eq 'Expired') {
        $Priority = 'Error';
        $Message = $LayoutObject->{LanguageObject}->Translate(
            'Your license has expired. Some features may be restricted.'
        );
    }
    elsif ($LicenseStatus eq 'Invalid') {
        $Priority = 'Error';
        $Message = $LayoutObject->{LanguageObject}->Translate(
            'Invalid license detected. Some features may be restricted.'
        );
    }
    elsif ($LicenseStatus eq 'Unavailable') {
        $Priority = 'Warning';
        $Message = $LayoutObject->{LanguageObject}->Translate(
            'No license found. Please add a valid license to access all features.'
        );
    }
    else {
        # Unknown status
        return '';
    }
    
    # Add admin-specific message
    if ($LayoutObject->{UserIsLicenseAdmin}) {
        my $Link = $LayoutObject->{Baselink} . 'Action=AdminAddLicense';
        $Message .= ' <a href="' . $Link . '" class="Button">' 
                  . $LayoutObject->{LanguageObject}->Translate('Manage License') 
                  . '</a>';
    }
    else {
        $Message .= ' ' . $LayoutObject->{LanguageObject}->Translate(
            'Please contact your system administrator.'
        );
    }
    
    # Create notification HTML
    my $NotificationHTML = $LayoutObject->Notify(
        Priority => $Priority,
        Info     => $Message,
    );
    
    return $NotificationHTML;
}

1;