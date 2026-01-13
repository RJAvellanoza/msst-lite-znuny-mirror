# --
# Copyright (C) 2025 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::EncryptionKey;

use strict;
use warnings;

use MIME::Base64;

our @ObjectDependencies = (
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::Log',
);

=head1 NAME

Kernel::System::EncryptionKey - Encryption key management

=head1 DESCRIPTION

This module handles storage and retrieval of encryption keys from the database.

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the constructor directly, use the ObjectManager instead:

    my $EncryptionKeyObject = $Kernel::OM->Get('Kernel::System::EncryptionKey');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{CacheType} = 'EncryptionKey';
    $Self->{CacheTTL}  = 60 * 60;  # 1 hour cache

    return $Self;
}

=head2 GetKey()

Get an encryption key from the database

    my $KeyValue = $EncryptionKeyObject->GetKey(
        KeyName => 'license_aes_key',
    );

Returns the key value as binary data or undef if not found.

=cut

sub GetKey {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{KeyName} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need KeyName!",
        );
        return;
    }

    # check cache first
    my $CacheKey = 'GetKey::' . $Param{KeyName};
    my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return $Cache if defined $Cache;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # get key from database
    return if !$DBObject->Prepare(
        SQL   => 'SELECT key_value FROM encryption_keys WHERE key_name = ?',
        Bind  => [ \$Param{KeyName} ],
        Limit => 1,
    );

    my $KeyValue;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $KeyValue = $Row[0];
        
        # decode if PostgreSQL (base64 encoded in DB)
        if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {
            $KeyValue = decode_base64($KeyValue);
        }
    }

    if ( !defined $KeyValue ) {
        # Note: It's normal for a key to not exist on first use
        # Only log as debug to avoid cluttering error logs
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'debug',
            Message  => "Encryption key '$Param{KeyName}' not found in database (will be created if needed)",
        );
        return;
    }

    # cache the result
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => $KeyValue,
    );

    return $KeyValue;
}

=head2 SetKey()

Store an encryption key in the database

    my $Success = $EncryptionKeyObject->SetKey(
        KeyName  => 'license_aes_key',
        KeyValue => $BinaryKeyData,
        UserID   => 1,
    );

Returns 1 on success, undef on error.

=cut

sub SetKey {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(KeyName KeyValue UserID)) {
        if ( !defined $Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $KeyValue = $Param{KeyValue};
    
    # encode for PostgreSQL
    if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {
        $KeyValue = encode_base64($KeyValue, '');
    }

    # check if key already exists
    return if !$DBObject->Prepare(
        SQL   => 'SELECT id FROM encryption_keys WHERE key_name = ?',
        Bind  => [ \$Param{KeyName} ],
        Limit => 1,
    );

    my $Exists;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Exists = 1;
    }

    my $Success;
    if ($Exists) {
        # update existing key
        $Success = $DBObject->Do(
            SQL => 'UPDATE encryption_keys SET key_value = ?, created_time = current_timestamp, created_by = ? WHERE key_name = ?',
            Bind => [ \$KeyValue, \$Param{UserID}, \$Param{KeyName} ],
        );
    }
    else {
        # insert new key
        $Success = $DBObject->Do(
            SQL => 'INSERT INTO encryption_keys (key_name, key_value, created_time, created_by) VALUES (?, ?, current_timestamp, ?)',
            Bind => [ \$Param{KeyName}, \$KeyValue, \$Param{UserID} ],
        );
    }

    if (!$Success) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Failed to store encryption key '$Param{KeyName}'!",
        );
        return;
    }

    # clear cache
    $Kernel::OM->Get('Kernel::System::Cache')->Delete(
        Type => $Self->{CacheType},
        Key  => 'GetKey::' . $Param{KeyName},
    );

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST project.

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut