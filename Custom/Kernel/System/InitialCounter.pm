# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::InitialCounter;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Valid',
);

=head1 NAME

Kernel::System::InitialCounter - InitialCounter lib

=head1 DESCRIPTION

All ticket priority functions.

=head1 PUBLIC INTERFACE

=head2 new()

create an object

    my $InitialCounterObject = $Kernel::OM->Get('Kernel::System::InitialCounter');


=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # $Self->{CacheType} = 'Priority';
    # $Self->{CacheTTL}  = 60 * 60 * 24 * 20;

    return $Self;
}

sub InitialCounterGet {
    my ( $Self, %Param ) = @_;

   
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Check if table exists and ask database
    my $Success = $DBObject->Prepare(
        SQL => 'select counter from ticket_initial_counter',
        Silent => 1,
    );
    
    # Return undef if table doesn't exist or query fails
    return if !$Success;

    # fetch the result
    my $Counter;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Counter = $Row[0];           
    } 

    return $Counter;
}



sub InitialCounterAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Counter UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    return if !$DBObject->Do(
        SQL => 'delete from ticket_initial_counter'           
    );
    # Don't delete ticket_number_counter - it maintains the current counter state
    # Only reset it if explicitly requested or if the new initial counter is higher
    # than the current max counter

    return if !$DBObject->Do(
        SQL => 'INSERT INTO ticket_initial_counter  (counter, create_time, create_by) VALUES (?, current_timestamp, ?)',            
        Bind => [
            \$Param{Counter},\$Param{UserID}
        ],
    );

    # get new priority id
    return if !$DBObject->Prepare(
        SQL   => 'SELECT id FROM ticket_initial_counter',
    );

    # fetch the result
    my $ID;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $ID = $Row[0];
    }

    return if !$ID;
    
    return $ID;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<https://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut
