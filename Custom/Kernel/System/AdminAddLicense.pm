# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::AdminAddLicense;

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

Kernel::System::AdminAddLicense - standard attachment lib

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

=head2 AdminAddLicenseAdd()

create a new standard attachment

    my $ID = $AdminAddLicenseObject->AdminAddLicenseAdd(
        Name        => 'Some Name',
        ValidID     => 1,
        Content     => $Content,
        ContentType => 'text/xml',
        Filename    => 'SomeFile.xml',
        UserID      => 123,
    );

=cut

sub AdminAddLicenseAdd {
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
    # Handle both contractNumber and mcn for backward compatibility
    my $mcn = $Param{mcn} || $Param{contractNumber} || '';
    
    return if !$DBObject->Do(
        SQL => 'INSERT INTO license '
            . ' (UID,contractCompany,endCustomer,mcn,macAddress,startDate,endDate,systemTechnology,lsmpSiteID,content_type, content, filename, '
            . ' create_time, create_by) VALUES '
            . ' (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, ?)',
        Bind => [
            \$Param{UID},\$Param{contractCompany},\$Param{endCustomer},\$mcn,\$Param{macAddress}, \$Param{startDate},\$Param{endDate}, 
            \$Param{systemTechnology}, \$Param{lsmpSiteID}, \$Param{ContentType}, \$Param{Content}, \$Param{Filename},
            \$Param{UserID},
        ],
    );

    # # get the id
    # $DBObject->Prepare(
    #     SQL  => 'SELECT id FROM standard_attachment WHERE name = ? AND content_type = ?',
    #     Bind => [ \$Param{Name}, \$Param{ContentType}, ],
    # );

    # # fetch the result
    # my $ID;
    # while ( my @Row = $DBObject->FetchrowArray() ) {
    #     $ID = $Row[0];
    # }

    return 1;
}

=head2 AdminAddLicenseGet()

get a standard attachment

    my %Data = $AdminAddLicenseObject->AdminAddLicenseGet(
        ID => $ID,
    );

=cut

sub AdminAddLicenseGet {
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

=head2 AdminAddLicenseUpdate()

update a new standard attachment

    my $ID = $AdminAddLicenseObject->AdminAddLicenseUpdate(
        ID          => $ID,
        Name        => 'Some Name',
        ValidID     => 1,
        Content     => $Content,
        ContentType => 'text/xml',
        Filename    => 'SomeFile.xml',
        UserID      => 123,
    );

=cut

sub AdminAddLicenseUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(ID Name ValidID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # reset cache
    my %Data = $Self->AdminAddLicenseGet(
        ID => $Param{ID},
    );

    $Kernel::OM->Get('Kernel::System::Cache')->Delete(
        Type => $Self->{CacheType},
        Key  => 'AdminAddLicenseLookupID::' . $Data{ID},
    );
    $Kernel::OM->Get('Kernel::System::Cache')->Delete(
        Type => $Self->{CacheType},
        Key  => 'AdminAddLicenseLookupName::' . $Data{Name},
    );
    $Kernel::OM->Get('Kernel::System::Cache')->Delete(
        Type => $Self->{CacheType},
        Key  => 'AdminAddLicenseLookupID::' . $Param{ID},
    );
    $Kernel::OM->Get('Kernel::System::Cache')->Delete(
        Type => $Self->{CacheType},
        Key  => 'AdminAddLicenseLookupName::' . $Param{Name},
    );

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # update attachment
    return if !$DBObject->Do(
        SQL => 'UPDATE standard_attachment SET name = ?, comments = ?, valid_id = ?, '
            . 'change_time = current_timestamp, change_by = ? WHERE id = ?',
        Bind => [
            \$Param{Name}, \$Param{Comment},
            \$Param{ValidID}, \$Param{UserID}, \$Param{ID},
        ],
    );

    if ( $Param{Content} ) {

        # encode attachment if it's a postgresql backend!!!
        if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {
            $Kernel::OM->Get('Kernel::System::Encode')->EncodeOutput( \$Param{Content} );
            $Param{Content} = encode_base64( $Param{Content} );
        }

        return if !$DBObject->Do(
            SQL => 'UPDATE standard_attachment SET content = ?, content_type = ?, '
                . ' filename = ? WHERE id = ?',
            Bind => [
                \$Param{Content}, \$Param{ContentType}, \$Param{Filename}, \$Param{ID},
            ],
        );
    }

    return 1;
}

=head2 AdminAddLicenseDelete()

delete a standard attachment

    $AdminAddLicenseObject->AdminAddLicenseDelete(
        ID => $ID,
    );

=cut

sub AdminAddLicenseDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(ID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # reset cache
    my %Data = $Self->AdminAddLicenseGet(
        ID => $Param{ID},
    );

    $Kernel::OM->Get('Kernel::System::Cache')->Delete(
        Type => $Self->{CacheType},
        Key  => 'AdminAddLicenseLookupID::' . $Param{ID},
    );
    $Kernel::OM->Get('Kernel::System::Cache')->Delete(
        Type => $Self->{CacheType},
        Key  => 'AdminAddLicenseLookupName::' . $Data{Name},
    );

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # delete attachment<->std template relation
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM standard_template_attachment WHERE standard_attachment_id = ?',
        Bind => [ \$Param{ID} ],
    );

    # sql
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM standard_attachment WHERE ID = ?',
        Bind => [ \$Param{ID} ],
    );

    return 1;
}

=head2 AdminAddLicenseLookup()

lookup for a standard attachment

    my $ID = $AdminAddLicenseObject->AdminAddLicenseLookup(
        AdminAddLicense => 'Some Name',
    );

    my $Name = $AdminAddLicenseObject->AdminAddLicenseLookup(
        AdminAddLicenseID => $ID,
    );

=cut

sub AdminAddLicenseLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{AdminAddLicense} && !$Param{AdminAddLicenseID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no AdminAddLicense or AdminAddLicense!',
        );
        return;
    }

    # check if we ask the same request?
    my $CacheKey;
    my $Key;
    my $Value;
    if ( $Param{AdminAddLicenseID} ) {
        $CacheKey = 'AdminAddLicenseLookupID::' . $Param{AdminAddLicenseID};
        $Key      = 'AdminAddLicenseID';
        $Value    = $Param{AdminAddLicenseID};
    }
    else {
        $CacheKey = 'AdminAddLicenseLookupName::' . $Param{AdminAddLicense};
        $Key      = 'AdminAddLicense';
        $Value    = $Param{AdminAddLicense};
    }

    my $Cached = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );

    return $Cached if $Cached;

    # get data
    my $SQL;
    my @Bind;
    if ( $Param{AdminAddLicense} ) {
        $SQL = 'SELECT id FROM standard_attachment WHERE name = ?';
        push @Bind, \$Param{AdminAddLicense};
    }
    else {
        $SQL = 'SELECT name FROM standard_attachment WHERE id = ?';
        push @Bind, \$Param{AdminAddLicenseID};
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    $DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my $DBValue;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $DBValue = $Row[0];
    }

    # check if data exists
    if ( !$DBValue ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Found no $Key found for $Value!",
        );
        return;
    }

    # cache result
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => $DBValue,
    );

    return $DBValue;
}

=head2 AdminAddLicenseList()

get list of standard attachments - return a hash (ID => Name (Filename))

    my %List = $AdminAddLicenseObject->AdminAddLicenseList(
        Valid => 0,  # optional, defaults to 1
    );

returns:

        %List = (
          '1' => 'Some Name' ( Filname ),
          '2' => 'Some Name' ( Filname ),
          '3' => 'Some Name' ( Filname ),
    );

=cut

sub AdminAddLicenseList {
    my ( $Self, %Param ) = @_;

    # build SQL with timezone-aware comparison
    my $SQL = "SELECT id,UID,contractCompany,endCustomer,mcn,macAddress,startDate,endDate,systemTechnology,lsmpSiteID,filename,
       CASE 
         WHEN endDate::date >= NOW()::date THEN (endDate::date - NOW()::date) || ' days'
         ELSE AGE(endDate::timestamp, NOW()::timestamp)::text
       END as remaining_duration,

     CASE        
         WHEN NOW()::date > endDate::date THEN 'Expired'
         WHEN startDate::date <= NOW()::date AND NOW()::date <= endDate::date THEN 'Valid'
         ELSE 'Invalid'
    END AS license_status
    FROM license";
    
    my $SQLx = "SELECT id,UID,contractCompany,endCustomer,mcn,macAddress,startDate,endDate, filename,  
       CONCAT(
           TIMESTAMPDIFF(MONTH, CURDATE(), endDate), ' month(s) ',
           DATEDIFF(endDate, DATE_ADD(CURDATE(), INTERVAL TIMESTAMPDIFF(MONTH, CURDATE(), endDate) MONTH)), ' day(s)'
       ) AS remaining_duration,

     CASE        
         WHEN CURDATE() > endDate THEN 'Expired'
         WHEN startDate <= CURDATE() AND CURDATE() <= endDate THEN 'Valid'
         ELSE 'Invalid'
    END AS license_status
    FROM license";

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
        $AdminAddLicenseList{UID} = $Row[1];
        $AdminAddLicenseList{contractCompany} = $Row[2];
        $AdminAddLicenseList{endCustomer} = $Row[3];
        $AdminAddLicenseList{mcn} = $Row[4];
        $AdminAddLicenseList{contractNumber} = $Row[4]; # Keep for backward compatibility
        $AdminAddLicenseList{macAddress} = $Row[5];
        $AdminAddLicenseList{startDate} = $Row[6];
        $AdminAddLicenseList{endDate} = $Row[7];
        $AdminAddLicenseList{systemTechnology} = $Row[8];
        $AdminAddLicenseList{lsmpSiteID} = $Row[9];
        $AdminAddLicenseList{filename} = $Row[10];
        $AdminAddLicenseList{remaining_duration} = $Row[11];
        $AdminAddLicenseList{license_status} = $Row[12];
    }

    # Debug logging
    if (%AdminAddLicenseList) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'debug',
            Message  => "AdminAddLicenseList - Status: $AdminAddLicenseList{license_status}, " .
                        "EndDate: $AdminAddLicenseList{endDate}, " .
                        "Remaining: " . ($AdminAddLicenseList{remaining_duration} || 'N/A'),
        );
    }

    return %AdminAddLicenseList;
}

=head2 GetLicensedTechnology()

Get the current licensed technology from active license

    my $Technology = $AdminAddLicenseObject->GetLicensedTechnology();

Returns the systemTechnology value (e.g., 'WAVE On Prem', 'ASTRO', 'DIMETRA') or empty string if no valid license

=cut

sub GetLicensedTechnology {
    my ( $Self, %Param ) = @_;

    # Get current license information
    my %License = $Self->AdminAddLicenseList();

    # Return systemTechnology if available, empty string otherwise
    return $License{systemTechnology} || '';
}

=head2 AdminAddLicenseStandardTemplateMemberAdd()

to add an attachment to a template

    my $Success = $AdminAddLicenseObject->AdminAddLicenseStandardTemplateMemberAdd(
        AttachmentID       => 123,
        StandardTemplateID => 123,
        Active             => 1,        # optional
        UserID             => 123,
    );

=cut

sub AdminAddLicenseStandardTemplateMemberAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(AttachmentID StandardTemplateID UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # delete existing relation
    return if !$DBObject->Do(
        SQL => 'DELETE FROM standard_template_attachment
            WHERE standard_attachment_id = ?
            AND standard_template_id = ?',
        Bind => [ \$Param{AttachmentID}, \$Param{StandardTemplateID} ],
    );

    # return if relation is not active
    if ( !$Param{Active} ) {
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
            Type => $Self->{CacheType},
        );
        return 1;
    }

    # insert new relation
    my $Success = $DBObject->Do(
        SQL => '
            INSERT INTO standard_template_attachment (standard_attachment_id, standard_template_id,
                create_time, create_by, change_time, change_by)
            VALUES (?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$Param{AttachmentID}, \$Param{StandardTemplateID}, \$Param{UserID},
            \$Param{UserID},
        ],
    );

    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => $Self->{CacheType},
    );

    return $Success;
}

=head2 AdminAddLicenseStandardTemplateMemberList()

returns a list of Standard Attachment / Standard Template members

    my %List = $AdminAddLicenseObject->AdminAddLicenseStandardTemplateMemberList(
        AttachmentID => 123,
    );

    or
    my %List = $AdminAddLicenseObject->AdminAddLicenseStandardTemplateMemberList(
        StandardTemplateID => 123,
    );

Returns:
    %List = (
        1 => 'Some Name',
        2 => 'Some Name',
    );

=cut

sub AdminAddLicenseStandardTemplateMemberList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{AttachmentID} && !$Param{StandardTemplateID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need AttachmentID or StandardTemplateID!',
        );
        return;
    }

    if ( $Param{AttachmentID} && $Param{StandardTemplateID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need AttachmentID or StandardTemplateID, but not both!',
        );
        return;
    }

    # create cache key
    my $CacheKey = 'AdminAddLicenseStandardTemplateMemberList::';
    if ( $Param{AttachmentID} ) {
        $CacheKey .= 'AttachmentID::' . $Param{AttachmentID};
    }
    elsif ( $Param{StandardTemplateID} ) {
        $CacheKey .= 'StandardTemplateID::' . $Param{StandardTemplateID};
    }

    # check cache
    my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if ref $Cache eq 'HASH';

    # sql
    my %Data;
    my @Bind;
    my $SQL = '
        SELECT sta.standard_attachment_id, sa.name, sta.standard_template_id, st.name
        FROM standard_template_attachment sta, standard_attachment sa, standard_template st
        WHERE';

    if ( $Param{AttachmentID} ) {
        $SQL .= ' st.valid_id IN (' . join ', ',
            $Kernel::OM->Get('Kernel::System::Valid')->ValidIDsGet() . ')';
    }
    elsif ( $Param{StandardTemplateID} ) {
        $SQL .= ' sa.valid_id IN (' . join ', ',
            $Kernel::OM->Get('Kernel::System::Valid')->ValidIDsGet() . ')';
    }

    $SQL .= '
            AND sta.standard_attachment_id = sa.id
            AND sta.standard_template_id = st.id';

    if ( $Param{AttachmentID} ) {
        $SQL .= ' AND sta.standard_attachment_id = ?';
        push @Bind, \$Param{AttachmentID};
    }
    elsif ( $Param{StandardTemplateID} ) {
        $SQL .= ' AND sta.standard_template_id = ?';
        push @Bind, \$Param{StandardTemplateID};
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    $DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        if ( $Param{StandardTemplateID} ) {
            $Data{ $Row[0] } = $Row[1];
        }
        else {
            $Data{ $Row[2] } = $Row[3];
        }
    }

    # return result
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \%Data,
    );

    return %Data;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<https://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut

# SELECT 
#     id,
#     startDate,
#     endDate,

   

  
#     CONCAT(
#         TIMESTAMPDIFF(MONTH, CURDATE(), endDate), ' month(s) ',
#         DATEDIFF(endDate, DATE_ADD(CURDATE(), INTERVAL TIMESTAMPDIFF(MONTH, CURDATE(), endDate) MONTH)), ' day(s)'
#     ) AS remaining_duration,

#     -- Determine license status
#     CASE
        
#         WHEN CURDATE() > endDate THEN 'Expired'
#         WHEN startDate <= CURDATE() AND CURDATE() <= endDate THEN 'Valid'
#         ELSE 'Invalid'
#     END AS license_status

# FROM license
