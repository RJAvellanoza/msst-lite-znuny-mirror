package Kernel::Config::Files::ZZZZTicketTypeDefault;

use strict;
use warnings;

sub Load {
    my ($File, $Self) = @_;

    # Override the default ticket type to Incident
    $Self->{'Ticket::Type::Default'} = 'Incident';

    return 1;
}

1;