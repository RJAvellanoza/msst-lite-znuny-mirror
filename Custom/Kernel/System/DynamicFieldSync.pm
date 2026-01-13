# --
# Copyright (C) 2025 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::DynamicFieldSync;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::System::User',
    'Kernel::System::DynamicField',
);

=head1 NAME

Kernel::System::DynamicFieldSync - Service to sync dynamic fields with user data

=head1 SYNOPSIS

    use Kernel::System::DynamicFieldSync;

    my $SyncObject = $Kernel::OM->Get('Kernel::System::DynamicFieldSync');

    # Sync AssignedTo dynamic field after user name change
    $SyncObject->SyncAssignedToField(UserID => 5);

=head1 DESCRIPTION

This module provides services to synchronize dynamic field values with user data,
ensuring dashboard columns and dropdowns always show current user names.

=head1 PUBLIC INTERFACE

=cut

=head2 new()

Create an object. Do not use it directly, instead use:

    my $SyncObject = $Kernel::OM->Get('Kernel::System::DynamicFieldSync');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 SyncAssignedToField()

Synchronizes the AssignedTo dynamic field with current user name.

    my $Success = $SyncObject->SyncAssignedToField(
        UserID => 5,  # User ID whose name changed
    );

Returns:
    1 on success, undef on failure

=cut

sub SyncAssignedToField {
    my ( $Self, %Param ) = @_;

    my $LogObject          = $Kernel::OM->Get('Kernel::System::Log');
    my $UserObject         = $Kernel::OM->Get('Kernel::System::User');
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

    # Check required parameter
    if ( !$Param{UserID} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Need UserID parameter!',
        );
        return;
    }

    # Get the AssignedTo dynamic field
    my $DynamicField = $DynamicFieldObject->DynamicFieldGet(
        Name => 'AssignedTo',
    );

    if ( !$DynamicField || !$DynamicField->{ID} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'AssignedTo dynamic field not found!',
        );
        return;
    }

    # Get current user data
    my %UserData = $UserObject->GetUserData(
        UserID        => $Param{UserID},
        NoOutOfOffice => 1,
    );

    if ( !%UserData ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Could not get user data for UserID $Param{UserID}!",
        );
        return;
    }

    # Build the display name (FirstName LastName)
    my $DisplayName = "$UserData{UserFirstname} $UserData{UserLastname}";

    # Get current PossibleValues
    my %PossibleValues = %{ $DynamicField->{Config}->{PossibleValues} || {} };

    # Check if the value needs updating
    my $CurrentValue = $PossibleValues{ $Param{UserID} } || '';

    if ( $CurrentValue eq $DisplayName ) {
        $LogObject->Log(
            Priority => 'info',
            Message  => "AssignedTo field for UserID $Param{UserID} already up to date: '$DisplayName'",
        );
        return 1;  # Already synced, no update needed
    }

    # Update the value for this UserID
    $PossibleValues{ $Param{UserID} } = $DisplayName;

    $LogObject->Log(
        Priority => 'notice',
        Message  => "Syncing AssignedTo field: UserID $Param{UserID} -> '$DisplayName' (was: '$CurrentValue')",
    );

    # Update the dynamic field
    my $Success = $DynamicFieldObject->DynamicFieldUpdate(
        ID         => $DynamicField->{ID},
        Name       => $DynamicField->{Name},
        Label      => $DynamicField->{Label},
        FieldOrder => $DynamicField->{FieldOrder},
        FieldType  => $DynamicField->{FieldType},
        ObjectType => $DynamicField->{ObjectType},
        Config     => {
            %{ $DynamicField->{Config} },
            PossibleValues => \%PossibleValues,
        },
        ValidID => $DynamicField->{ValidID},
        UserID  => 1,
    );

    if ( !$Success ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to update AssignedTo dynamic field for UserID $Param{UserID}!",
        );
        return;
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => "Successfully synced AssignedTo field for UserID $Param{UserID}: '$DisplayName'",
    );

    return 1;
}

=head2 SyncAllAssignedToValues()

Synchronizes all user entries in the AssignedTo dynamic field with current user names.
Useful for bulk updates or migrations.

    my $Success = $SyncObject->SyncAllAssignedToValues();

Returns:
    1 on success, undef on failure

=cut

sub SyncAllAssignedToValues {
    my ( $Self, %Param ) = @_;

    my $LogObject          = $Kernel::OM->Get('Kernel::System::Log');
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

    # Get the AssignedTo dynamic field
    my $DynamicField = $DynamicFieldObject->DynamicFieldGet(
        Name => 'AssignedTo',
    );

    if ( !$DynamicField || !$DynamicField->{ID} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'AssignedTo dynamic field not found!',
        );
        return;
    }

    # Get all UserIDs from PossibleValues (excluding 99 which is Unassigned)
    my %PossibleValues = %{ $DynamicField->{Config}->{PossibleValues} || {} };
    my @UserIDs = grep { $_ ne '99' } keys %PossibleValues;

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'Starting bulk sync of AssignedTo field for ' . scalar(@UserIDs) . ' users',
    );

    my $SuccessCount = 0;
    my $FailureCount = 0;

    # Sync each user
    for my $UserID (@UserIDs) {
        my $Success = $Self->SyncAssignedToField(
            UserID => $UserID,
        );

        if ($Success) {
            $SuccessCount++;
        }
        else {
            $FailureCount++;
        }
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => "Bulk sync complete: $SuccessCount successful, $FailureCount failed",
    );

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSSTLite project.

=cut
