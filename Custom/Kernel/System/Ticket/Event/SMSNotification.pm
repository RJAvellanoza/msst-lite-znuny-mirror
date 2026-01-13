# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Ticket::Event::SMSNotification;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::System::Ticket',
    'Kernel::Config',
    'Kernel::System::TwilioSMS',
    'Kernel::System::User',
    'Kernel::System::Group',
    'Kernel::System::Cache',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    $LogObject->Log(
        Priority => 'notice',
        Message  => "SMS notification Run() called for event: $Param{Event} on TicketID: " . ($Param{Data}->{TicketID} || 'unknown'),
    );

    # check needed params
    for my $Needed (qw(Data Event Config UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # Check if ticket ID is available
    if ( !$Param{Data}->{TicketID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need TicketID in Data!",
        );
        return;
    }

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # Get ticket data with dynamic fields for CI and Site information
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Param{Data}->{TicketID},
        UserID        => 1,
        DynamicFields => 1,  # Enable to fetch CI and Site dynamic fields
    );
    
    # Determine COMPLETE event type immediately
    my $EventType = 'update';
    my $IsResolvedEvent = 0;
    my $IsReopenedEvent = 0;  # Track reopened events separately
    my $IsAssignedEvent = 0;  # Track assigned events separately
    my $ShouldSendSMS = 0;  # Explicit allow list approach - default to NOT sending
    
    # For NEW tickets - ALWAYS send SMS
    if ( $Param{Event} eq 'TicketCreate' ) {
        $EventType = 'new';
        $ShouldSendSMS = 1;
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS will be sent for NEW ticket $Ticket{TicketNumber}",
        );
    }
    # For STATE updates - Send for assigned, resolved, and reopened
    elsif ( $Param{Event} eq 'TicketStateUpdate' ) {
        if ( $Param{Data}->{OldTicketData} && $Param{Data}->{OldTicketData}->{State} ) {
            my $OldState = $Param{Data}->{OldTicketData}->{State};
            my $NewState = $Ticket{State};
            
            # No actual change? Skip SMS
            if ( $OldState eq $NewState ) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS skipped for ticket $Ticket{TicketNumber} - state didn't change (still '$NewState')",
                );
                # $ShouldSendSMS remains 0
            }
            # Changed TO new?
            elsif ( $OldState !~ /^new$/i && $NewState =~ /^new$/i ) {
                $EventType = 'new';
                $ShouldSendSMS = 1;
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS will be sent for NEW ticket $Ticket{TicketNumber} (transition: '$OldState' -> '$NewState')",
                );
            }
            # Changed TO assigned?
            elsif ( $OldState !~ /^assigned$/i && $NewState =~ /^assigned$/i ) {
                $EventType = 'assigned';
                $IsAssignedEvent = 1;  # Mark as assigned event
                $ShouldSendSMS = 1;
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS will be sent for ASSIGNED ticket $Ticket{TicketNumber} (transition: '$OldState' -> '$NewState')",
                );
            }
            # Changed TO resolved?
            elsif ( $OldState !~ /resolved/i && $NewState =~ /resolved/i ) {
                $EventType = 'resolved';
                $IsResolvedEvent = 1;
                $ShouldSendSMS = 1;
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS will be sent for RESOLVED ticket $Ticket{TicketNumber} (transition: '$OldState' -> '$NewState')",
                );
            }
            # Reopened? Check if going FROM resolved TO an open state (excluding new and assigned which are handled above)
            elsif ( $OldState =~ /resolved/i && ($NewState =~ /^(open|pending|in[\s-]?progress|working)/i) ) {
                $EventType = 'reopened';
                $IsReopenedEvent = 1;  # Mark as reopened event
                $ShouldSendSMS = 1;
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS will be sent for REOPENED ticket $Ticket{TicketNumber} (transition from resolved: '$OldState' -> '$NewState')",
                );
            }
            # Regular update - DO NOT SEND SMS
            else {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS skipped for ticket $Ticket{TicketNumber} - regular update (transition: '$OldState' -> '$NewState') - NOT a create/assigned/resolve/reopen event",
                );
                # $ShouldSendSMS remains 0
            }
        }
        # No old data - $ShouldSendSMS remains 0 (can't determine state transition)
    }
    # For OWNER updates - Send SMS when ticket gets assigned to a user
    elsif ( $Param{Event} eq 'TicketOwnerUpdate' ) {
        if ( $Param{Data}->{OldTicketData} && defined $Param{Data}->{OldTicketData}->{OwnerID} ) {
            my $OldOwnerID = $Param{Data}->{OldTicketData}->{OwnerID};
            my $NewOwnerID = $Ticket{OwnerID};
            
            # No actual change? Skip SMS
            if ( $OldOwnerID == $NewOwnerID ) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS skipped for ticket $Ticket{TicketNumber} - owner didn't change (still OwnerID=$NewOwnerID)",
                );
                # $ShouldSendSMS remains 0
            }
            # Changed FROM root (unassigned) TO a real user?
            elsif ( $OldOwnerID == 1 && $NewOwnerID > 1 ) {
                $EventType = 'assigned';
                $IsAssignedEvent = 1;
                $ShouldSendSMS = 1;
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS will be sent for ticket $Ticket{TicketNumber} assigned to user (OwnerID: $OldOwnerID -> $NewOwnerID)",
                );
            }
            # Changed FROM one user TO another user (reassignment)
            elsif ( $OldOwnerID > 1 && $NewOwnerID > 1 && $OldOwnerID != $NewOwnerID ) {
                $EventType = 'reassigned';
                $IsAssignedEvent = 1;  # Treat reassignment like assignment
                $ShouldSendSMS = 1;
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS will be sent for ticket $Ticket{TicketNumber} reassigned between users (OwnerID: $OldOwnerID -> $NewOwnerID)",
                );
            }
            # Changed FROM user back TO root (unassigned)
            elsif ( $OldOwnerID > 1 && $NewOwnerID == 1 ) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS skipped for ticket $Ticket{TicketNumber} - ticket unassigned (OwnerID: $OldOwnerID -> 1) - not sending SMS",
                );
                # $ShouldSendSMS remains 0
            }
            # Other owner changes - skip SMS
            else {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS skipped for ticket $Ticket{TicketNumber} - owner change not relevant (OwnerID: $OldOwnerID -> $NewOwnerID)",
                );
                # $ShouldSendSMS remains 0
            }
        }
        # No old data - $ShouldSendSMS remains 0 (can't determine owner change)
    }
    # Any other event type - DO NOT SEND SMS
    else {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS skipped for ticket $Ticket{TicketNumber} - event '$Param{Event}' is not CREATE, ASSIGNED, RESOLVE, or REOPEN",
        );
        # $ShouldSendSMS remains 0
    }
    
    # Exit early if we should NOT send SMS
    if ( !$ShouldSendSMS ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS notification skipped for ticket $Ticket{TicketNumber} - only CREATE, ASSIGNED, RESOLVE, and REOPEN events trigger SMS",
        );
        return 1;
    }
    
    # Prevent duplicate SMS notifications within 60 seconds
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    my $CacheKey = "SMSNotification::Ticket::$Param{Data}->{TicketID}";
    my $LastSent = $CacheObject->Get(
        Type => 'SMSNotification',
        Key  => $CacheKey,
    );
    
    if ($LastSent) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS notification skipped for ticket $Ticket{TicketNumber} - already sent within last 60 seconds",
        );
        return 1;
    }

    # ROBUST priority mapping - handle ALL possible formats
    my %PriorityMapping = (
        # Full format
        'P1-Critical' => 1, 'P2-High' => 2, 'P3-Medium' => 3, 'P4-Low' => 4,
        # Short format
        'P1' => 1, 'P2' => 2, 'P3' => 3, 'P4' => 4,
        # Lowercase
        'p1-critical' => 1, 'p2-high' => 2, 'p3-medium' => 3, 'p4-low' => 4,
        'p1' => 1, 'p2' => 2, 'p3' => 3, 'p4' => 4,
        # Number only
        '1' => 1, '2' => 2, '3' => 3, '4' => 4,
        # Alternative names
        'Critical' => 1, 'High' => 2, 'Medium' => 3, 'Low' => 4,
        'critical' => 1, 'high' => 2, 'medium' => 3, 'low' => 4,
    );
    
    # Get Twilio SMS service
    my $TwilioSMSObject = $Kernel::OM->Get('Kernel::System::TwilioSMS');
    
    # Check SMS configuration
    my %Config = $TwilioSMSObject->GetConfiguration();
    if ( !$Config{Success} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "SMS notification configuration error: $Config{ErrorMessage}",
        );
        return;
    }
    
    $LogObject->Log(
        Priority => 'notice',
        Message  => "SMS Event Handler: Configuration validated successfully",
    );
    
    # Collect all recipients (assigned user + default recipients)
    my @Recipients;
    my $Message;
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');

    # Add assigned user to recipients if ticket has an assigned owner (not root/admin)
    $LogObject->Log(
        Priority => 'info',
        Message  => "SMS Debug: Checking assigned user - OwnerID: '" . ($Ticket{OwnerID} || 'UNDEF') . "', Owner: '" . ($Ticket{Owner} || 'UNDEF') . "'",
    );
    
    if ( $Ticket{OwnerID} && $Ticket{OwnerID} != 1 ) {
        $LogObject->Log(
            Priority => 'info',
            Message  => "SMS Debug: Processing assigned user with OwnerID=$Ticket{OwnerID}",
        );
        
        # Get assigned user data
        my %User = $UserObject->GetUserData(
            UserID => $Ticket{OwnerID},
        );
        
        if ( !%User ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "SMS Debug: Failed to get user data for OwnerID=$Ticket{OwnerID}",
            );
        } else {
            $LogObject->Log(
                Priority => 'info',
                Message  => "SMS Debug: Found user '" . ($User{UserLogin} || 'UNKNOWN') . "' for OwnerID=$Ticket{OwnerID}",
            );
            
            # Check if user is in NOCUser OR NOCAdmin group
            my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
            
            # Check NOCUser group
            my $NOCUserGroupID = $GroupObject->GroupLookup(
                Group => 'NOCUser',
            );
            
            # Check NOCAdmin group
            my $NOCAdminGroupID = $GroupObject->GroupLookup(
                Group => 'NOCAdmin',
            );
            
            $LogObject->Log(
                Priority => 'info',
                Message  => "SMS Debug: NOCUser GroupID=" . ($NOCUserGroupID || 'NOT_FOUND') . ", NOCAdmin GroupID=" . ($NOCAdminGroupID || 'NOT_FOUND'),
            );
            
            my $UserInGroup = 0; # Start with false, will set to true if in either group
            
            # Check NOCAdmin group first (higher privilege)
            if ( $NOCAdminGroupID ) {
                my %GroupUsers = $GroupObject->PermissionGroupUserGet(
                    GroupID => $NOCAdminGroupID,
                    Type    => 'rw',
                );
                
                if ( $GroupUsers{$Ticket{OwnerID}} ) {
                    $UserInGroup = 1;
                    $LogObject->Log(
                        Priority => 'info',
                        Message  => "SMS Debug: User $User{UserLogin} has 'rw' permission in NOCAdmin group",
                    );
                } else {
                    # Check read-only permissions
                    %GroupUsers = $GroupObject->PermissionGroupUserGet(
                        GroupID => $NOCAdminGroupID,
                        Type    => 'ro',
                    );
                    
                    if ( $GroupUsers{$Ticket{OwnerID}} ) {
                        $UserInGroup = 1;
                        $LogObject->Log(
                            Priority => 'info',
                            Message  => "SMS Debug: User $User{UserLogin} has 'ro' permission in NOCAdmin group",
                        );
                    }
                }
            }
            
            # If not in NOCAdmin, check NOCUser group
            if ( !$UserInGroup && $NOCUserGroupID ) {
                my %GroupUsers = $GroupObject->PermissionGroupUserGet(
                    GroupID => $NOCUserGroupID,
                    Type    => 'rw',
                );
                
                $LogObject->Log(
                    Priority => 'info',
                    Message  => "SMS Debug: NOCUser group has " . scalar(keys %GroupUsers) . " users with 'rw' permission",
                );
                
                if ( $GroupUsers{$Ticket{OwnerID}} ) {
                    $UserInGroup = 1;
                    $LogObject->Log(
                        Priority => 'info',
                        Message  => "SMS Debug: User $User{UserLogin} has 'rw' permission in NOCUser group",
                    );
                } else {
                    # Check read-only permissions
                    %GroupUsers = $GroupObject->PermissionGroupUserGet(
                        GroupID => $NOCUserGroupID,
                        Type    => 'ro',
                    );
                    
                    if ( $GroupUsers{$Ticket{OwnerID}} ) {
                        $UserInGroup = 1;
                        $LogObject->Log(
                            Priority => 'info',
                            Message  => "SMS Debug: User $User{UserLogin} has 'ro' permission in NOCUser group",
                        );
                    }
                }
            }
            
            # If no groups exist, default to allowing SMS
            if ( !$NOCUserGroupID && !$NOCAdminGroupID ) {
                $UserInGroup = 1;
                $LogObject->Log(
                    Priority => 'info',
                    Message  => "SMS Debug: No NOC groups found, defaulting to allow SMS for assigned user",
                );
            }
            
            if ( !$UserInGroup ) {
                $LogObject->Log(
                    Priority => 'notice',
                    Message  => "SMS notification: assigned user $User{UserLogin} (ID=$Ticket{OwnerID}) is NOT in NOCUser or NOCAdmin group - skipping SMS",
                );
            }
            
            if ( $UserInGroup ) {
                $LogObject->Log(
                    Priority => 'info',
                    Message  => "SMS Debug: User $User{UserLogin} is in NOCUser group (or group check disabled), checking for mobile number",
                );
                
                # Get mobile phone from preferences
                my %Preferences = $UserObject->GetPreferences(
                    UserID => $Ticket{OwnerID},
                );
                
                # Debug all preferences
                my $PrefCount = scalar(keys %Preferences);
                $LogObject->Log(
                    Priority => 'info',
                    Message  => "SMS Debug: User $User{UserLogin} has $PrefCount preferences",
                );
                
                # Check specifically for UserMobile
                my $UserMobile = $Preferences{UserMobile};
                
                $LogObject->Log(
                    Priority => 'info',
                    Message  => "SMS Debug: UserMobile preference value: '" . ($UserMobile || 'EMPTY') . "' for user $User{UserLogin}",
                );
                
                # Also check if it might be stored in User data directly
                if ( !$UserMobile && $User{UserMobile} ) {
                    $UserMobile = $User{UserMobile};
                    $LogObject->Log(
                        Priority => 'info',
                        Message  => "SMS Debug: Found mobile in User data: '$UserMobile' for user $User{UserLogin}",
                    );
                }
                
                if ( $UserMobile ) {
                    # Clean the mobile number (remove spaces, ensure it starts with +)
                    $UserMobile =~ s/\s+//g;  # Remove all spaces
                    if ( $UserMobile !~ /^\+/ ) {
                        # If doesn't start with +, assume it's a US number
                        $UserMobile = "+1" . $UserMobile if $UserMobile =~ /^\d{10}$/;
                    }
                    
                    push @Recipients, $UserMobile;
                    $LogObject->Log(
                        Priority => 'notice',
                        Message  => "SMS notification: SUCCESS - Added assigned user $User{UserLogin} (ID=$Ticket{OwnerID}) phone: $UserMobile",
                    );
                } else {
                    $LogObject->Log(
                        Priority => 'notice',
                        Message  => "SMS notification: No mobile phone number found for assigned user $User{UserLogin} (ID=$Ticket{OwnerID})",
                    );
                }
            }
        }
    } else {
        $LogObject->Log(
            Priority => 'info',
            Message  => "SMS Debug: Skipping assigned user - OwnerID is 1 (root) or not set",
        );
    }

    # Check if priority is enabled for SMS - this determines if default recipients should be added
    my $ConfigKey = $PriorityMapping{$Ticket{Priority}} || 0;
    my $ConfigSettingName = "SMSNotification::Priority::" . $ConfigKey . "::Enabled";
    my $PriorityEnabled = $ConfigKey ? ($ConfigObject->Get($ConfigSettingName) || '0') : '0';
    
    # DEBUG: Return exact values for API debugging
    my $DebugMsg = "SMS DEBUG: Ticket=$Ticket{TicketNumber}, RawPriority='$Ticket{Priority}', MappedKey=$ConfigKey, ConfigSetting='$ConfigSettingName', EnabledValue='$PriorityEnabled'";
    $LogObject->Log(
        Priority => 'info',
        Message  => $DebugMsg,
    );
    
    # Also log ALL priority settings for debugging
    for my $P (1..4) {
        my $SettingName = "SMSNotification::Priority::" . $P . "::Enabled";
        my $Val = $ConfigObject->Get($SettingName) || 'UNDEF';
        $LogObject->Log(
            Priority => 'info',
            Message  => "SMS DEBUG: Priority $P enabled = '$Val'",
        );
    }
    
    # For tickets changing TO resolved or being reopened, priority settings still apply
    # SMS will only be sent if the priority is enabled
    $LogObject->Log(
        Priority => 'info',
        Message  => "SMS DEBUG: State check - State='$Ticket{State}', EventType='$EventType', PriorityEnabled='$PriorityEnabled'",
    );
    
    if ( $IsResolvedEvent ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS notification for ticket CHANGING TO RESOLVED $Ticket{TicketNumber} - will ALWAYS send (bypasses priority check)",
        );
    }
    
    if ( $IsReopenedEvent ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS notification for ticket REOPENED $Ticket{TicketNumber} - priority check will apply",
        );
    }
    
    if ( $IsAssignedEvent ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS notification for ticket ASSIGNED $Ticket{TicketNumber} - priority check will apply",
        );
    }
    
    # IMPORTANT: Default recipients and assigned users have DIFFERENT rules:
    # - ASSIGNED USERS: Get SMS for important events (NEW, ASSIGNED, RESOLVED, REOPENED) regardless of priority
    #   (Already handled above in lines 206-407)
    # - DEFAULT RECIPIENTS: ONLY get SMS when priority is ENABLED - this applies to ALL events
    
    # Check if default recipients should be added based on priority setting
    my $ShouldAddDefaultRecipients = 0;
    my $Reason = '';
    
    # DEFAULT RECIPIENTS: Only add if priority is enabled (applies to ALL event types)
    if ($PriorityEnabled && $PriorityEnabled ne '0') {
        # Priority is enabled - add default recipients for any event type
        $ShouldAddDefaultRecipients = 1;
        
        # Build reason message based on event type
        if ($IsResolvedEvent) {
            $Reason = "RESOLVED ticket with priority $Ticket{Priority} enabled";
        }
        elsif ($EventType eq 'new') {
            $Reason = "NEW ticket with priority $Ticket{Priority} enabled";
        }
        elsif ($IsAssignedEvent) {
            my $AssignmentType = $EventType eq 'reassigned' ? 'REASSIGNED' : 'ASSIGNED';
            $Reason = "$AssignmentType ticket with priority $Ticket{Priority} enabled";
        }
        elsif ($IsReopenedEvent) {
            $Reason = "REOPENED ticket with priority $Ticket{Priority} enabled";
        }
        else {
            $Reason = "ticket update with priority $Ticket{Priority} enabled";
        }
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS notification for $EventType ticket $Ticket{TicketNumber} - priority enabled, will add default recipients",
        );
    }
    else {
        # Priority is disabled - skip default recipients for ALL event types
        my $EventDescription = $IsResolvedEvent ? 'RESOLVED' : 
                               $IsReopenedEvent ? 'REOPENED' : 
                               $IsAssignedEvent ? ($EventType eq 'reassigned' ? 'REASSIGNED' : 'ASSIGNED') :
                               $EventType eq 'new' ? 'NEW' : 'UPDATE';
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "Priority $Ticket{Priority} is disabled for $EventDescription ticket - skipping default recipients (ConfigKey: $ConfigKey, Enabled: '" . ($PriorityEnabled || '0') . "')",
        );
    }
    
    if ($ShouldAddDefaultRecipients) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "Adding default recipients because: $Reason",
        );
        
        # Add default recipients from configuration
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS Debug: DefaultRecipients value: '" . ($Config{DefaultRecipients} || 'EMPTY') . "'",
        );
        
        if ( $Config{DefaultRecipients} ) {
            my @DefaultNumbers = $TwilioSMSObject->ParseRecipients(
                Recipients => $Config{DefaultRecipients}
            );
            
            for my $Number (@DefaultNumbers) {
                # Check for duplicates
                if ( !grep { $_ eq $Number } @Recipients ) {
                    push @Recipients, $Number;
                    $LogObject->Log(
                        Priority => 'notice',
                        Message  => "SMS notification: Added default recipient: $Number",
                    );
                }
            }
        }
    }

    # Check if we have any recipients
    $LogObject->Log(
        Priority => 'notice',
        Message  => "SMS Debug: Total recipients found: " . scalar(@Recipients) . " for ticket $Ticket{TicketNumber}",
    );
    
    if ( !@Recipients ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "SMS notification skipped - no valid recipients for ticket $Ticket{TicketNumber}",
        );
        return 1;
    }
    
    # Get system URL configuration
    my $HttpType = $ConfigObject->Get('HttpType') || 'http';
    my $FQDN = $ConfigObject->Get('FQDN') || 'localhost';
    my $ScriptAlias = $ConfigObject->Get('ScriptAlias') || 'otrs/';
    
    # Get CI and Site information from dynamic fields
    my $CI = $Ticket{DynamicField_CI} || 'N/A';
    my $Site = $Ticket{DynamicField_EventSite} || 'N/A';
    
    # Format state for display
    my $StateDisplay = uc($EventType);
    
    # Build message with LSMP branding and CI/Site information
    # Show "Unassigned" if OwnerID is 1 (root user) or not set
    my $AssigneeDisplay = ($Ticket{OwnerID} && $Ticket{OwnerID} != 1) ? $Ticket{Owner} : 'Unassigned';
    
    $Message = sprintf(
        "[LSMP Alert - %s]\nTicket#%s\nPriority:%s\nTitle:%s\nCI:%s\nSite:%s\nAssignee:%s",
        $StateDisplay,
        $Ticket{TicketNumber},
        $Ticket{Priority},
        $Ticket{Title},  # No longer truncating title
        $CI,
        $Site,
        $AssigneeDisplay
    );
    
    $LogObject->Log(
        Priority => 'info',
        Message  => "SMS notification will be sent to " . scalar(@Recipients) . " recipients for ticket $Ticket{TicketNumber} (event: $StateDisplay)",
    );

    # Send SMS using TwilioSMS class
    my %Result = $TwilioSMSObject->SendSMS(
        Recipients => \@Recipients,
        Message    => $Message,
    );

    if ( $Result{Success} ) {
        $LogObject->Log(
            Priority => 'info',
            Message  => "SMS notification SENT for ticket $Ticket{TicketNumber}: $Result{SuccessCount} successful, $Result{FailureCount} failed",
        );
        
        # Cache that we sent SMS for this ticket to prevent duplicates
        $CacheObject->Set(
            Type  => 'SMSNotification',
            Key   => $CacheKey,
            Value => 1,
            TTL   => 60,  # 60 seconds
        );
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => "SMS notification failed for ticket $Ticket{TicketNumber}: $Result{ErrorMessage}",
        );
    }

    return 1;
}

=head2 SendSMSForTicket()

Send SMS for a ticket from any context (not just events).

    my $Result = $SMSNotification->SendSMSForTicket(
        TicketID      => 123,
        Event         => 'Manual',    # Optional
        OldTicketData => \%OldData,   # Optional
        UserID        => 1,           # Optional
    );

Returns:
    1 on success, 0 on failure

=cut

sub SendSMSForTicket {
    my ( $Self, %Param ) = @_;
    
    return if !$Param{TicketID};
    
    # Build event data structure for Run()
    my %EventData = (
        Data => {
            TicketID => $Param{TicketID},
            OldTicketData => $Param{OldTicketData},
        },
        Event => $Param{Event} || 'Manual',
        Config => {},
        UserID => $Param{UserID} || 1,
    );
    
    return $Self->Run(%EventData);
}

1;