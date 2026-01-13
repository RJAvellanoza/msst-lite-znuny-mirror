# --
# Copyright (C) 2025 MSSTLite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::TicketCreateOverride;

use strict;
use warnings;

# This variable will store the TypeID during ticket creation
our $CurrentTypeID;

# Store original methods before they're loaded
our ($OriginalTicketCreate, $OriginalTicketCreateNumber);

# Apply overrides - this is called after ObjectManager initialization
sub Apply {
    # Only apply once
    return if $OriginalTicketCreate;
    
    warn "MSSTLite: Applying ticket prefix overrides\n";
    
    # Force load Ticket module if not already loaded
    eval { require Kernel::System::Ticket; };
    
    # Store originals
    $OriginalTicketCreate = \&Kernel::System::Ticket::TicketCreate;
    $OriginalTicketCreateNumber = \&Kernel::System::Ticket::TicketCreateNumber;
    
    # Override TicketCreate
    no warnings 'redefine';
    *Kernel::System::Ticket::TicketCreate = sub {
        my ( $Self, %Param ) = @_;
        
        warn "MSSTLite Override: TicketCreate called with TypeID: " . ($Param{TypeID} || 'none') . "\n" if $Param{TypeID};
        
        # Store TypeID for TicketCreateNumber to use
        local $CurrentTypeID = $Param{TypeID};
        
        # Call original
        return $OriginalTicketCreate->($Self, %Param);
    };
    
    # Override TicketCreateNumber
    *Kernel::System::Ticket::TicketCreateNumber = sub {
        my ( $Self, %Param ) = @_;
        
        # Get the number generator module
        my $GeneratorModule = $Kernel::OM->Get('Kernel::Config')->Get('Ticket::NumberGenerator') || '';
        
        # If we have a stored TypeID and using our custom generator, pass it along
        if ($CurrentTypeID && $GeneratorModule eq 'Kernel::System::Ticket::Number::AutoIncrementWithPrefix') {
            warn "MSSTLite Override: TicketCreateNumber - Passing TypeID $CurrentTypeID to custom generator\n";
            
            return $Kernel::OM->Get($GeneratorModule)->TicketCreateNumber(
                %Param,
                TypeID => $CurrentTypeID,
            );
        }
        
        # Otherwise use standard call
        return $OriginalTicketCreateNumber->($Self, %Param);
    };
}

# Auto-apply when module loads
Apply();

1;