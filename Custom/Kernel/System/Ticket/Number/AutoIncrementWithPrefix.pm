# --
# Copyright (C) 2025 MSSTLite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Ticket::Number::AutoIncrementWithPrefix;

use strict;
use warnings;

use parent qw(Kernel::System::Ticket::Number::AutoIncrement);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::DateTime',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Ticket',
    'Kernel::System::TicketPrefix',
    'Kernel::System::InitialCounter',
);

sub TicketNumberBuild {
    my ( $Self, %Param ) = @_;

    # Check for counter
    return if !$Param{Counter};

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Get min counter size (default 5)
    my $MinSize = $ConfigObject->Get('Ticket::NumberGenerator::AutoIncrement::MinCounterSize')
        || $ConfigObject->Get('Ticket::NumberGenerator::MinCounterSize')
        || 5;

    # Pad counter with leading zeros
    my $Counter = sprintf "%.*u", $MinSize, $Param{Counter};

    $LogObject->Log(
        Priority => 'notice',
        Message  => "TicketNumberBuild - Counter: $Counter, TypeID: " . ($Param{TypeID} || 'none'),
    );

    # If TypeID is provided, add prefix
    if ( $Param{TypeID} ) {
        my $TicketPrefixObject = $Kernel::OM->Get('Kernel::System::TicketPrefix');
        my $TypePrefixString = $TicketPrefixObject->GetTNPrefixByType( TypeID => $Param{TypeID} );
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "TicketNumberBuild - Prefix for TypeID $Param{TypeID}: " . ($TypePrefixString || 'none'),
        );
        
        if ( $TypePrefixString ) {
            # Check if prefix already ends with dash to prevent double-dash
            if ( $TypePrefixString =~ /-$/ ) {
                return $TypePrefixString . $Counter;
            } else {
                return $TypePrefixString . '-' . $Counter;
            }
        }
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => "TicketNumberBuild - No TypeID or prefix found, returning counter with SystemID",
    );

    # Return just the counter without SystemID if no prefix
    return $Counter;
}

sub GetTNByString {
    my ( $Self, $String ) = @_;

    return if !$String;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $TicketHook        = $ConfigObject->Get('Ticket::Hook');
    my $TicketHookDivider = $ConfigObject->Get('Ticket::HookDivider');
    my $MinSize           = $ConfigObject->Get('Ticket::NumberGenerator::AutoIncrement::MinCounterSize')
        || $ConfigObject->Get('Ticket::NumberGenerator::MinCounterSize')
        || 5;
    my $MaxSize = $MinSize + 5;

    # Check for ticket number with prefix pattern
    # Matches: [Hook][Divider][PREFIX]-[NUMBER] or just [Hook][Divider][NUMBER]
    if ( $String =~ /\Q$TicketHook$TicketHookDivider\E([\w]+-\d{$MinSize,$MaxSize}|\d{$MinSize,$MaxSize})/i ) {
        return $1;
    }

    # Also check without hook/divider
    if ( $String =~ /([\w]+-\d{$MinSize,$MaxSize}|\d{$MinSize,$MaxSize})/ ) {
        return $1;
    }

    return;
}

sub TicketCreateNumber {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Store TypeID for later use
    my $TypeID = $Param{TypeID};
    
    $LogObject->Log(
        Priority => 'notice', 
        Message  => "TicketCreateNumber called with TypeID: " . ($TypeID || 'none') . ", Params: " . join(", ", map { "$_=$Param{$_}" } keys %Param),
    );
    
    # Delete TypeID from %Param to avoid passing it to parent methods
    delete $Param{TypeID};

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    
    # Get initial counter if set
    my $InitialCounterObject = $Kernel::OM->Get('Kernel::System::InitialCounter');
    my $InitialCounter = $InitialCounterObject->InitialCounterGet() || 0;
    
    # Get current max counter value FIRST
    return if !$DBObject->Prepare(
        SQL => 'SELECT MAX(counter) FROM ticket_number_counter',
    );
    
    my $CurrentCounter = 0;
    while (my @Row = $DBObject->FetchrowArray()) {
        $CurrentCounter = $Row[0] || 0;
    }
    
    # Apply initial counter if needed
    if ($InitialCounter && $CurrentCounter < $InitialCounter) {
        $CurrentCounter = $InitialCounter - 1; # -1 because we'll increment below
    }
    
    # Increment counter
    my $NewCounter = $CurrentCounter + 1;
    
    # Create counter entry with new value
    my $CounterUID = $Self->_GetUID();
    
    # Insert new counter
    return if !$DBObject->Do(
        SQL => 'INSERT INTO ticket_number_counter (counter, counter_uid, create_time) VALUES (?, ?, current_timestamp)',
        Bind => [ \$NewCounter, \$CounterUID ],
    );
    
    my $Counter = $NewCounter;
    
    $LogObject->Log(
        Priority => 'debug',
        Message  => "TicketCreateNumber - Counter: $Counter, TypeID: " . ($TypeID || 'none'),
    );
    
    # Build ticket number with our format (no SystemID)
    my $TicketNumber = $Self->TicketNumberBuild(
        Counter => $Counter,
        TypeID  => $TypeID,
    );
    
    $LogObject->Log(
        Priority => 'debug',
        Message  => "TicketCreateNumber - Generated: $TicketNumber",
    );
    
    return $TicketNumber;
}

sub _GetUID {
    my ($Self) = @_;
    
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');
    my $TimeObject = $Kernel::OM->Create('Kernel::System::DateTime');
    
    return $MainObject->MD5sum(
        String => $TimeObject->ToEpoch() . int(rand(1000000)),
    );
}

1;