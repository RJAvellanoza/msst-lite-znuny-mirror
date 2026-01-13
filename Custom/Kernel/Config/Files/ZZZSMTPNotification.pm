# --
# Custom configuration for SMTP Notification Module
# --

package Kernel::Config::Files::ZZZSMTPNotification;

use strict;
use warnings;
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # SMTP Notification Navigation Module
    $Self->{'Frontend::NavigationModule'}->{'AdminSMTPNotification'} = {
        'Group' => [
            'admin',
            'MSIAdmin',
            'NOCAdmin'
        ],
        'GroupRo' => [],
        'Module' => 'Kernel::Output::HTML::NavBar::ModuleAdmin',
        'Name' => 'SMTP Notification',
        'Block' => 'MSSTLite',
        'Description' => 'Configure SMTP notification settings and priority rules',
        'IconBig' => 'fa-envelope-o',
        'IconSmall' => 'fa-envelope-o',
        'Prio' => '920',
    };

    # SMTP Notification Frontend Module
    $Self->{'Frontend::Module'}->{'AdminSMTPNotification'} = {
        'GroupRo' => [],
        'Group' => [
            'admin',
            'MSIAdmin',
            'NOCAdmin'
        ],
        'Description' => 'Configure SMTP notification settings and priority rules.',
        'Title' => 'SMTP Notification',
        'NavBarName' => 'Admin',
    };

    return 1;
}

1;