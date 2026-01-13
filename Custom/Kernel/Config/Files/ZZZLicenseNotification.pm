# --
# Custom configuration for License Notification
# --

package Kernel::Config::Files::ZZZLicenseNotification;

use strict;
use warnings;
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # License notification settings
    $Self->{'License::ExpirationNotification::Enabled'} = 1;
    $Self->{'License::ExpirationNotification::DaysBeforeExpiry'} = 60;
    $Self->{'License::ExpirationNotification::MessageTemplate'} = 'Your license will be expiring in %s days. Please contact Motorola Solutions for service contract renewal.';
    $Self->{'License::ExpirationNotification::ExpiredMessageTemplate'} = 'Your license has expired. Please contact Motorola Solutions for license renewal.';
    $Self->{'License::ExpirationNotification::ContactNumber'} = '';
    
    # Register the output filter
    $Self->{'Frontend::Output::FilterContent'}->{'LicenseExpirationNotification'} = {
        Module => 'Kernel::Output::HTML::FilterContent::LicenseExpirationNotification',
    };
    
    # Register the AJAX module
    $Self->{'Frontend::Module'}->{'AgentLicenseNotificationDismiss'} = {
        Description => 'AJAX handler for dismissing license notification',
        Title => 'License Notification Dismiss',
        Group => ['users'],
        GroupRo => [],
        NavBarName => '',
    };

    return 1;
}

1;