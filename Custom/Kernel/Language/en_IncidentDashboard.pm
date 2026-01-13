# --
# MSSTLITE-88: Incident Dashboard Language Customizations
# --

package Kernel::Language::en_IncidentDashboard;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    # Override Owner to show as "Assigned To" in dashboard context
    $Self->{Translation}->{'Owner'} = 'Assigned To';

    # Override Title to show as "Short Description" in dashboard context
    $Self->{Translation}->{'Title'} = 'Short Description';

    # Override QueueView to be two words
    $Self->{Translation}->{'QueueView'} = 'Queue View';

    return 1;
}

1;