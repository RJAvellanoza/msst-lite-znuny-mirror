# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::Dashboard::UnassignedIncidents;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed objects
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    my @Params = (
        {
            Desc  => Translatable('Max displayed unassigned incidents'),
            Name  => 'UnassignedIncidentsLimit',
            Block => 'Option',
            Data  => {
                5  => ' 5',
                10 => '10',
                15 => '15',
                20 => '20',
                25 => '25',
            },
            SelectedID => $Self->{Config}->{Limit} || 10,
        },
    );

    return @Params;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },
        CacheKey => 'UnassignedIncidents-' . $Kernel::OM->Get('Kernel::Output::HTML::Layout')->{UserLanguage},
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject       = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $OperationalKPIsObj = $Kernel::OM->Get('Kernel::System::OperationalKPIs');
    my $TicketObject       = $Kernel::OM->Get('Kernel::System::Ticket');

    # Get limit from preferences or config
    my $Limit = $Self->{Config}->{Limit} || 10;

    # Get unassigned incidents
    my @UnassignedIncidents = $OperationalKPIsObj->GetLiveUnassignedDashboard();

    # Limit results
    my @DisplayedIncidents = @UnassignedIncidents[ 0 .. $Limit - 1 ];

    if ( !@UnassignedIncidents ) {
        $LayoutObject->Block(
            Name => 'NoUnassigned',
        );
    }
    else {
        # Show count summary
        $LayoutObject->Block(
            Name => 'Summary',
            Data => {
                TotalCount => scalar(@UnassignedIncidents),
                DisplayedCount => scalar(@DisplayedIncidents),
            },
        );

        # Display each incident
        for my $Incident (@DisplayedIncidents) {
            my %TicketData = $TicketObject->TicketGet(
                TicketID => $Incident->{TicketID},
                UserID   => $Self->{UserID},
            );

            # Priority coloring
            my $PriorityClass = 'Priority' . $Incident->{Priority};
            $PriorityClass =~ s/[^a-zA-Z0-9]//g;  # Remove special chars

            $LayoutObject->Block(
                Name => 'IncidentRow',
                Data => {
                    TicketNumber  => $Incident->{TicketNumber},
                    Title         => $Incident->{Title},
                    Priority      => $Incident->{Priority},
                    PriorityClass => $PriorityClass,
                    Age           => $Incident->{Age},
                    Source        => $Incident->{Source},
                    TicketLink    => "Action=AgentIncidentForm&Subaction=Update&IncidentNumber=$Incident->{TicketNumber}",
                },
            );
        }

        # Show "view all" link if there are more
        if ( scalar(@UnassignedIncidents) > $Limit ) {
            $LayoutObject->Block(
                Name => 'ViewAll',
                Data => {
                    RemainingCount => scalar(@UnassignedIncidents) - $Limit,
                },
            );
        }
    }

    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardUnassignedIncidents',
        Data         => {
            %{ $Self->{Config} },
        },
    );

    return $Content;
}

1;
