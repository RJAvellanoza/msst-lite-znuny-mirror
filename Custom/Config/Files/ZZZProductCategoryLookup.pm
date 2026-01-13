# Kernel/Config/Files/ZZZProductCategoryLookup.pm
#
# This file registers the custom Generic Agent module.

package Kernel::Config::Files::ZZZProductCategoryLookup;

use strict;
use warnings;

sub Load {
    my ($File, $Self) = @_;

    # Register the new Generic Agent module
    $Self->{'GenericAgent::Modules'}->{'ProductCategoryLookup'} = {
        Module => 'Kernel::System::GenericAgent::ProductCategoryLookup',
        Name   => 'Product Category Lookup',
    };

    return 1;
}

1;
