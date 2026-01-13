# --
# Copyright (C) 2025 MSSTLite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Config::Files::ZZZZTicketPrefixOverride;

use strict;
use warnings;
use utf8;

# Load and apply the ticket create override
use Kernel::System::TicketCreateOverride;

sub Load {
    my ($File, $Self) = @_;

    # Override ticket number generator to use our custom prefix version
    $Self->{'Ticket::NumberGenerator'} = 'Kernel::System::Ticket::Number::AutoIncrementWithPrefix';
    
    # Set initial counter to 1000
    $Self->{'Ticket::NumberGenerator::InitialCounter'} = 1000;
    
    # Set counter size to 10 digits
    $Self->{'Ticket::NumberGenerator::MinCounterSize'} = 10;
    $Self->{'Ticket::NumberGenerator::AutoIncrement::MinCounterSize'} = 10;

    return 1;
}

1;