# --
# Fix Reports menu permissions - remove stats group requirement
# --

package Kernel::Config::Files::ZZZZZZReportsMenuPermissions;

use strict;
use warnings;
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # Change Operational Reports Navigation to not require stats group
    if ($Self->{'Frontend::Navigation'}->{'AgentOperationalReports'}->{'001-OperationalReports'}) {
        for my $item (@{$Self->{'Frontend::Navigation'}->{'AgentOperationalReports'}->{'001-OperationalReports'}}) {
            $item->{Group} = [];
            $item->{GroupRo} = [];
        }
    }

    # Change Operational Reports Module to not require stats group
    if ($Self->{'Frontend::Module'}->{'AgentOperationalReports'}) {
        $Self->{'Frontend::Module'}->{'AgentOperationalReports'}->{Group} = [];
        $Self->{'Frontend::Module'}->{'AgentOperationalReports'}->{GroupRo} = [];
    }

    # Change Incident Report Navigation to not require stats group
    if ($Self->{'Frontend::Navigation'}->{'AgentIncidentReport'}->{'001-IncidentReport'}) {
        for my $item (@{$Self->{'Frontend::Navigation'}->{'AgentIncidentReport'}->{'001-IncidentReport'}}) {
            $item->{Group} = [];
            $item->{GroupRo} = [];
        }
    }

    # Change Incident Report Module to not require stats group
    if ($Self->{'Frontend::Module'}->{'AgentIncidentReport'}) {
        $Self->{'Frontend::Module'}->{'AgentIncidentReport'}->{Group} = [];
        $Self->{'Frontend::Module'}->{'AgentIncidentReport'}->{GroupRo} = [];
    }

    # Change Incident Reports (new charts) Navigation to not require stats group
    if ($Self->{'Frontend::Navigation'}->{'AgentIncidentReports'}->{'001-IncidentReports'}) {
        for my $item (@{$Self->{'Frontend::Navigation'}->{'AgentIncidentReports'}->{'001-IncidentReports'}}) {
            $item->{Group} = [];
            $item->{GroupRo} = [];
        }
    }

    # Change Incident Reports (new charts) Module to not require stats group
    if ($Self->{'Frontend::Module'}->{'AgentIncidentReports'}) {
        $Self->{'Frontend::Module'}->{'AgentIncidentReports'}->{Group} = [];
        $Self->{'Frontend::Module'}->{'AgentIncidentReports'}->{GroupRo} = [];
    }

    # Make Statistics require stats group (which nobody has)
    # This hides Statistics while keeping Reports menu visible
    if ($Self->{'Frontend::Navigation'}->{'AgentStatistics'}->{'001-Framework'}) {
        for my $item (@{$Self->{'Frontend::Navigation'}->{'AgentStatistics'}->{'001-Framework'}}) {
            $item->{Group} = ['stats'];
            $item->{GroupRo} = ['stats'];
        }
    }

    return 1;
}

1;
