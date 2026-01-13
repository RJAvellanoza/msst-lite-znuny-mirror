# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::TicketPrefix;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Valid',
);

=head1 NAME

Kernel::System::TicketPrefix - TicketPrefix lib

=head1 DESCRIPTION

All ticket priority functions.

=head1 PUBLIC INTERFACE

=head2 new()

create an object

    my $PriorityObject = $Kernel::OM->Get('Kernel::System::TicketPrefix');


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



sub PrefixList {
    my ( $Self, %Param ) = @_;

    # check valid param
    if ( !defined $Param{Valid} ) {
        $Param{Valid} = 1;
    }
   

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # create sql
    my $SQL = 'SELECT id, prefix FROM ticket_prefix ';
    if ( $Param{Valid} ) {
        $SQL
            .= "WHERE valid_id IN (1,2,3)";
    }

    return if !$DBObject->Prepare( SQL => $SQL );

    # fetch the result
    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Data{ $Row[0] } = $Row[1];
    } 

    return %Data;
}




sub PrefixGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(PrefixID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }   

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # ask database
    return if !$DBObject->Prepare(
        SQL => 'SELECT tp.id, tt.name as Type, tp.Prefix, tp.valid_id, tp.create_time, tp.create_by, tp.type as TypeID '
            . 'FROM ticket_prefix tp, ticket_type tt  WHERE tp.type = tt.id and tp.id = ?',
        Bind  => [ \$Param{PrefixID} ],
        Limit => 1,
    );

    # fetch the result
    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Data{ID}         = $Row[0];
        $Data{Type}       = $Row[1];
        $Data{Prefix}     = $Row[2];
        $Data{ValidID}    = $Row[3];
        $Data{CreateTime} = $Row[4];
        $Data{CreateBy}   = $Row[5]; 
        $Data{TypeID}     = $Row[6];      
    }

    # set cache
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => 'PriorityGet' . $Param{PriorityID},
        Value => \%Data,
    );

    return %Data;
}



sub PrefixAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(TypeID Prefix ValidID UserID)) {
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
        SQL => 'INSERT INTO ticket_prefix (type, prefix, valid_id, create_time, create_by) VALUES (?, ?, ?, current_timestamp, ?)',            
        Bind => [
            \$Param{TypeID}, \$Param{Prefix}, \$Param{ValidID}, \$Param{UserID}
        ],
    );

    # get new priority id
    return if !$DBObject->Prepare(
        SQL   => 'SELECT id FROM ticket_prefix WHERE prefix = ?',
        Bind  => [ \$Param{Prefix} ],
        Limit => 1,
    );

    # fetch the result
    my $ID;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $ID = $Row[0];
    }

    return if !$ID;
    
    return $ID;
}


sub PrefixUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(PrefixID TypeID Prefix ValidID)) {
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
        SQL => 'UPDATE ticket_prefix SET type = ?, prefix = ?, valid_id = ? WHERE id = ?',        
        Bind => [
            \$Param{TypeID}, \$Param{Prefix}, \$Param{ValidID}, \$Param{PrefixID},
        ],
    );

    return 1;
}


sub PrefixDuplicate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(TypeID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }   

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # ask database
    return if !$DBObject->Prepare(
        SQL => 'Select id from ticket_prefix where type = ? and valid_id = 1',
        Bind  => [ \$Param{TypeID} ],
        Limit => 1,
    );

    # fetch the result
    my $Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Data         = $Row[0];         
    }
    return $Data || 0;

}

sub GetTNPrefixByType {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(TypeID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }   

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # ask database
    return if !$DBObject->Prepare(
        SQL => 'Select prefix from ticket_prefix where type = ? and valid_id = 1',
        Bind  => [ \$Param{TypeID} ],
        Limit => 1,
    );

    # fetch the result
    my $prefix;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $prefix         = $Row[0];         
    }
    return $prefix || "";

}

sub GetPrefixListCount {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Valid)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }   

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # ask database
    return if !$DBObject->Prepare(
        SQL => 'Select count(*) from ticket_prefix where valid_id = ?',
        Bind  => [ \$Param{Valid} ],
    );

    # fetch the result
    my $prefixcount;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $prefixcount = $Row[0];         
    }
    return $prefixcount || 0;

}


1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<https://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut
