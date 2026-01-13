# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::License;

use strict;
use warnings;

use MIME::Base64;

our @ObjectDependencies = (
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::Encode',
    'Kernel::System::Log',
    'Kernel::System::Valid',
);

=head1 NAME

Kernel::System::License - standard attachment lib

=head1 DESCRIPTION

All standard attachment functions.

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the constructor directly, use the ObjectManager instead:

    my $AdminAddLicenseObject = $Kernel::OM->Get('Kernel::System::AdminAddLicense');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{CacheType} = 'AdminAddLicense';
    $Self->{CacheTTL}  = 60 * 60 * 24 * 20;

    return $Self;
}

sub AdminLicenseAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Content ContentType Filename UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # encode attachment if it's a postgresql backend!!!
    if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {
        $Kernel::OM->Get('Kernel::System::Encode')->EncodeOutput( \$Param{Content} );
        $Param{Content} = encode_base64( $Param{Content} );
    }

    return if !$DBObject->Do(
        SQL => 'delete from license'           
    );
    
    # insert attachment
    return if !$DBObject->Do(
        SQL => 'INSERT INTO license (content_type, content, filename, create_time, create_by) VALUES (?, ?, ?, current_timestamp, ?)',
        Bind => [\$Param{ContentType}, \$Param{Content}, \$Param{Filename},\$Param{UserID}],
    );

    return 1;
}

sub AdminLicenseGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ID!',
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # sql
    return if !$DBObject->Prepare(
        SQL => 'SELECT filename, content_type, content, '
            . 'create_time, create_by '
            . 'FROM license WHERE id = ?',
        Bind   => [ \$Param{ID} ],
        Encode => [ 1, 1, 0, 1, 1, 1 ],
    );

    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {

        # decode attachment if it's a postgresql backend!!!
        if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {
            $Row[2] = decode_base64( $Row[2] );
        }
        %Data = (
            ID          => $Param{ID},
            Filename    => $Row[0],
            ContentType => $Row[1],
            Content     => $Row[2],
            CreateTime  => $Row[3],
            CreateBy    =>$Row[4],
            
        );
    }

    return %Data;
}



sub AdminLicenseList {
    my ( $Self, %Param ) = @_;

    # build SQL
    my $SQL = "SELECT id, filename, create_time FROM license";

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # get data from database
    return if !$DBObject->Prepare(
        SQL => $SQL,
    );

    # fetch the result
    my %AdminAddLicenseList;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $AdminAddLicenseList{id} = $Row[0];
        $AdminAddLicenseList{filename} = $Row[1];
        $AdminAddLicenseList{CreateTime} = $Row[2];
    }

    return %AdminAddLicenseList;
}

1;