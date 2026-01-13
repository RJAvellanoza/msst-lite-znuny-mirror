package var::packagesetup::MSSTLite;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Queue',
    'Kernel::System::Type',
    'Kernel::System::Priority',
    'Kernel::System::State',
    'Kernel::System::Group',
    'Kernel::System::Role',
    'Kernel::System::User',
    'Kernel::System::SysConfig',
);

=head1 NAME

var::packagesetup::MSSTLite - Code to execute during package installation

=head1 DESCRIPTION

All code to execute during package installation

=head1 PUBLIC INTERFACE

=head2 new()

Create an object

    my $CodeObject = var::packagesetup::MSSTLite->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # Allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 CodeInstall()

Run the code install part

    my $Result = $CodeObject->CodeInstall();

=cut

sub CodeInstall {
    my ( $Self, %Param ) = @_;

    # First, update the default ticket type configuration to avoid validation errors
    $Self->_UpdateDefaultTicketType();
    
    # Create queues and other entities first before setting defaults
    $Self->_UpdatePriorities();
    $Self->_CreateIncidentStates();
    $Self->_CreateTicketType();
    $Self->_CreateSupportGroupQueue();  # Create Support Group queue first
    $Self->_DeleteDefaultQueues();      # Delete default queues after creating custom ones
    $Self->_CreateMSSTGroups();
    $Self->_SetupPermissions();
    # Set default queues AFTER creating the Support Group queue
    $Self->_SetDefaultQueues();

    # Set default language to English for all users
    $Self->_SetDefaultLanguageForAllUsers();

    return 1;
}

=head2 CodeReinstall()

Run the code reinstall part

    my $Result = $CodeObject->CodeReinstall();

=cut

sub CodeReinstall {
    my ( $Self, %Param ) = @_;

    # First, update the default ticket type configuration to avoid validation errors
    $Self->_UpdateDefaultTicketType();
    
    # Create queues and other entities first before setting defaults
    $Self->_UpdatePriorities();
    $Self->_CreateIncidentStates();
    $Self->_CreateTicketType();
    $Self->_CreateSupportGroupQueue();  # Create Support Group queue first
    $Self->_DeleteDefaultQueues();      # Delete default queues after creating custom ones
    $Self->_CreateMSSTGroups();
    $Self->_SetupPermissions();
    # Set default queues AFTER creating the Support Group queue
    $Self->_SetDefaultQueues();

    # Set default language to English for all users
    $Self->_SetDefaultLanguageForAllUsers();

    return 1;
}

=head2 CodeUpgrade()

Run the code upgrade part

    my $Result = $CodeObject->CodeUpgrade();

=cut

sub CodeUpgrade {
    my ( $Self, %Param ) = @_;

    # First, update the default ticket type configuration to avoid validation errors
    $Self->_UpdateDefaultTicketType();
    
    # Create queues and other entities first before setting defaults
    $Self->_UpdatePriorities();
    $Self->_CreateIncidentStates();
    $Self->_CreateTicketType();
    $Self->_CreateSupportGroupQueue();  # Create Support Group queue first
    $Self->_DeleteDefaultQueues();      # Delete default queues after creating custom ones
    $Self->_CreateMSSTGroups();
    $Self->_SetupPermissions();
    # Set default queues AFTER creating the Support Group queue
    $Self->_SetDefaultQueues();

    # Set default language to English for all users
    $Self->_SetDefaultLanguageForAllUsers();

    return 1;
}

=head2 CodeUninstall()

Run the code uninstall part

    my $Result = $CodeObject->CodeUninstall();

=cut

sub CodeUninstall {
    my ( $Self, %Param ) = @_;

    # Don't remove data during uninstall - leave it for manual cleanup if needed
    
    return 1;
}

=head2 _CreateTicketType()

Create the Incident ticket type

=cut

sub _UpdatePriorities {
    my ( $Self, %Param ) = @_;

    my $PriorityObject = $Kernel::OM->Get('Kernel::System::Priority');
    my $LogObject      = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject       = $Kernel::OM->Get('Kernel::System::DB');

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Creating P1-P4 priorities',
    );

    # Define the new priorities to create
    my @NewPriorities = (
        { Name => 'P1-Critical', ValidID => 1 },
        { Name => 'P2-High',     ValidID => 1 },
        { Name => 'P3-Medium',   ValidID => 1 },
        { Name => 'P4-Low',      ValidID => 1 },
    );

    # Create each priority if it doesn't exist
    for my $Priority (@NewPriorities) {
        # Check if priority already exists
        my $ExistingID = $PriorityObject->PriorityLookup(
            Priority => $Priority->{Name},
            Silent   => 1,
        );
        
        if (!$ExistingID) {
            # Create the priority
            my $PriorityID = $PriorityObject->PriorityAdd(
                Name    => $Priority->{Name},
                ValidID => $Priority->{ValidID},
                UserID  => 1,
            );
            
            if ($PriorityID) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: Created priority '$Priority->{Name}' with ID $PriorityID",
                );
            } else {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Failed to create priority '$Priority->{Name}'",
                );
            }
        } else {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Priority '$Priority->{Name}' already exists with ID $ExistingID",
            );
        }
    }
    
    # Deploy priority default configurations
    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Deploying priority default configurations',
    );
    
    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
    
    # Priority default configurations - set to P3-Medium as default
    my %PriorityDefaults = (
        'AppointmentCalendar::Plugin::TicketCreate###PriorityDefault' => 'P3-Medium',
        'PostmasterDefaultPriority' => 'P3-Medium',
        'Process::DefaultPriority' => 'P3-Medium',
        'Ticket::Frontend::AgentTicketEmail###Priority' => 'P3-Medium',
        'Ticket::Frontend::AgentTicketNoteToLinkedTicket###PriorityDefault' => 'P3-Medium',
        'Ticket::Frontend::AgentTicketPhone###Priority' => 'P3-Medium',
        'Ticket::Frontend::CustomerTicketMessage###PriorityDefault' => 'P3-Medium',
        'Ticket::Frontend::CustomerTicketZoom###PriorityDefault' => 'P3-Medium',
    );
    
    # Lock all settings
    my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
        LockAll => 1,
        UserID  => 1,
        Force   => 1,
    );
    
    if ($ExclusiveLockGUID) {
        # Update each setting
        for my $Setting (sort keys %PriorityDefaults) {
            my $Success = $SysConfigObject->SettingUpdate(
                Name              => $Setting,
                IsValid           => 1,
                EffectiveValue    => $PriorityDefaults{$Setting},
                ExclusiveLockGUID => $ExclusiveLockGUID,
                UserID            => 1,
            );
            
            if ($Success) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: Updated priority default: $Setting => $PriorityDefaults{$Setting}",
                );
            }
        }
        
        # Configuration will be deployed later by the main ConfigurationDeploy
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLite: Priority defaults updated successfully',
        );
        
        # Unlock settings after deployment
        $SysConfigObject->SettingUnlock(
            UnlockAll => 1,
            UserID    => 1,
        );
    }
    
    # Delete default Znuny priorities AFTER everything is set up
    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Deleting default priorities',
    );
    
    my @PrioritiesToDelete = (
        '1 very low',
        '2 low', 
        '3 normal',
        '4 high',
        '5 very high',
    );
    
    for my $PriorityName (@PrioritiesToDelete) {
        # First check if priority exists
        my $SQL = "SELECT id FROM ticket_priority WHERE name = ?";
        $DBObject->Prepare(SQL => $SQL, Bind => [ \$PriorityName ]);
        
        my $PriorityID;
        while (my @Row = $DBObject->FetchrowArray()) {
            $PriorityID = $Row[0];
        }
        
        if ($PriorityID) {
            # Check if any tickets use this priority
            $SQL = "SELECT COUNT(*) FROM ticket WHERE ticket_priority_id = ?";
            $DBObject->Prepare(SQL => $SQL, Bind => [ \$PriorityID ]);
            
            my $TicketCount = 0;
            while (my @Row = $DBObject->FetchrowArray()) {
                $TicketCount = $Row[0];
            }
            
            # Get P3-Medium ID for migration
            my $P3ID;
            $SQL = "SELECT id FROM ticket_priority WHERE name = 'P3-Medium'";
            $DBObject->Prepare(SQL => $SQL);
            while (my @Row = $DBObject->FetchrowArray()) {
                $P3ID = $Row[0];
            }
            
            if ($P3ID) {
                if ($TicketCount > 0) {
                    # Update tickets to use P3-Medium before deleting
                    $DBObject->Do(
                        SQL => "UPDATE ticket SET ticket_priority_id = ? WHERE ticket_priority_id = ?",
                        Bind => [ \$P3ID, \$PriorityID ],
                    );
                    
                    $LogObject->Log(
                        Priority => 'notice',
                        Message  => "MSSTLite: Updated $TicketCount tickets from '$PriorityName' to 'P3-Medium'",
                    );
                }
                
                # Also update ticket_history references
                $DBObject->Do(
                    SQL => "UPDATE ticket_history SET priority_id = ? WHERE priority_id = ?",
                    Bind => [ \$P3ID, \$PriorityID ],
                );
                
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: Updated ticket_history references from '$PriorityName' to 'P3-Medium'",
                );
            }
            
            # Now delete the priority
            $DBObject->Do(
                SQL => "DELETE FROM ticket_priority WHERE id = ?",
                Bind => [ \$PriorityID ],
            );
            
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Deleted priority '$PriorityName'",
            );
        }
    }

    return 1;
}

sub _CreateTicketType {
    my ( $Self, %Param ) = @_;

    my $TypeObject = $Kernel::OM->Get('Kernel::System::Type');
    my $LogObject  = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject   = $Kernel::OM->Get('Kernel::System::DB');

    my $IncidentTypeID;

    # Check if Incident type already exists
    my %TypeList = $TypeObject->TypeList();
    for my $TypeID ( keys %TypeList ) {
        if ( $TypeList{$TypeID} eq 'Incident' ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Ticket type 'Incident' already exists with ID $TypeID",
            );
            $IncidentTypeID = $TypeID;
            last;
        }
    }

    # Create Incident type if it doesn't exist
    if (!$IncidentTypeID) {
        $IncidentTypeID = $TypeObject->TypeAdd(
            Name    => 'Incident',
            ValidID => 1,
            UserID  => 1,
        );

        if ($IncidentTypeID) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Created ticket type 'Incident' with ID $IncidentTypeID",
            );
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Failed to create ticket type 'Incident'",
            );
        }
    }

    # Always try to remove Unclassified type if it exists
    my $SQL = "SELECT id FROM ticket_type WHERE name = 'Unclassified'";
    $DBObject->Prepare(SQL => $SQL);
    
    my $UnclassifiedTypeID;
    while (my @Row = $DBObject->FetchrowArray()) {
        $UnclassifiedTypeID = $Row[0];
    }
    
    if ($UnclassifiedTypeID) {
        # Update any tickets using Unclassified type to use Incident type instead
        if ($IncidentTypeID) {
            $DBObject->Do(
                SQL => "UPDATE ticket SET type_id = ? WHERE type_id = ?",
                Bind => [ \$IncidentTypeID, \$UnclassifiedTypeID ],
            );
            
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Updated tickets from 'Unclassified' type to 'Incident' type",
            );
            
            # Also update ticket_history references
            $DBObject->Do(
                SQL => "UPDATE ticket_history SET type_id = ? WHERE type_id = ?",
                Bind => [ \$IncidentTypeID, \$UnclassifiedTypeID ],
            );
            
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Updated ticket_history from 'Unclassified' type to 'Incident' type",
            );
        }
        
        # Now we can safely delete the Unclassified type
        my $DeleteSuccess = $DBObject->Do(
            SQL => "DELETE FROM ticket_type WHERE id = ?",
            Bind => [ \$UnclassifiedTypeID ],
        );
        
        if ($DeleteSuccess) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Successfully deleted 'Unclassified' ticket type",
            );
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Failed to delete 'Unclassified' ticket type",
            );
        }
    }

    return $IncidentTypeID;
}

=head2 _CreateIncidentQueue()

Create the Incident queue

=cut

sub _CreateIncidentQueue {
    my ( $Self, %Param ) = @_;

    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');

    # Check if Incident queue already exists
    my %QueueList = $QueueObject->QueueList();
    for my $QueueID ( keys %QueueList ) {
        if ( $QueueList{$QueueID} eq 'Incident' ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Queue 'Incident' already exists with ID $QueueID",
            );
            return $QueueID;
        }
    }

    # Create Incident queue
    my $QueueID = $QueueObject->QueueAdd(
        Name            => 'Incident',
        ValidID         => 1,
        GroupID         => 1,  # users group
        Calendar        => '',
        FirstResponseTime => 240,    # 4 hours
        UpdateTime      => 480,      # 8 hours  
        SolutionTime    => 1440,     # 24 hours
        UnlockTimeout   => 0,
        FollowUpID      => 1,
        FollowUpLock    => 0,
        SystemAddressID => 1,
        SalutationID    => 1,
        SignatureID     => 1,
        Comment         => 'Queue for incident management',
        UserID          => 1,
    );

    if ($QueueID) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "Created queue 'Incident' with ID $QueueID",
        );
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to create queue 'Incident'",
        );
    }

    return $QueueID;
}

=head2 _CreateMSSTGroups()

Create MSST-specific groups

=cut

sub _CreateMSSTGroups {
    my ( $Self, %Param ) = @_;

    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');

    my @GroupsToCreate = (
        {
            Name    => 'MSIAdmin',
            Comment => 'MSI Administrators - Full incident management access',
        },
        {
            Name    => 'NOCAdmin', 
            Comment => 'NOC Administrators - Network operations center admins',
        },
        {
            Name    => 'NOCUser',
            Comment => 'NOC Users - Network operations center users',
        },
    );

    for my $GroupData (@GroupsToCreate) {
        # Check if group already exists
        my %GroupList = $GroupObject->GroupList();
        my $GroupExists = 0;
        for my $GroupID ( keys %GroupList ) {
            if ( $GroupList{$GroupID} eq $GroupData->{Name} ) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "Group '$GroupData->{Name}' already exists with ID $GroupID",
                );
                $GroupExists = 1;
                last;
            }
        }

        next if $GroupExists;

        # Create group
        my $GroupID = $GroupObject->GroupAdd(
            Name    => $GroupData->{Name},
            Comment => $GroupData->{Comment},
            ValidID => 1,
            UserID  => 1,
        );

        if ($GroupID) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Created group '$GroupData->{Name}' with ID $GroupID",
            );
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Failed to create group '$GroupData->{Name}'",
            );
        }
    }

    return 1;
}

=head2 _SetupPermissions()

Setup permissions for MSST groups

=cut

sub _SetupPermissions {
    my ( $Self, %Param ) = @_;

    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');

    # Get group and queue IDs
    my %GroupList = $GroupObject->GroupList();
    my %QueueList = $QueueObject->QueueList();

    my $IncidentQueueID;
    for my $QueueID ( keys %QueueList ) {
        if ( $QueueList{$QueueID} eq 'Incident' ) {
            $IncidentQueueID = $QueueID;
            last;
        }
    }

    return 1 unless $IncidentQueueID;

    # Setup queue-group permissions for MSST groups
    for my $GroupName (qw(MSIAdmin NOCAdmin NOCUser)) {
        my $GroupID;
        for my $ID ( keys %GroupList ) {
            if ( $GroupList{$ID} eq $GroupName ) {
                $GroupID = $ID;
                last;
            }
        }

        next unless $GroupID;

        # Get current queue data to preserve SystemAddressID
        my %QueueData = $QueueObject->QueueGet(
            ID => $IncidentQueueID,
        );

        # Set queue permissions
        my $Success = $QueueObject->QueueUpdate(
            QueueID         => $IncidentQueueID,
            Name            => 'Incident',
            GroupID         => $GroupID,
            SystemAddressID => $QueueData{SystemAddressID} || 1,
            SalutationID    => $QueueData{SalutationID} || 1,
            SignatureID     => $QueueData{SignatureID} || 1,
            FollowUpID      => $QueueData{FollowUpID} || 1,
            FollowUpLock    => $QueueData{FollowUpLock} || 0,
            UnlockTimeout   => $QueueData{UnlockTimeout} || 0,
            ValidID         => 1,
            UserID          => 1,
        );

        if ($Success) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Updated Incident queue permissions for group $GroupName",
            );
        }
    }

    return 1;
}

=head2 _CreateIncidentStates()

Create custom incident states

=cut

sub _CreateIncidentStates {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Creating custom incident states',
    );
    
    # STEP 1: Create state types if they don't exist
    my @StateTypes = (
        { name => 'open', comments => 'Open state type' },
        { name => 'closed', comments => 'Closed state type' },
        { name => 'pending', comments => 'Pending state type' },
    );
    
    for my $StateType (@StateTypes) {
        my $SQL = "SELECT id FROM ticket_state_type WHERE name = ?";
        $DBObject->Prepare(SQL => $SQL, Bind => [ \$StateType->{name} ]);
        
        my $Exists = 0;
        while (my @Row = $DBObject->FetchrowArray()) {
            $Exists = 1;
        }
        
        if (!$Exists) {
            $DBObject->Do(
                SQL => "INSERT INTO ticket_state_type (name, comments, create_by, create_time, change_by, change_time) VALUES (?, ?, 1, current_timestamp, 1, current_timestamp)",
                Bind => [ \$StateType->{name}, \$StateType->{comments} ],
            );
            
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Created state type '$StateType->{name}'",
            );
        }
    }
    
    # STEP 2: Check ticket count and conditionally delete
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # Get all ticket IDs
    my @TicketIDs = $TicketObject->TicketSearch(
        Result     => 'ARRAY',
        UserID     => 1,
        Permission => 'ro',
    );

    my $TicketCount = scalar @TicketIDs;

    $LogObject->Log(
        Priority => 'notice',
        Message  => "MSSTLite: Found $TicketCount ticket(s) in the system",
    );

    my $CanDeleteStates = 0;  # Flag to track if we can safely delete/recreate states

    if ($TicketCount == 0) {
        # No tickets, safe to delete and recreate states
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLite: No tickets found, will delete and recreate all states',
        );
        $CanDeleteStates = 1;
    }
    elsif ($TicketCount == 1) {
        # Only 1 ticket (probably test ticket), delete it
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLite: Only 1 ticket found (likely test ticket), deleting it',
        );

        my $Success = $TicketObject->TicketDelete(
            TicketID => $TicketIDs[0],
            UserID   => 1,
        );

        if ($Success) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Deleted ticket $TicketIDs[0]",
            );
            $CanDeleteStates = 1;
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Failed to delete ticket $TicketIDs[0], will create missing states only",
            );
            $CanDeleteStates = 0;
        }
    }
    else {
        # Multiple tickets exist, don't delete anything
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLite: $TicketCount tickets exist, will create missing states only (won't delete existing data)",
        );
        $CanDeleteStates = 0;
    }

    # STEP 3: Handle state creation based on whether we can delete
    my @States = (
        { name => 'new', comments => 'New ticket', type => 'new' },
        { name => 'assigned', comments => 'Ticket has been assigned to a group/agent', type => 'open' },
        { name => 'in progress', comments => 'Ticket is being actively worked on', type => 'open' },
        { name => 'pending', comments => 'Ticket is in pending state', type => 'pending auto' },
        { name => 'resolved', comments => 'Issue has been resolved but not yet confirmed by customer', type => 'closed' },
        { name => 'closed', comments => 'Ticket has been closed', type => 'closed' },
        { name => 'cancelled', comments => 'Ticket was cancelled', type => 'closed' },
    );

    if ($CanDeleteStates) {
        # Safe to delete and recreate all states
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLite: Deleting all existing states',
        );

        $DBObject->Do(SQL => "DELETE FROM ticket_state");

        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLite: Creating all states from scratch',
        );

        # Create all states
        for my $State (@States) {
            # Get type_id
            my $SQL = "SELECT id FROM ticket_state_type WHERE name = ?";
            $DBObject->Prepare(SQL => $SQL, Bind => [ \$State->{type} ]);

            my $TypeID;
            while (my @Row = $DBObject->FetchrowArray()) {
                $TypeID = $Row[0];
            }

            if (!$TypeID) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Could not find type '$State->{type}' for state '$State->{name}'",
                );
                next;
            }

            # Insert state (let DB auto-generate ID)
            $DBObject->Do(
                SQL => "INSERT INTO ticket_state (name, comments, type_id, valid_id, create_by, create_time, change_by, change_time) VALUES (?, ?, ?, 1, 1, current_timestamp, 1, current_timestamp)",
                Bind => [ \$State->{name}, \$State->{comments}, \$TypeID ],
            );

            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Created state '$State->{name}'",
            );
        }
    }
    else {
        # Can't delete states, create only missing ones
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLite: Creating missing states (preserving existing tickets)',
        );

        for my $State (@States) {
            # Check if state already exists
            my $SQL = "SELECT id FROM ticket_state WHERE name = ?";
            $DBObject->Prepare(SQL => $SQL, Bind => [ \$State->{name} ]);

            my $Exists = 0;
            while (my @Row = $DBObject->FetchrowArray()) {
                $Exists = 1;
            }

            if ($Exists) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: State '$State->{name}' already exists, skipping",
                );
                next;
            }

            # Get type_id
            $SQL = "SELECT id FROM ticket_state_type WHERE name = ?";
            $DBObject->Prepare(SQL => $SQL, Bind => [ \$State->{type} ]);

            my $TypeID;
            while (my @Row = $DBObject->FetchrowArray()) {
                $TypeID = $Row[0];
            }

            if (!$TypeID) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Could not find type '$State->{type}' for state '$State->{name}'",
                );
                next;
            }

            # Insert missing state
            $DBObject->Do(
                SQL => "INSERT INTO ticket_state (name, comments, type_id, valid_id, create_by, create_time, change_by, change_time) VALUES (?, ?, ?, 1, 1, current_timestamp, 1, current_timestamp)",
                Bind => [ \$State->{name}, \$State->{comments}, \$TypeID ],
            );

            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Created missing state '$State->{name}'",
            );
        }
    }
    
    # STEP 3: Deploy state default configurations
    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Deploying state default configurations',
    );
    
    # State default configurations
    my %StateDefaults = (
        'PostmasterFollowUpState' => 'pending',
        'Ticket::Frontend::AgentTicketBounce###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketClose###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketCompose###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketEmail###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketEmailOutbound###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketForward###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketNoteToLinkedTicket###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketNoteToLinkedTicket###LinkedTicketStateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketOwner###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketPending###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketPhone###StateDefault' => 'pending',
        'Ticket::Frontend::AgentTicketPhoneInbound###State' => 'pending',
        'Ticket::Frontend::AgentTicketPhoneOutbound###State' => 'pending',
        'Ticket::Frontend::AgentTicketPriority###StateDefault' => 'new',
        'Ticket::Frontend::AgentTicketResponsible###StateDefault' => 'resolved',
        'Ticket::Frontend::CustomerTicketZoom###StateDefault' => 'in progress',
    );
    
    # Lock all settings
    my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
        LockAll => 1,
        UserID  => 1,
        Force   => 1,
    );
    
    if ($ExclusiveLockGUID) {
        # Update each setting
        for my $Setting (sort keys %StateDefaults) {
            my $Success = $SysConfigObject->SettingUpdate(
                Name              => $Setting,
                IsValid           => 1,
                EffectiveValue    => $StateDefaults{$Setting},
                ExclusiveLockGUID => $ExclusiveLockGUID,
                UserID            => 1,
            );
            
            if ($Success) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: Updated state default: $Setting => $StateDefaults{$Setting}",
                );
            }
        }
        
        # Configuration will be deployed later by the main ConfigurationDeploy
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLite: State defaults updated successfully',
        );
        
        # Unlock settings after deployment
        $SysConfigObject->SettingUnlock(
            UnlockAll => 1,
            UserID    => 1,
        );
    }
    
    # STEP 4: Delete unwanted default Znuny states
    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Deleting unwanted default states',
    );
    
    my @StatesToDelete = (
        'closed successful',
        'closed unsuccessful', 
        'open',
        'removed',
        'pending reminder',
        'pending auto close+',
        'pending auto close-',
        'merged'
    );
    
    for my $StateName (@StatesToDelete) {
        # Delete state completely
        $DBObject->Do(
            SQL => "DELETE FROM ticket_state WHERE name = ?",
            Bind => [ \$StateName ],
        );
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLite: Deleted state '$StateName'",
        );
    }
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Custom incident states created and configured successfully',
    );
    
    return 1;
}

=head2 _CreateSupportGroupQueue()

Create the Support Group queue if it doesn't exist

=cut

sub _CreateSupportGroupQueue {
    my ( $Self, %Param ) = @_;

    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');

    # Check if Support Group queue already exists
    my %QueueList = $QueueObject->QueueList();
    for my $QueueID ( keys %QueueList ) {
        if ( $QueueList{$QueueID} eq 'Support Group' ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Queue 'Support Group' already exists with ID $QueueID",
            );
            return $QueueID;
        }
    }

    # Create Support Group queue
    my $QueueID = $QueueObject->QueueAdd(
        Name            => 'Support Group',
        ValidID         => 1,
        GroupID         => 1,  # users group
        Calendar        => '',
        FirstResponseTime => 60,     # 1 hour
        UpdateTime      => 120,      # 2 hours  
        SolutionTime    => 480,      # 8 hours
        UnlockTimeout   => 0,
        FollowUpID      => 1,
        FollowUpLock    => 0,
        SystemAddressID => 1,
        SalutationID    => 1,
        SignatureID     => 1,
        Comment         => 'Default support queue',
        UserID          => 1,
    );

    if ($QueueID) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "Created queue 'Support Group' with ID $QueueID",
        );
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to create queue 'Support Group'",
        );
    }

    return $QueueID;
}

=head2 _SetDefaultQueues()

Set default queues for PostmasterDefaultQueue and Process::DefaultQueue

=cut

sub _SetDefaultQueues {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $QueueObject  = $Kernel::OM->Get('Kernel::System::Queue');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    # Find the "Support Group" queue ID - it should already exist from _CreateSupportGroupQueue
    my %QueueList = $QueueObject->QueueList();
    my $SupportGroupQueueID;
    
    for my $QueueID ( keys %QueueList ) {
        if ( $QueueList{$QueueID} eq 'Support Group' ) {
            $SupportGroupQueueID = $QueueID;
            last;
        }
    }

    if ( !$SupportGroupQueueID ) {
        # This shouldn't happen as _CreateSupportGroupQueue should have already created it
        $LogObject->Log(
            Priority => 'error',
            Message  => "Support Group queue not found - this should not happen!",
        );
        return;
    }

    # Update system configuration
    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

    $LogObject->Log(
        Priority => 'notice',
        Message  => "MSSTLite: Found Support Group queue with ID: $SupportGroupQueueID, setting as default queue",
    );

    # Lock settings for update
    my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
        LockAll => 1,
        UserID  => 1,
        Force   => 1,
    );

    if (!$ExclusiveLockGUID) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLite: Failed to lock settings for default queue configuration",
        );
        return 0;
    }

    my $Success1 = 0;
    my $Success2 = 0;

    # Set PostmasterDefaultQueue
    $Success1 = $SysConfigObject->SettingUpdate(
        Name              => 'PostmasterDefaultQueue',
        EffectiveValue    => 'Support Group',
        ExclusiveLockGUID => $ExclusiveLockGUID,
        UserID            => 1,
    );

    if (!$Success1) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLite: Failed to update PostmasterDefaultQueue",
        );
    }

    # Set Process::DefaultQueue
    $Success2 = $SysConfigObject->SettingUpdate(
        Name              => 'Process::DefaultQueue',
        EffectiveValue    => 'Support Group',
        ExclusiveLockGUID => $ExclusiveLockGUID,
        UserID            => 1,
    );

    if (!$Success2) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLite: Failed to update Process::DefaultQueue",
        );
    }

    # Deploy the configuration changes immediately
    my $DeploySuccess = 0;
    if ($Success1 || $Success2) {
        $DeploySuccess = $SysConfigObject->ConfigurationDeploy(
            Comments          => "MSSTLite: Setting default queues to Support Group",
            UserID            => 1,
            Force             => 1,
            AllSettings       => 1,
            ExclusiveLockGUID => $ExclusiveLockGUID,
        );

        if ($DeploySuccess) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Successfully deployed default queue configuration",
            );
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Failed to deploy default queue configuration",
            );
        }
    }

    # Unlock settings
    $SysConfigObject->SettingUnlock(
        UnlockAll => 1,
        UserID    => 1,
    );

    if ($Success1 && $Success2) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLite: Successfully set PostmasterDefaultQueue and Process::DefaultQueue to 'Support Group'",
        );
        return 1;
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "MSSTLite: Failed to set one or both default queue configurations",
        );
        return 0;
    }
}

=head2 _DeleteDefaultQueues()

Delete default Znuny queues and migrate all references to Support Group

=cut

sub _DeleteDefaultQueues {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Deleting default queues and migrating to Support Group',
    );
    
    # Get Support Group queue ID first
    my $SQL = "SELECT id FROM queue WHERE name = 'Support Group'";
    $DBObject->Prepare(SQL => $SQL);
    
    my $SupportGroupID;
    while (my @Row = $DBObject->FetchrowArray()) {
        $SupportGroupID = $Row[0];
    }
    
    if (!$SupportGroupID) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'MSSTLite: Support Group queue not found, cannot delete default queues',
        );
        return 0;
    }
    
    # Queues to delete
    my @QueuesToDelete = (
        'Postmaster',
        'Raw',
        'Junk', 
        'Misc',
        'Incident',
    );
    
    for my $QueueName (@QueuesToDelete) {
        # Get queue ID
        $SQL = "SELECT id FROM queue WHERE name = ?";
        $DBObject->Prepare(SQL => $SQL, Bind => [ \$QueueName ]);
        
        my $QueueID;
        while (my @Row = $DBObject->FetchrowArray()) {
            $QueueID = $Row[0];
        }
        
        if ($QueueID) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Migrating all references from queue '$QueueName' to 'Support Group'",
            );
            
            # Migrate tickets
            $DBObject->Do(
                SQL => "UPDATE ticket SET queue_id = ? WHERE queue_id = ?",
                Bind => [ \$SupportGroupID, \$QueueID ],
            );
            
            # Migrate ticket_history
            $DBObject->Do(
                SQL => "UPDATE ticket_history SET queue_id = ? WHERE queue_id = ?", 
                Bind => [ \$SupportGroupID, \$QueueID ],
            );
            
            # Migrate queue_standard_template
            $DBObject->Do(
                SQL => "UPDATE queue_standard_template SET queue_id = ? WHERE queue_id = ?",
                Bind => [ \$SupportGroupID, \$QueueID ],
            );
            
            # Migrate any other tables that might reference queues
            $DBObject->Do(
                SQL => "UPDATE queue_preferences SET queue_id = ? WHERE queue_id = ?",
                Bind => [ \$SupportGroupID, \$QueueID ],
            );
            
            # Now delete the queue
            $DBObject->Do(
                SQL => "DELETE FROM queue WHERE id = ?",
                Bind => [ \$QueueID ],
            );
            
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Deleted queue '$QueueName' and migrated all references",
            );
        }
    }
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Default queues cleanup completed',
    );
    
    return 1;
}

=head2 _UpdateDefaultTicketType()

Update the default ticket type configuration to avoid validation errors

=cut

sub _UpdateDefaultTicketType {
    my ( $Self, %Param ) = @_;

    my $TypeObject     = $Kernel::OM->Get('Kernel::System::Type');
    my $LogObject      = $Kernel::OM->Get('Kernel::System::Log');

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Ensuring Incident type exists for configuration',
    );

    # First, ensure Incident type exists
    my $IncidentTypeID;
    my %TypeList = $TypeObject->TypeList();
    for my $TypeID ( keys %TypeList ) {
        if ( $TypeList{$TypeID} eq 'Incident' ) {
            $IncidentTypeID = $TypeID;
            last;
        }
    }

    # Create Incident type if it doesn't exist
    if (!$IncidentTypeID) {
        $IncidentTypeID = $TypeObject->TypeAdd(
            Name    => 'Incident',
            ValidID => 1,
            UserID  => 1,
        );
        
        if ($IncidentTypeID) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "MSSTLite: Created 'Incident' type with ID $IncidentTypeID early to ensure configuration validation passes",
            );
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLite: Failed to create 'Incident' type",
            );
        }
    } else {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "MSSTLite: 'Incident' type already exists with ID $IncidentTypeID",
        );
    }

    # The XML configuration in IncidentTypes.xml will handle setting Incident as the default
    # We just need to ensure the type exists before configuration validation

    return 1;
}

=head2 _SetDefaultLanguageForAllUsers()

Set default language to English for all existing users

=cut

sub _SetDefaultLanguageForAllUsers {
    my ( $Self, %Param ) = @_;

    my $UserObject  = $Kernel::OM->Get('Kernel::System::User');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject    = $Kernel::OM->Get('Kernel::System::DB');

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLite: Setting default language to English for all users',
    );

    # Get all active users
    my %UserList = $UserObject->UserList(
        Type    => 'Short',
        Valid   => 1,
    );

    my $UpdatedCount = 0;
    my $FailedCount = 0;

    for my $UserID ( keys %UserList ) {
        # Check if user already has a language preference
        $DBObject->Prepare(
            SQL  => 'SELECT preferences_value FROM user_preferences WHERE user_id = ? AND preferences_key = ?',
            Bind => [ \$UserID, \'UserLanguage' ],
        );

        my $ExistingLanguage;
        while ( my @Row = $DBObject->FetchrowArray() ) {
            $ExistingLanguage = $Row[0];
        }

        # Only set if no language preference exists or it's not English
        if ( !$ExistingLanguage || $ExistingLanguage ne 'en' ) {
            my $Success = $UserObject->SetPreferences(
                UserID => $UserID,
                Key    => 'UserLanguage',
                Value  => 'en',
            );

            if ($Success) {
                $UpdatedCount++;
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "MSSTLite: Set language to English for user $UserList{$UserID} (UserID: $UserID)",
                );
            } else {
                $FailedCount++;
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "MSSTLite: Failed to set language for user $UserList{$UserID} (UserID: $UserID)",
                );
            }
        }
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => "MSSTLite: Language update complete. Updated: $UpdatedCount users, Failed: $FailedCount users",
    );

    return 1;
}

1;