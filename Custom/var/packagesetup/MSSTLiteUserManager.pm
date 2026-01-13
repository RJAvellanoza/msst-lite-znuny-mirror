# --
# Kernel/System/MSSTLiteUserManager.pm - MSSTLite User and Group Management
# Copyright (C) 2025 MSSTLite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package var::packagesetup::MSSTLiteUserManager;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Group',
    'Kernel::System::Log',
    'Kernel::System::User',
);

=head1 NAME

var::packagesetup::MSSTLiteUserManager - MSSTLite User and Group Management

=head1 SYNOPSIS

    use var::packagesetup::MSSTLiteUserManager;

    my $UserManager = $Kernel::OM->Get('var::packagesetup::MSSTLiteUserManager');

    # Initialize default groups and users
    $UserManager->InitializeDefaultGroups();
    $UserManager->InitializeDefaultUsers();

=head1 PUBLIC INTERFACE

=cut

=head2 new()

Create an object. Do not use it directly, instead use:

    my $UserManager = $Kernel::OM->Get('var::packagesetup::MSSTLiteUserManager');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 InitializeDefaultGroups()

Initialize default groups for MSSTLite system.

    my $Success = $UserManager->InitializeDefaultGroups();

=cut

sub InitializeDefaultGroups {
    my ( $Self, %Param ) = @_;

    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');

    # Define default groups - based on znuny-users-groups.sopm requirements
    my @DefaultGroups = (
        {
            Name    => 'MSIAdmin',
            Comment => 'MSI Administrator group for MSI personnel',
        },
        {
            Name    => 'NOCAdmin',
            Comment => 'NOC Administrator group for managing NOC operations',
        },
        {
            Name    => 'NOCUser',
            Comment => 'NOC User group for NOC operators',
        },
    );

    # Create each group if it doesn't exist
    for my $GroupData (@DefaultGroups) {
        eval {
            # Check if group exists
            my $GroupID = $GroupObject->GroupLookup(
                Group => $GroupData->{Name},
            );

            if (!$GroupID) {
                # Create the group
                $GroupID = $GroupObject->GroupAdd(
                    Name    => $GroupData->{Name},
                    Comment => $GroupData->{Comment},
                    ValidID => 1,
                    UserID  => 1,
                );

                if ($GroupID) {
                    $LogObject->Log(
                        Priority => 'notice',
                        Message  => "MSSTLite: Created $GroupData->{Name} group successfully",
                    );
                } else {
                    $LogObject->Log(
                        Priority => 'error',
                        Message  => "MSSTLite: Failed to create $GroupData->{Name} group",
                    );
                }
            } else {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: $GroupData->{Name} group already exists",
                );
            }
        };
        if ($@) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Error creating $GroupData->{Name} group: $@",
            );
        }
    }

    return 1;
}

=head2 InitializeDefaultUsers()

Initialize default users for MSSTLite system.

    my $Success = $UserManager->InitializeDefaultUsers();

=cut

sub InitializeDefaultUsers {
    my ( $Self, %Param ) = @_;

    my $UserObject  = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');

    # Define default users - based on znuny-users-groups.sopm definitions
    my @DefaultUsers = (
        {
            UserLogin     => 'unassigned',
            UserFirstname => 'Unassigned',
            UserLastname  => ' ',
            UserEmail     => 'unassigned@localhost',
            UserPw        => 'DisabledAccount123!',
            Groups        => [qw(MSIAdmin users)],
        },
        {
            UserLogin     => 'msicmso',
            UserFirstname => 'MSI',
            UserLastname  => 'CMSO',
            UserEmail     => 'msi.cmso@yourcompany.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(MSIAdmin stats users)],
        },
        {
            UserLogin     => 'msifield',
            UserFirstname => 'MSI',
            UserLastname  => 'Field',
            UserEmail     => 'msi.field@yourcompany.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(MSIAdmin stats users)],
        },
        {
            UserLogin     => 'lsmpappuser',
            UserFirstname => 'LSMP',
            UserLastname  => 'APP User',
            UserEmail     => 'lsmp.appuser@yourcompany.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(MSIAdmin stats users)],
        },
        {
            UserLogin     => 'nocadmin1',
            UserFirstname => 'nocadmin1',
            UserLastname  => 'Auto',
            UserEmail     => 'nocadmin1@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCAdmin NOCUser stats users)],
        },
        {
            UserLogin     => 'nocadmin2',
            UserFirstname => 'nocadmin2',
            UserLastname  => 'Auto',
            UserEmail     => 'nocadmin2@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCAdmin NOCUser stats users)],
        },
        {
            UserLogin     => 'nocuser1',
            UserFirstname => 'nocuser1',
            UserLastname  => 'Auto',
            UserEmail     => 'nocuser1@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCUser stats users)],
        },
        {
            UserLogin     => 'nocuser2',
            UserFirstname => 'nocuser2',
            UserLastname  => 'Auto',
            UserEmail     => 'nocuser2@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCUser stats users)],
        },
        {
            UserLogin     => 'nocuser3',
            UserFirstname => 'nocuser3',
            UserLastname  => 'Auto',
            UserEmail     => 'nocuser3@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCUser stats users)],
        },
        {
            UserLogin     => 'nocuser4',
            UserFirstname => 'nocuser4',
            UserLastname  => 'Auto',
            UserEmail     => 'nocuser4@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCUser stats users)],
        },
        {
            UserLogin     => 'nocuser5',
            UserFirstname => 'nocuser5',
            UserLastname  => 'Auto',
            UserEmail     => 'nocuser5@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCUser stats users)],
        },
        {
            UserLogin     => 'nocuser6',
            UserFirstname => 'nocuser6',
            UserLastname  => 'Auto',
            UserEmail     => 'nocuser6@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCUser stats users)],
        },
        {
            UserLogin     => 'nocuser7',
            UserFirstname => 'nocuser7',
            UserLastname  => 'Auto',
            UserEmail     => 'nocuser7@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCUser stats users)],
        },
        {
            UserLogin     => 'nocuser8',
            UserFirstname => 'nocuser8',
            UserLastname  => 'Auto',
            UserEmail     => 'nocuser8@gmail.com',
            UserPw        => 'tmp12345',
            Groups        => [qw(NOCUser stats users)],
        },
    );

    # Create each user
    for my $UserData (@DefaultUsers) {
        eval {
            $Self->_CreateOrUpdateUserAndAssignGroup(%{$UserData});
        };
        if ($@) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Error during user setup for $UserData->{UserLogin}: $@",
            );
        }
    }

    return 1;
}

=head2 CreateOrUpdateUserAndAssignGroup()

Create or update a user and assign them to multiple groups.

    my $Success = $UserManager->CreateOrUpdateUserAndAssignGroup(
        UserLogin     => 'username',
        UserFirstname => 'First',
        UserLastname  => 'Last',
        UserEmail     => 'user@example.com',
        UserPw        => 'password',
        Groups        => [qw(MSIAdmin stats users)],
    );

=cut

sub CreateOrUpdateUserAndAssignGroup {
    my ( $Self, %Param ) = @_;

    my $UserObject  = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');

    # Validate required parameters
    for my $Required (qw(UserLogin UserFirstname UserLastname UserEmail UserPw Groups)) {
        if (!$Param{$Required}) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Missing required parameter '$Required' for user creation",
            );
            return;
        }
    }
    
    # Ensure Groups is an array reference
    if (ref($Param{Groups}) ne 'ARRAY') {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLite: Groups parameter must be an array reference for user $Param{UserLogin}",
        );
        return;
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => "MSSTLite: Processing user $Param{UserLogin}",
    );

    my $UserID = $UserObject->UserLookup(
        UserLogin => $Param{UserLogin},
    );

    if ($UserID) {
        # User exists, skip creation
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLite: User $Param{UserLogin} already exists (UserID: $UserID), skipping creation",
        );
    } else {
        # User doesn't exist, create new user
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLite: Creating new user $Param{UserLogin}",
        );

        # Special handling for unassigned user - force ID 99
        if ($Param{UserLogin} eq 'unassigned') {
            my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
            
            # Check if ID 99 is already taken
            $DBObject->Prepare(
                SQL => 'SELECT login FROM users WHERE id = 99',
            );
            
            my $ExistingLogin;
            while (my @Row = $DBObject->FetchrowArray()) {
                $ExistingLogin = $Row[0];
            }
            
            if ($ExistingLogin && $ExistingLogin ne 'unassigned') {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Cannot create unassigned user with ID 99 - already taken by $ExistingLogin",
                );
                return;
            }
            
            # Create with forced ID 99
            my $Success = $DBObject->Do(
                SQL => 'INSERT INTO users (id, login, pw, title, first_name, last_name, valid_id, create_time, create_by, change_time, change_by) VALUES (99, ?, ?, ?, ?, ?, 1, current_timestamp, 1, current_timestamp, 1)',
                Bind => [
                    \$Param{UserLogin},
                    \$Param{UserPw},
                    \'Unassigned',
                    \$Param{UserFirstname},
                    \$Param{UserLastname},
                ],
            );
            
            if ($Success) {
                $UserID = 99;
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: Successfully created unassigned user with forced ID 99",
                );
            } else {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Failed to create unassigned user with ID 99",
                );
            }
        } else {
            # Normal user creation
            $UserID = $UserObject->UserAdd(
                UserFirstname   => $Param{UserFirstname},
                UserLastname    => $Param{UserLastname},
                UserLogin       => $Param{UserLogin},
                UserPw          => $Param{UserPw},
                UserEmail       => $Param{UserEmail},
                ValidID         => 1,
                CreateUserID    => 1,
                ChangeUserID    => 1,
            );

            if ($UserID) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: Successfully created user $Param{UserLogin} (UserID: $UserID)",
                );
            } else {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Failed to create $Param{UserLogin} user",
                );
            }
        }
    }

    # Assign user to all specified groups
    for my $GroupName (@{$Param{Groups}}) {
        my $GroupID = $GroupObject->GroupLookup(
            Group => $GroupName,
        );

        # If group doesn't exist, create it
        if (!$GroupID) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Group $GroupName not found, creating it...",
            );
            
            $GroupID = $GroupObject->GroupAdd(
                Name    => $GroupName,
                Comment => "Auto-created by MSSTLite for user $Param{UserLogin}",
                ValidID => 1,
                UserID  => 1,
            );
            
            if ($GroupID) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: Successfully created group $GroupName (GroupID: $GroupID)",
                );
            } else {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Failed to create group $GroupName, cannot assign $Param{UserLogin} user",
                );
                next; # Skip to next group
            }
        }

        if ($GroupID && $UserID) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Found $GroupName (GroupID: $GroupID)",
            );

            my $GroupSuccess = $GroupObject->GroupMemberAdd(
                GID        => $GroupID,
                UID        => $UserID,
                Permission => {
                    ro          => 1,
                    rw          => 1,
                    move_into   => 1,
                    create      => 1,
                    note        => 1,
                    owner       => 1,
                    priority    => 1,
                    responsible => 1,
                },
                UserID     => 1,
            );

            if ($GroupSuccess) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Assigned $Param{UserLogin} (UserID: $UserID) to $GroupName (GroupID: $GroupID)",
                );
            } else {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Failed to assign $Param{UserLogin} (UserID: $UserID) to $GroupName (GroupID: $GroupID)",
                );
            }
        }
    }

    # Safety mechanism: Remove msifield from admin and NOCAdmin groups if it somehow got added
    if ($Param{UserLogin} eq 'msifield' && $UserID) {
        $Self->_RemoveMsifieldFromRestrictedGroups($UserID);
    }

    # Set default language to English for all users
    if ($UserID) {
        my $LanguageSuccess = $UserObject->SetPreferences(
            UserID => $UserID,
            Key    => 'UserLanguage',
            Value  => 'en',
        );

        if ($LanguageSuccess) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Set default language to English for user $Param{UserLogin}",
            );
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Failed to set default language for user $Param{UserLogin}",
            );
        }
    }

    # Set My Queues preference for NOC users (NOCAdmin and NOCUser groups)
    if ($UserID && $Param{Groups}) {
        my $IsNOCUser = 0;
        for my $GroupName (@{$Param{Groups}}) {
            if ($GroupName eq 'NOCAdmin' || $GroupName eq 'NOCUser') {
                $IsNOCUser = 1;
                last;
            }
        }
        
        if ($IsNOCUser) {
            # Get the Support Group queue ID
            my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
            my %QueueList = $QueueObject->QueueList();
            my $SupportGroupQueueID;
            
            for my $QueueID (keys %QueueList) {
                if ($QueueList{$QueueID} eq 'Support Group') {
                    $SupportGroupQueueID = $QueueID;
                    last;
                }
            }
            
            if ($SupportGroupQueueID) {
                # Add Support Group to personal_queues table (My Queues)
                my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
                
                # First check if it already exists
                $DBObject->Prepare(
                    SQL => 'SELECT queue_id FROM personal_queues WHERE user_id = ? AND queue_id = ?',
                    Bind => [ \$UserID, \$SupportGroupQueueID ],
                );
                
                my $Exists;
                while (my @Row = $DBObject->FetchrowArray()) {
                    $Exists = 1;
                }
                
                if (!$Exists) {
                    # Insert into personal_queues table
                    my $Success = $DBObject->Do(
                        SQL => 'INSERT INTO personal_queues (queue_id, user_id) VALUES (?, ?)',
                        Bind => [ \$SupportGroupQueueID, \$UserID ],
                    );
                    
                    if ($Success) {
                        $LogObject->Log(
                            Priority => 'notice',
                            Message  => "MSSTLite: Added Support Group queue to My Queues for NOC user $Param{UserLogin}",
                        );
                        
                        # Clear cache for this user
                        my $CacheKey = 'GetAllCustomQueues::' . $UserID;
                        $Kernel::OM->Get('Kernel::System::Cache')->Delete(
                            Type => 'Queue',
                            Key  => $CacheKey,
                        );
                    } else {
                        $LogObject->Log(
                            Priority => 'error',
                            Message  => "MSSTLite: Failed to add Support Group queue to My Queues for NOC user $Param{UserLogin}",
                        );
                    }
                } else {
                    $LogObject->Log(
                        Priority => 'notice',
                        Message  => "MSSTLite: Support Group queue already in My Queues for NOC user $Param{UserLogin}",
                    );
                }
            } else {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Support Group queue not found, cannot add to My Queues for NOC user $Param{UserLogin}",
                );
            }
        }
    }

    return 1;
}

=head2 _CreateOrUpdateUserAndAssignGroup()

Internal method for creating or updating users and assigning them to groups.

=cut

sub _CreateOrUpdateUserAndAssignGroup {
    my ( $Self, %Param ) = @_;
    return $Self->CreateOrUpdateUserAndAssignGroup(%Param);
}

=head2 DeleteUserByLogin()

Deletes a user by their login name.

    my $Success = $UserManager->DeleteUserByLogin(
        UserLogin => 'username',
    );

=cut

sub DeleteUserByLogin {
    my ($Self, %Param) = @_;
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $LogObject  = $Kernel::OM->Get('Kernel::System::Log');

    my $UserLogin = $Param{UserLogin};
    if (!$UserLogin) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLite: Need UserLogin to delete a user.",
        );
        return;
    }

    my $UserID = $UserObject->UserLookup(UserLogin => $UserLogin);
    if ($UserID) {
        my %UserData = $UserObject->GetUserData(UserID => $UserID);
        my $Success = $UserObject->UserUpdate(
            UserID        => $UserID,
            UserLogin     => $UserLogin,
            UserFirstname => $UserData{UserFirstname},
            UserLastname  => $UserData{UserLastname},
            UserEmail     => $UserData{UserEmail},
            ValidID       => 2, # 2 = invalid (soft delete)
            ChangeUserID  => 1,
        );
        if ($Success) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Deleted user $UserLogin (UserID: $UserID)",
            );
            return 1;
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Failed to delete user $UserLogin (UserID: $UserID)",
            );
            return;
        }
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLite: User $UserLogin does not exist, nothing to delete.",
        );
        return 1; # Return success if user doesn't exist, as the goal is for them to be gone.
    }
}

=head2 _RemoveMsifieldFromRestrictedGroups()

Internal safety method to remove msifield from admin and NOCAdmin groups if accidentally assigned.

    my $Success = $UserManager->_RemoveMsifieldFromRestrictedGroups($UserID);

=cut

sub _RemoveMsifieldFromRestrictedGroups {
    my ( $Self, $UserID ) = @_;

    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');

    return if !$UserID;

    # Define restricted groups for msifield
    my @RestrictedGroups = ('admin', 'NOCAdmin');
    
    # Get user's current groups
    my %UserGroups = $GroupObject->PermissionUserGet(
        UserID => $UserID,
        Type   => 'rw',
    );

    foreach my $GroupName (@RestrictedGroups) {
        # Look up the group ID
        my $GroupID = $GroupObject->GroupLookup(
            Group => $GroupName,
        );
        
        next if !$GroupID;

        # Check if user is member of this restricted group
        if (exists $UserGroups{$GroupID}) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite Safety: msifield found in $GroupName group, removing...",
            );

            # Remove from the group
            my $RemoveSuccess = $GroupObject->GroupMemberAdd(
                GID        => $GroupID,
                UID        => $UserID,
                Permission => {
                    ro          => 0,
                    rw          => 0,
                    move_into   => 0,
                    create      => 0,
                    note        => 0,
                    owner       => 0,
                    priority    => 0,
                    responsible => 0,
                },
                UserID     => 1,
            );

            if ($RemoveSuccess) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite Safety: Successfully removed msifield from $GroupName group",
                );
            } else {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite Safety: Failed to remove msifield from $GroupName group",
                );
            }
        }
    }

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSSTLite project. The use of this software is
governed by the terms and conditions of the license agreement between you
and MSSTLite.

=cut 