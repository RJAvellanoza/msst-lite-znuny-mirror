# --
# Copyright (C) 2025 MSST-Lite
# --
# Force-enable event modules that should always be active
# --

package Kernel::Config::Files::ZZZZEventModules;

use strict;
use warnings;
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # SMTP notification is now configured via XML/SysConfig
    # Removed duplicate registration to prevent sending emails twice
    
    return 1;
}

1;