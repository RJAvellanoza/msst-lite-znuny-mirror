# --
# Copyright (C) 2024 Radiant Digital, radiant.digital
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AgentTicketZoom;

use strict;
use warnings;

# Get the original module path before we override
our $ORIGINAL_MODULE_PATH = $INC{'Kernel/Modules/AgentTicketZoom.pm'} || '/opt/znuny-6.5.15/Kernel/Modules/AgentTicketZoom.pm';

# Load the original module by manipulating the include path
BEGIN {
    # Remove our custom path from @INC temporarily
    my @original_inc = @INC;
    @INC = grep { $_ !~ m{/opt/znuny/msst-lite-znuny} } @INC;
    
    # Load the original Znuny module
    eval {
        if (-e '/opt/znuny-6.5.15/Kernel/Modules/AgentTicketZoom.pm') {
            require '/opt/znuny-6.5.15/Kernel/Modules/AgentTicketZoom.pm';
        }
    };
    
    # Restore @INC
    @INC = @original_inc;
}

our @ObjectDependencies = (
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Ticket',
    'Kernel::System::Web::Request',
);

# Store reference to original new and Run methods
my $original_package = 'Kernel::Modules::AgentTicketZoom';

sub new {
    my ( $Type, %Param ) = @_;

    # Create instance using original constructor if available
    my $Self;
    
    # Try to find and use the original new method from the loaded module
    if (defined &{$original_package . '::new'}) {
        # Create a temporary package to avoid infinite recursion
        my $temp_package = 'OriginalAgentTicketZoom' . $$;
        
        # Create instance with original new method logic
        $Self = {%Param};
        bless( $Self, $Type );
    } else {
        # Fallback constructor
        $Self = {%Param};
        bless( $Self, $Type );
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # Check needed stuff
    if ( !$Self->{TicketID} ) {
        return $LayoutObject->ErrorScreen(
            Message => 'No TicketID is given!',
            Comment => 'Please contact the administrator.',
        );
    }

    # Get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # Check permissions
    my $Access = $TicketObject->TicketPermission(
        Type     => 'ro',
        TicketID => $Self->{TicketID},
        UserID   => $Self->{UserID}
    );

    # Error screen if no access
    if ( !$Access ) {
        return $LayoutObject->NoPermission(
            Message => "This ticket does not exist, or you don't have permissions to access it in its current state.",
            WithHeader => $Self->{Subaction} && $Self->{Subaction} eq 'ArticleUpdate' ? 'no' : 'yes',
        );
    }

    # Get ticket attributes to check the type
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Self->{TicketID},
        DynamicFields => 0,
        UserID        => $Self->{UserID},
    );

    # Check if this is an incident ticket and redirect to incident form
    if ( $Ticket{Type} && $Ticket{Type} eq 'Incident' ) {
        # Redirect to the incident form with the ticket number as incident number
        return $LayoutObject->Redirect(
            OP => "Action=AgentIncidentForm;Subaction=Update;IncidentNumber=$Ticket{TicketNumber}",
        );
    }

    # For non-incident tickets, we need to call the original functionality
    # Load and execute the original module code
    if (-e '/opt/znuny-6.5.15/Kernel/Modules/AgentTicketZoom.pm') {
        # Read the original file
        my $MainObject = $Kernel::OM->Get('Kernel::System::Main');
        my $OriginalCode = $MainObject->FileRead(
            Location => '/opt/znuny-6.5.15/Kernel/Modules/AgentTicketZoom.pm',
        );
        
        if ($OriginalCode && ${$OriginalCode}) {
            # Create a unique package name to avoid conflicts
            my $TempPackage = 'Kernel::Modules::AgentTicketZoomOriginal' . time() . $$;
            my $Code = ${$OriginalCode};
            
            # Replace the package name
            $Code =~ s/package\s+Kernel::Modules::AgentTicketZoom/package $TempPackage/g;
            
            # Evaluate the code in our namespace
            eval $Code;
            
            if (!$@) {
                # Create instance and call Run method
                my $OriginalInstance = $TempPackage->new(%{$Self});
                if ($OriginalInstance && $OriginalInstance->can('Run')) {
                    return $OriginalInstance->Run(%Param);
                }
            }
        }
    }

    # Final fallback - basic error message
    return $LayoutObject->ErrorScreen(
        Message => 'Unable to display ticket details.',
        Comment => 'Please use the ticket list to access tickets.',
    );
}

1;