# --
# Custom configuration for Admin License Module
# --

package Kernel::Config::Files::ZZZAdminLicense;

use strict;
use warnings;
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # Register MSSTLite block for admin overview
    $Self->{'Frontend::AdminModuleGroups'}->{'001-Framework'}->{'MSSTLite'} = {
        'Title' => 'LSMP Configuration',
        'Order' => 50,  # Low number = appears at top
        'Group' => [
            'admin',
            'MSIAdmin',
            'NOCAdmin'
        ],
        'GroupRo' => [],
    };

    # NOTE: AdminAddLicense permissions are centrally managed in ZZZZZNOCAdminNavigation.pm
    # Do not define Group/GroupRo settings here to avoid conflicts

    # User Details Preferences
    $Self->{'PreferencesGroups'}->{'UserDetails'} = {
        'Module' => 'Kernel::Output::HTML::Preferences::UserDetails',
        'PreferenceGroup' => 'UserProfile',
        'Label' => 'User Details',
        'Key' => 'User Details',
        'Desc' => 'Change your details.',
        'Block' => 'User Details',
        'Prio' => '1001',
        'Active' => '1',
    };

    return 1;
}

1;
