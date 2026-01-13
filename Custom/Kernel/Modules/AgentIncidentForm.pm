# --
# Copyright (C) 2024 Radiant Digital, radiant.digital
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AgentIncidentForm;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject       = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject        = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $IncidentObject     = $Kernel::OM->Get('Kernel::System::Incident');
    my $TicketObject       = $Kernel::OM->Get('Kernel::System::Ticket');
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $ConfigObject       = $Kernel::OM->Get('Kernel::Config');
    my $UserObject         = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject        = $Kernel::OM->Get('Kernel::System::Group');

    # Check permissions
    if ( !$Self->{UserID} ) {
        return $LayoutObject->NoPermission(
            Message    => Translatable('You need to be logged in to access this page.'),
            WithHeader => 'yes',
        );
    }

    # Get parameters
    my %GetParam;
    for my $Param (
        qw(Subaction IncidentID IncidentNumber TicketID
        Source Priority State CI AssignedTo
        ShortDescription Description
        ProductCat1 ProductCat2 ProductCat3 ProductCat4
        OperationalCat1 OperationalCat2 OperationalCat3
        ResolutionCat1 ResolutionCat2 ResolutionCat3
        ResolutionNotes
        WorkNoteText IncludeInMSI
        )
        )
    {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }

    # Handle AJAX category requests
    if ( $GetParam{Subaction} && ($GetParam{Subaction} eq 'CategoryGet' || $GetParam{Subaction} eq 'LoadCategories') ) {
        return $Self->_LoadCategories(%GetParam);
    }

    # Handle AJAX state validation
    if ( $GetParam{Subaction} && $GetParam{Subaction} eq 'ValidateState' ) {
        return $Self->_ValidateStateTransition(%GetParam);
    }

    # Handle AJAX work note addition
    if ( $GetParam{Subaction} && $GetParam{Subaction} eq 'AddWorkNote' ) {
        return $Self->_AddWorkNote(%GetParam);
    }

    # Handle AJAX resolution note addition
    if ( $GetParam{Subaction} && $GetParam{Subaction} eq 'AddResolutionNote' ) {
        return $Self->_AddResolutionNote(%GetParam);
    }

    # Handle AJAX user loading for groups
    if ( $GetParam{Subaction} && $GetParam{Subaction} eq 'LoadAssignedUsers' ) {
        return $Self->_LoadAssignedUsers(%GetParam);
    }

    # Handle Easy MSI Escalation ServiceNow submission
    if ( $GetParam{Subaction} && $GetParam{Subaction} eq 'SubmitToServiceNow' ) {
        return $Self->_SubmitToServiceNow(%GetParam);
    }

    # Handle Easy MSI Escalation ServiceNow pull/sync
    if ( $GetParam{Subaction} && $GetParam{Subaction} eq 'PullFromServiceNow' ) {
        return $Self->_PullFromServiceNow(%GetParam);
    }

    # Determine action
    my $SubactionToPerform = $GetParam{Subaction} || 'Create';
    

    # Create new incident
    if ( $SubactionToPerform eq 'Create' ) {
        return $Self->_ShowForm(
            %GetParam,
            Action => 'Create',
        );
    }

    # Process new incident creation
    elsif ( $SubactionToPerform eq 'CreateAction' ) {
        
        # Validate required fields
        my %Error;
        my @MissingFields;
        for my $Required (qw(Source Priority ShortDescription ProductCat1 ProductCat2 OperationalCat1 OperationalCat2)) {
            if ( !$GetParam{$Required} ) {
                $Error{ $Required . 'Invalid' } = 'ServerError';
                push @MissingFields, $Required;
            }
        }
        
        # AssignedTo is required if state is "Assigned"
        if ( $GetParam{State} && lc($GetParam{State}) eq 'assigned' && !$GetParam{AssignedTo} ) {
            $Error{'AssignedToInvalid'} = 'ServerError';
            push @MissingFields, 'AssignedTo';
        }

        # Check for errors
        if (%Error) {
            
            # Add error message to form
            $GetParam{ValidationError} = 1;
            $GetParam{MissingFields} = \@MissingFields;
            
            return $Self->_ShowForm(
                %GetParam,
                %Error,
                Action => 'Create',
            );
        }


        # Create incident
        
        my $State = $GetParam{State} || 'new';
            if ($GetParam{AssignedTo}) {
            $State = 'assigned';
        }

        my $IncidentID = $IncidentObject->IncidentCreate(
            Source           => $GetParam{Source} || 'Direct Input',  # Default to Direct Input
            Priority         => $GetParam{Priority},
            State            => $State,
            CI               => $GetParam{CI} || '',
            AssignedTo       => $GetParam{AssignedTo} || '',
            ShortDescription => $GetParam{ShortDescription},
            Description      => $GetParam{Description} || '',
            ProductCat1      => $GetParam{ProductCat1},
            ProductCat2      => $GetParam{ProductCat2},
            ProductCat3      => $GetParam{ProductCat3} || '',
            ProductCat4      => $GetParam{ProductCat4} || '',
            OperationalCat1  => $GetParam{OperationalCat1},
            OperationalCat2  => $GetParam{OperationalCat2},
            OperationalCat3  => $GetParam{OperationalCat3} || '',
            UserID           => $Self->{UserID},
        );

        # Send SMS notification directly for new incident created via web form
        if ( $IncidentID ) {
            eval {
                # Send SMS notification using the event handler
                my $SMSNotification = $Kernel::OM->Get('Kernel::System::Ticket::Event::SMSNotification');
                $SMSNotification->SendSMSForTicket(
                    TicketID => $IncidentID,
                    Event    => 'IncidentFormCreate',
                    UserID   => $Self->{UserID},
                );
            };
            if ($@) {
                # Log error but don't fail the incident creation
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "SMS notification error (non-critical): $@",
                );
            }
        }

        if ( !$IncidentID ) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Incident could not be created!'),
            );
        }


        # Get incident data
        my %Incident = $IncidentObject->IncidentGet(
            IncidentID => $IncidentID,
            UserID     => $Self->{UserID},
        );

        # Check which button was clicked
        my $SubmitButton = $ParamObject->GetParam( Param => 'SubmitButton' ) || 'Save';

        # Redirect based on button clicked
        if ( $SubmitButton eq 'SaveAndClose' ) {
            # Redirect to dashboard with the ticket number as a URL parameter
            # This ensures it only shows ONCE when we redirect, not on every page load
            return $LayoutObject->Redirect(
                OP => "Action=AgentDashboard;IncidentCreated=$Incident{IncidentNumber}"
            );
        }
        else {
            # Redirect to update view (default "Save" behavior)
            return $LayoutObject->Redirect(
                OP => "Action=AgentIncidentForm;Subaction=Update;IncidentID=$IncidentID;IncidentCreated=1"
            );
        }
    }

    # Update existing incident
    elsif ( $SubactionToPerform eq 'Update' ) {

        # Get incident data
        my %Incident;
        if ( $GetParam{IncidentID} ) {
            %Incident = $IncidentObject->IncidentGet(
                IncidentID => $GetParam{IncidentID},
                UserID     => $Self->{UserID},
            );
        }
        elsif ( $GetParam{IncidentNumber} ) {
            %Incident = $IncidentObject->IncidentGet(
                IncidentNumber => $GetParam{IncidentNumber},
                UserID         => $Self->{UserID},
            );
            # Set IncidentID for form processing
            $GetParam{IncidentID} = $Incident{IncidentID};
        }

        if ( !%Incident ) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Incident not found!'),
            );
        }

        # No need to clear session notifications anymore - we're using URL parameters

        return $Self->_ShowForm(
            %GetParam,
            %Incident,
            Action => 'Update',
        );
    }

    # Process incident update
    elsif ( $SubactionToPerform eq 'UpdateAction' ) {
        
        # Get incident data - handle both IncidentID and IncidentNumber
        my %Incident;
        if ( $GetParam{IncidentID} ) {
            %Incident = $IncidentObject->IncidentGet(
                IncidentID => $GetParam{IncidentID},
                UserID     => $Self->{UserID},
            );
        }
        elsif ( $GetParam{IncidentNumber} ) {
            %Incident = $IncidentObject->IncidentGet(
                IncidentNumber => $GetParam{IncidentNumber},
                UserID         => $Self->{UserID},
            );
            # Set IncidentID for further processing
            $GetParam{IncidentID} = $Incident{IncidentID};
        }
        
        if ( !%Incident ) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Incident not found!'),
            );
        }
        
        my $CurrentState = $Incident{State};
        
        # Check if incident is in closed or cancelled state
        if ( $CurrentState && $CurrentState =~ /^(closed|cancelled)/i ) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Cannot update incidents in closed or cancelled state'),
                Comment => Translatable('Incidents in closed or cancelled state are read-only and cannot be modified.'),
            );
        }

        # State validation removed - all transitions are now allowed
        # No need to check ValidateStateTransition anymore

        # Validate required fields for updates
        my %Error;
        my @MissingFields;
        
        # Basic required fields for all updates
        for my $Required (qw(Priority State ShortDescription)) {
            if ( !$GetParam{$Required} ) {
                $Error{ $Required . 'Invalid' } = 'ServerError';
                push @MissingFields, $Required;
            }
        }
        
        # AssignedTo is required for certain states
        if ( $GetParam{State} ) {
            my $StateLower = lc($GetParam{State});
            my @StatesRequiringAssignee = ('assigned', 'in progress', 'pending', 'resolved');
            
            my $RequiresAssignee = 0;
            for my $RequiredState (@StatesRequiringAssignee) {
                if ( index($StateLower, $RequiredState) != -1 ) {
                    $RequiresAssignee = 1;
                    last;
                }
            }
            
            if ( $RequiresAssignee && !$GetParam{AssignedTo} ) {
                $Error{'AssignedToInvalid'} = 'ServerError';
                push @MissingFields, 'AssignedTo';
            }
        }
        
        # Resolution fields are required when state is "Resolved"
        if ( $GetParam{State} && lc($GetParam{State}) eq 'resolved' ) {
            for my $Required (qw(ResolutionCat1 ResolutionCat2 ResolutionNotes)) {
                if ( !$GetParam{$Required} ) {
                    $Error{ $Required . 'Invalid' } = 'ServerError';
                    push @MissingFields, $Required;
                }
            }
        }

        if (%Error) {
            
            # Get current incident data to preserve form values
            my %Incident = $IncidentObject->IncidentGet(
                IncidentID => $GetParam{IncidentID},
                UserID     => $Self->{UserID},
            );
            
            return $Self->_ShowForm(
                %Incident,     # Current incident data
                %GetParam,     # User's form input (overrides incident data)
                %Error,        # Validation errors
                ValidationError => 1,
                MissingFields => \@MissingFields,
                Action => 'Update',
            );
        }

        # Auto-assign state to "Assigned" if an owner is selected and the ticket is new
        if (lc($GetParam{State}) eq 'new' && $GetParam{AssignedTo}) {
            $GetParam{State} = 'assigned';
        }

        # Update incident
        my $Success = $IncidentObject->IncidentUpdate(
            IncidentID       => $GetParam{IncidentID},
            Priority         => $GetParam{Priority},
            State            => $GetParam{State},
            CI               => $GetParam{CI},
            AssignedTo       => $GetParam{AssignedTo},
            ShortDescription => $GetParam{ShortDescription},
            Description      => $GetParam{Description},
            ProductCat1      => $GetParam{ProductCat1},
            ProductCat2      => $GetParam{ProductCat2},
            ProductCat3      => $GetParam{ProductCat3},
            ProductCat4      => $GetParam{ProductCat4},
            OperationalCat1  => $GetParam{OperationalCat1},
            OperationalCat2  => $GetParam{OperationalCat2},
            OperationalCat3  => $GetParam{OperationalCat3},
            ResolutionCat1   => $GetParam{ResolutionCat1},
            ResolutionCat2   => $GetParam{ResolutionCat2},
            ResolutionCat3   => $GetParam{ResolutionCat3},
            ResolutionNotes  => $GetParam{ResolutionNotes},
            UserID           => $Self->{UserID},
        );
        
        if (!$Success) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Failed to update incident!'),
            );
        }

        # Send SMS notification only for RESOLVED and REOPENED state changes
        my $SendSMS = 0;
        my $EventType = '';
        
        # CRITICAL DEBUG LOGGING
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "SMS DEBUG: State transition check - OLD STATE: '$Incident{State}' => NEW STATE: '$GetParam{State}'",
        );
        
        # Only send SMS if state is CHANGING TO resolved, not when it's already resolved
        if ( $GetParam{State} && ($GetParam{State} =~ /closed|resolved/i) &&
             $Incident{State} && !($Incident{State} =~ /closed|resolved/i) ) {
            # State is changing FROM non-resolved TO resolved
            $SendSMS = 1;
            $EventType = 'resolved';
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "SMS DEBUG: RESOLVED state detected - will send SMS",
            );
        }
        # Check if this is a reopened state (from closed/resolved to any open state)
        # FIXED: Also check for 'assigned', 'in progress' states as reopened
        elsif ( $Incident{State} && $Incident{State} =~ /closed|resolved/i && 
                $GetParam{State} && $GetParam{State} =~ /new|open|assigned|in progress/i ) {
            $SendSMS = 1;
            $EventType = 'reopened';
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "SMS DEBUG: REOPENED state detected - will send SMS",
            );
        }
        else {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "SMS DEBUG: No SMS trigger - transition from '$Incident{State}' to '$GetParam{State}' doesn't match rules",
            );
        }
        
        if ( $SendSMS ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'info',
                Message  => "SMS: Attempting to send SMS for event type: $EventType",
            );
            eval {
                # Build old ticket data for state change detection
                my %OldTicketData;
                if ( $Incident{State} ) {
                    $OldTicketData{State} = $Incident{State};
                }
                # Send SMS notification using the event handler
                my $SMSNotification = $Kernel::OM->Get('Kernel::System::Ticket::Event::SMSNotification');
                $SMSNotification->SendSMSForTicket(
                    TicketID      => $GetParam{IncidentID},
                    Event         => 'IncidentFormUpdate',
                    OldTicketData => \%OldTicketData,
                    UserID        => $Self->{UserID},
                );
            };
            if ($@) {
                # Log error but don't fail the incident update
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "SMS notification error (non-critical): $@",
                );
            }
        }

        # Add work note if provided
        if ( $GetParam{WorkNoteText} ) {
            $IncidentObject->AddWorkNote(
                IncidentID   => $GetParam{IncidentID},
                Note         => $GetParam{WorkNoteText},
                IncludeInMSI => 1,  # Always include in MSI
                UserID       => $Self->{UserID},
            );
        }
        
        # Add resolution history whenever resolution information is provided
        if ( $GetParam{ResolutionNotes} ) {
            # Get user info
            my $UserObject = $Kernel::OM->Get('Kernel::System::User');
            my %User = $UserObject->GetUserData(
                UserID => $Self->{UserID},
            );
            
            $IncidentObject->AddResolutionNote(
                IncidentID       => $GetParam{IncidentID},
                ResolutionCat1   => $GetParam{ResolutionCat1},
                ResolutionCat2   => $GetParam{ResolutionCat2},
                ResolutionCat3   => $GetParam{ResolutionCat3},
                    ResolutionNotes  => $GetParam{ResolutionNotes},
                UserID           => $Self->{UserID},
                CreatedBy        => $Self->{UserID},
                CreatedByName    => "$User{UserFirstname} $User{UserLastname}",
            );
        }

        # Check which button was clicked
        my $SubmitButton = $ParamObject->GetParam( Param => 'SubmitButton' ) || 'Save';

        # Redirect based on button clicked
        if ( $SubmitButton eq 'SaveAndClose' ) {
            # Get the updated incident to get the proper ticket number
            my %UpdatedIncident = $IncidentObject->IncidentGet(
                IncidentID => $GetParam{IncidentID},
                UserID     => $Self->{UserID},
            );

            # Redirect to dashboard with the ticket number as a URL parameter
            return $LayoutObject->Redirect(
                OP => "Action=AgentDashboard;IncidentUpdated=$UpdatedIncident{IncidentNumber}"
            );
        }
        else {
            # Redirect to update view (default "Save" behavior)
            # Ensure we have a valid redirect parameter
            my $RedirectParam;
            if ($GetParam{IncidentNumber}) {
                $RedirectParam = "IncidentNumber=" . $GetParam{IncidentNumber};
            } elsif ($GetParam{IncidentID}) {
                $RedirectParam = "IncidentID=" . $GetParam{IncidentID};
            } else {
                # Fallback - shouldn't happen but just in case
                $RedirectParam = "IncidentID=" . $GetParam{IncidentID};
            }

            return $LayoutObject->Redirect(
                OP => "Action=AgentIncidentForm;Subaction=Update;$RedirectParam;IncidentUpdated=1"
            );
        }
    }

    # View incident (read-only)
    elsif ( $SubactionToPerform eq 'View' ) {
        
        # Get incident data
        my %Incident;
        if ( $GetParam{IncidentID} ) {
            %Incident = $IncidentObject->IncidentGet(
                IncidentID => $GetParam{IncidentID},
                UserID     => $Self->{UserID},
            );
        }

        if ( !%Incident ) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Incident not found!'),
            );
        }

        return $Self->_ShowForm(
            %GetParam,
            %Incident,
            Action   => 'View',
            ReadOnly => 1,
        );
    }

    
    return $LayoutObject->ErrorScreen(
        Message => Translatable('Invalid action!') . " Action: $SubactionToPerform",
    );
}

sub _ShowForm {
    my ( $Self, %Param ) = @_;

    my $LayoutObject        = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $IncidentObject      = $Kernel::OM->Get('Kernel::System::Incident');
    my $CategoryObject      = $Kernel::OM->Get('Kernel::System::IncidentCategory');
    my $ConfigObject        = $Kernel::OM->Get('Kernel::Config');
    my $UserObject          = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject         = $Kernel::OM->Get('Kernel::System::Group');
    my $CustomerUserObject  = $Kernel::OM->Get('Kernel::System::CustomerUser');

    # Check sync cooldown status (same as escalation view)
    my $SyncInCooldown = 0;
    my $SyncCooldownMinutes = 0;
    if ( $Param{IncidentID} ) {
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

        # Query cooldown table
        my $Success = $DBObject->Prepare(
            SQL   => "SELECT cooldown_until FROM bulk_update_cooldown WHERE ticket_id = ? AND cooldown_until > NOW()",
            Bind  => [ \$Param{IncidentID} ],
            Limit => 1,
        );

        if ($Success) {
            my @Row = $DBObject->FetchrowArray();
            if (@Row) {
                $SyncInCooldown = 1;

                # Calculate remaining minutes
                my $CooldownUntil = $Row[0];
                # Strip microseconds
                $CooldownUntil =~ s/\.\d+$//;

                my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
                my $CooldownEpoch = $TimeObject->TimeStamp2SystemTime( String => $CooldownUntil );
                my $CurrentEpoch = $TimeObject->SystemTime();
                my $RemainingSeconds = $CooldownEpoch - $CurrentEpoch;
                $SyncCooldownMinutes = int($RemainingSeconds / 60) + 1;  # Round up
            }
        }
    }

    $Param{SyncInCooldown} = $SyncInCooldown;
    $Param{SyncCooldownMinutes} = $SyncCooldownMinutes;

    # Get incident priority list
    my %PriorityList = (
        'P1' => 'P1-Critical',
        'P2' => 'P2-High',
        'P3' => 'P3-Medium',
        'P4' => 'P4-Low',
    );

    # Get incident state list - using lowercase to match Znuny states
    my %StateList = (
        'new'                => 'New',
        'assigned'           => 'Assigned',
        'in progress'        => 'In Progress',
        'pending'            => 'Pending',
        'resolved'           => 'Resolved',
        'closed'             => 'Closed',
        'closed successful'  => 'Closed Successful',
        'cancelled'          => 'Cancelled',
    );
    
    # Check if incident is in read-only state (closed or cancelled)
    my $ReadOnly = 0;
    if ( $Param{State} && $Param{State} =~ /^(closed|cancelled)/i ) {
        $ReadOnly = 1;
    }

    # Get allowed state transitions
    my @AllowedStates;
    if ( $Param{Action} eq 'Create' ) {
        # For creation, allow 'new' and 'assigned' states
        @AllowedStates = ('new', 'assigned');
    } else {
        # For updates, determine allowed states based on current state
        my $CurrentState = $Param{State} || '';
        
        # State-specific transitions
        if ( $CurrentState eq 'new' ) {
            # When in 'new' state, don't allow pending or resolved transitions
            # Remove 'new' from allowed states on update
            @AllowedStates = ('new','assigned', 'in progress', 'cancelled');
        }
        elsif ( $CurrentState eq 'assigned' ) {
            # When in 'assigned' state, only allow these transitions
            @AllowedStates = ('assigned', 'in progress', 'cancelled');
        }
        elsif ( $CurrentState eq 'in progress' ) {
            # When in 'in progress' state, only allow these transitions
            @AllowedStates = ('assigned', 'in progress', 'pending', 'resolved', 'cancelled');
        }
        elsif ( $CurrentState eq 'pending' ) {
            # When in 'pending' state, allow going back to in progress or forward to resolved
            @AllowedStates = ('in progress', 'pending', 'resolved', 'cancelled');
        }
        elsif ( $CurrentState eq 'resolved' ) {
            # When in 'resolved' state, allow these transitions
            @AllowedStates = ('assigned', 'in progress', 'pending', 'resolved', 'closed', 'cancelled');
        }
        elsif ( $CurrentState eq 'closed' || $CurrentState eq 'closed successful' ) {
            # When in 'closed' state, form should be read-only but show current state
            @AllowedStates = ('closed');
        }
        elsif ( $CurrentState eq 'cancelled' ) {
            # When in 'cancelled' state, form should be read-only but show current state
            @AllowedStates = ('cancelled');
        }
        else {
            # Default allowed states (excluding 'closed')
            @AllowedStates = ('assigned', 'in progress', 'cancelled');
        }
    }

    # Build state selection - filter out undefined states
    my %AllowedStateList;
    for my $State (@AllowedStates) {
        next if !$State;  # Skip empty/undefined states
        next if !exists $StateList{$State};  # Skip states not in our list
        $AllowedStateList{$State} = $StateList{$State};
    }

    # Get users for assignment
    my %UserList = $UserObject->UserList(
        Type  => 'Long',
        Valid => 1,
    );

    # Filter users by NOCUser and NOCAdmin groups only
    my %AssignmentUserList;
    
    # Get NOCUser and NOCAdmin group IDs
    my @AllowedGroups = qw(NOCUser NOCAdmin);
    my @GroupIDs;
    
    for my $GroupName (@AllowedGroups) {
        my $GroupID = $GroupObject->GroupLookup(
            Group => $GroupName,
        );
        push @GroupIDs, $GroupID if $GroupID;
    }
    
    # Get users that belong to NOCUser or NOCAdmin groups
    for my $GroupID (@GroupIDs) {
        my %GroupUserList = $GroupObject->PermissionGroupUserGet(
            GroupID => $GroupID,
            Type    => 'rw',  # Read/write permissions
        );
        
        for my $UserID (keys %GroupUserList) {
            if ($UserList{$UserID}) {
                $AssignmentUserList{$UserID} = $UserList{$UserID};
            }
        }
    }

    # Get category options
    my %CategoryOptions;

    # Product categories - load Tier 1 and filter based on license
    my $AllProductCat1 = $CategoryObject->CategoryGet(
        Type => 'product',
        Tier => 1,
    );

    # Filter ProductCat1 based on licensed technology
    my $LicenseObject = $Kernel::OM->Get('Kernel::System::AdminAddLicense');
    my $LicensedTech = $LicenseObject->GetLicensedTechnology();

    # Map license technology to tier1 category values
    my %TechMapping = (
        'WAVE On Prem' => 'WAVE',
        'ASTRO'        => 'ASTRO Infrastructure',
        'DIMETRA'      => 'DIMETRA',
    );

    # LSMP is always shown regardless of license
    my $LSMPName = 'Local Service Management Platform (LSMP)';

    # Filter categories based on license
    if ($LicensedTech && exists $TechMapping{$LicensedTech}) {
        my $AllowedTier1 = $TechMapping{$LicensedTech};
        $CategoryOptions{ProductCat1} = [
            grep { $_->{Name} eq $AllowedTier1 || $_->{Name} eq $LSMPName }
            @{$AllProductCat1}
        ];
    } else {
        # Fallback: show all if no license or unknown tech
        $CategoryOptions{ProductCat1} = $AllProductCat1;
    }
    
    
    
    
    if ( $Param{ProductCat1} ) {
        $CategoryOptions{ProductCat2} = $CategoryObject->CategoryGet(
            Type  => 'product',
            Tier  => 2,
            Tier1 => $Param{ProductCat1},
        );
    }
    
    if ( $Param{ProductCat2} ) {
        $CategoryOptions{ProductCat3} = $CategoryObject->CategoryGet(
            Type  => 'product',
            Tier  => 3,
            Tier1 => $Param{ProductCat1},
            Tier2 => $Param{ProductCat2},
        );
    }
    
    if ( $Param{ProductCat3} ) {
        $CategoryOptions{ProductCat4} = $CategoryObject->CategoryGet(
            Type  => 'product',
            Tier  => 4,
            Tier1 => $Param{ProductCat1},
            Tier2 => $Param{ProductCat2},
            Tier3 => $Param{ProductCat3},
        );
    }

    # Operational categories - always load Tier 1
    $CategoryOptions{OperationalCat1} = $CategoryObject->CategoryGet(
        Type => 'operational',
        Tier => 1,
    );
    
    
    if ( $Param{OperationalCat1} ) {
        $CategoryOptions{OperationalCat2} = $CategoryObject->CategoryGet(
            Type  => 'operational',
            Tier  => 2,
            Tier1 => $Param{OperationalCat1},
        );
    }
    
    if ( $Param{OperationalCat2} ) {
        $CategoryOptions{OperationalCat3} = $CategoryObject->CategoryGet(
            Type  => 'operational',
            Tier  => 3,
            Tier1 => $Param{OperationalCat1},
            Tier2 => $Param{OperationalCat2},
        );
    }

    # Resolution categories - always load Tier 1 for AJAX functionality
    $CategoryOptions{ResolutionCat1} = $CategoryObject->CategoryGet(
        Type => 'resolution',
        Tier => 1,
    );
    
    # Load additional resolution tiers if state requires and values exist
    if ( $Param{State} && ( $Param{State} eq 'resolved' || $Param{State} eq 'closed successful' ) ) {
        
        if ( $Param{ResolutionCat1} ) {
            $CategoryOptions{ResolutionCat2} = $CategoryObject->CategoryGet(
                Type  => 'resolution',
                Tier  => 2,
                Tier1 => $Param{ResolutionCat1},
            );
        }
        
        if ( $Param{ResolutionCat1} && $Param{ResolutionCat2} ) {
            $CategoryOptions{ResolutionCat3} = $CategoryObject->CategoryGet(
                Type  => 'resolution',
                Tier  => 3,
                Tier1 => $Param{ResolutionCat1},
                Tier2 => $Param{ResolutionCat2},
            );
        }
    }
    # Also load resolution categories when editing if values exist
    elsif ( $Param{Action} && $Param{Action} eq 'Update' && $Param{ResolutionCat1} ) {
        $CategoryOptions{ResolutionCat2} = $CategoryObject->CategoryGet(
            Type  => 'resolution',
            Tier  => 2,
            Tier1 => $Param{ResolutionCat1},
        );
        
        if ( $Param{ResolutionCat2} ) {
            $CategoryOptions{ResolutionCat3} = $CategoryObject->CategoryGet(
                Type  => 'resolution',
                Tier  => 3,
                Tier1 => $Param{ResolutionCat1},
                Tier2 => $Param{ResolutionCat2},
            );
        }
    }

    # Build dropdown strings
    # Source is now a read-only field - always "Direct Input" for manual creation
    # (Event Monitoring will be set when incidents come through API)
    
    # Priority dropdown
    $Param{PriorityStrg} = $LayoutObject->BuildSelection(
        Data         => \%PriorityList,
        Name         => 'Priority',
        SelectedID   => $Param{Priority} || 'P3',
        Class        => 'Modernize Validate_Required',
        PossibleNone => 0,
        Disabled     => $ReadOnly,
    );
    
    # State dropdown
    $Param{StateStrg} = $LayoutObject->BuildSelection(
        Data         => \%AllowedStateList,
        Name         => 'State',
        SelectedID   => $Param{State} || 'new',
        Class        => 'Modernize Validate_Required',
        PossibleNone => 0,
        Disabled     => $ReadOnly,
    );
    
    # Assignment Group dropdown - show only MSI/NOC groups but map to queues via hidden field
    my %AllGroups = $GroupObject->GroupList(
        Valid => 1,
    );
    
    # Filter to only show MSI/NOC groups
    my %MSIGroupList;
    my @MSIGroups = qw(MSIAdmin NOCAdmin NOCUser);
    for my $GroupID ( keys %AllGroups ) {
        if ( grep { $AllGroups{$GroupID} eq $_ } @MSIGroups ) {
            $MSIGroupList{$GroupID} = $AllGroups{$GroupID};
        }
    }
    
    # Note: Assignment Group removed - all incidents use 'Support Group' queue
    
    # Auto-select logged-in user if they are in the assignment list
    my $SelectedAssignedTo = $Param{AssignedTo} || '';
    if ( $Param{Action} eq 'Create' && !$SelectedAssignedTo ) {
        if ( exists $AssignmentUserList{$Self->{UserID}} ) {
            $SelectedAssignedTo = $Self->{UserID};
            # Auto-set state to 'assigned' when auto-populating assignee
            if (!$Param{State}) {
                $Param{State} = 'assigned';
            }
        }
    }

    # Assigned To dropdown
    $Param{AssignedToStrg} = $LayoutObject->BuildSelection(
        Data         => \%AssignmentUserList,
        Name         => 'AssignedTo',
        SelectedID   => $SelectedAssignedTo,
        Class        => 'Modernize' . ($Param{AssignedToInvalid} ? ' ServerError' : ''),
        PossibleNone => 1,
        Disabled     => $ReadOnly,
    );
    
    # Build category dropdowns
    # Product categories - Always build at least empty dropdowns for required fields
    if ( $CategoryOptions{ProductCat1} && @{$CategoryOptions{ProductCat1}} ) {
        my %Cat1Data;
        for my $Cat (@{$CategoryOptions{ProductCat1}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat1Data{$name} = $name;
        }
        $Param{ProductCat1Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat1Data,
            Name         => 'ProductCat1',
            SelectedID   => $Param{ProductCat1} || '',
            Class        => 'Modernize Validate_Required' . ($Param{ProductCat1Invalid} ? ' ServerError' : ''),
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    } else {
        # Build empty dropdown for required field
        $Param{ProductCat1Strg} = $LayoutObject->BuildSelection(
            Data         => {},
            Name         => 'ProductCat1',
            SelectedID   => '',
            Class        => 'Modernize Validate_Required' . ($Param{ProductCat1Invalid} ? ' ServerError' : ''),
            PossibleNone => 1,
            Translation  => 0,
            Disabled     => $ReadOnly,
        );
    }
    
    if ( $CategoryOptions{ProductCat2} && @{$CategoryOptions{ProductCat2}} ) {
        my %Cat2Data;
        for my $Cat (@{$CategoryOptions{ProductCat2}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat2Data{$name} = $name;
        }
        $Param{ProductCat2Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat2Data,
            Name         => 'ProductCat2',
            SelectedID   => $Param{ProductCat2} || '',
            Class        => 'Modernize Validate_Required' . ($Param{ProductCat2Invalid} ? ' ServerError' : ''),
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    } else {
        # Build empty dropdown for required field
        $Param{ProductCat2Strg} = $LayoutObject->BuildSelection(
            Data         => {},
            Name         => 'ProductCat2',
            SelectedID   => '',
            Class        => 'Modernize Validate_Required' . ($Param{ProductCat2Invalid} ? ' ServerError' : ''),
            PossibleNone => 1,
            Disabled     => $ReadOnly,
            Translation  => 0,
        );
    }
    
    if ( $CategoryOptions{ProductCat3} ) {
        my %Cat3Data;
        for my $Cat (@{$CategoryOptions{ProductCat3}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat3Data{$name} = $name;
        }
        $Param{ProductCat3Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat3Data,
            Name         => 'ProductCat3',
            SelectedID   => $Param{ProductCat3} || '',
            Class        => 'Modernize',
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    }
    
    if ( $CategoryOptions{ProductCat4} ) {
        my %Cat4Data;
        for my $Cat (@{$CategoryOptions{ProductCat4}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat4Data{$name} = $name;
        }
        
        $Param{ProductCat4Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat4Data,
            Name         => 'ProductCat4',
            SelectedID => $Param{ProductCat4} || '',
            Class        => 'Modernize',
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    }
    
    # Operational categories - Always build at least empty dropdowns for required fields
    if ( $CategoryOptions{OperationalCat1} && @{$CategoryOptions{OperationalCat1}} ) {
        my %Cat1Data;
        for my $Cat (@{$CategoryOptions{OperationalCat1}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat1Data{$name} = $name;
        }
        $Param{OperationalCat1Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat1Data,
            Name         => 'OperationalCat1',
            SelectedID   => $Param{OperationalCat1} || '',
            Class        => 'Modernize Validate_Required' . ($Param{OperationalCat1Invalid} ? ' ServerError' : ''),
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    } else {
        # Build empty dropdown for required field
        $Param{OperationalCat1Strg} = $LayoutObject->BuildSelection(
            Data         => {},
            Name         => 'OperationalCat1',
            SelectedID   => '',
            Class        => 'Modernize Validate_Required' . ($Param{OperationalCat1Invalid} ? ' ServerError' : ''),
            PossibleNone => 1,
            Translation  => 0,
            Disabled     => $ReadOnly,
        );
    }
    
    if ( $CategoryOptions{OperationalCat2} && @{$CategoryOptions{OperationalCat2}} ) {
        my %Cat2Data;
        for my $Cat (@{$CategoryOptions{OperationalCat2}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat2Data{$name} = $name;
        }
        $Param{OperationalCat2Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat2Data,
            Name         => 'OperationalCat2',
            SelectedID   => $Param{OperationalCat2} || '',
            Class        => 'Modernize Validate_Required' . ($Param{OperationalCat2Invalid} ? ' ServerError' : ''),
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    } else {
        # Build empty dropdown for required field
        $Param{OperationalCat2Strg} = $LayoutObject->BuildSelection(
            Data         => {},
            Name         => 'OperationalCat2',
            SelectedID   => '',
            Class        => 'Modernize Validate_Required' . ($Param{OperationalCat2Invalid} ? ' ServerError' : ''),
            PossibleNone => 1,
            Translation  => 0,
            Disabled     => $ReadOnly,
        );
    }
    
    if ( $CategoryOptions{OperationalCat3} ) {
        my %Cat3Data;
        for my $Cat (@{$CategoryOptions{OperationalCat3}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat3Data{$name} = $name;
        }
        $Param{OperationalCat3Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat3Data,
            Name         => 'OperationalCat3',
            SelectedID => $Param{OperationalCat3} || '',
            Class        => 'Modernize',
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    }
    
    # Resolution categories
    if ( $CategoryOptions{ResolutionCat1} ) {
        my %Cat1Data;
        for my $Cat (@{$CategoryOptions{ResolutionCat1}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat1Data{$name} = $name;
        }
        $Param{ResolutionCat1Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat1Data,
            Name         => 'ResolutionCat1',
            SelectedID   => $Param{ResolutionCat1} || '',
            Class        => 'Modernize',
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    }
    
    if ( $CategoryOptions{ResolutionCat2} ) {
        my %Cat2Data;
        for my $Cat (@{$CategoryOptions{ResolutionCat2}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat2Data{$name} = $name;
        }
        $Param{ResolutionCat2Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat2Data,
            Name         => 'ResolutionCat2',
            SelectedID   => $Param{ResolutionCat2} || '',
            Class        => 'Modernize',
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    }
    
    if ( $CategoryOptions{ResolutionCat3} ) {
        my %Cat3Data;
        for my $Cat (@{$CategoryOptions{ResolutionCat3}}) {
            my $name = $Cat->{Name};
            $name =~ s/^\s+|\s+$//g;  # Trim whitespace
            $Cat3Data{$name} = $name;
        }
        $Param{ResolutionCat3Strg} = $LayoutObject->BuildSelection(
            Data         => \%Cat3Data,
            Name         => 'ResolutionCat3',
            SelectedID   => $Param{ResolutionCat3} || '',
            Class        => 'Modernize',
            PossibleNone => 1,
            Disabled     => $ReadOnly,
        );
    }
    
    
    # Create empty dropdowns for missing category levels
    for my $Field (qw(ProductCat1 ProductCat2 ProductCat3 ProductCat4 OperationalCat1 OperationalCat2 OperationalCat3 ResolutionCat1 ResolutionCat2 ResolutionCat3)) {
        if ( !$Param{$Field . 'Strg'} ) {
            # Only Product and Operational categories are required for creation, Resolution categories are only required when resolving
            my $RequiredClass = '';
            if ($Field =~ /^(Product|Operational)Cat[12]$/) {
                $RequiredClass = ' Validate_Required';
            }
            elsif ($Field =~ /^ResolutionCat[12]$/ && $Param{State} && $Param{State} eq 'resolved') {
                $RequiredClass = ' Validate_Required';
            }
            
            $Param{$Field . 'Strg'} = $LayoutObject->BuildSelection(
                Data         => {},
                Name         => $Field,
                Class        => 'Modernize' . $RequiredClass,
                PossibleNone => 1,
                Disabled     => $ReadOnly,
            );
        }
    }

    # Get history if updating
    my @WorkNotesHistory;
    my @IncidentHistory;
    my @CombinedHistory;
    
    if ( $Param{IncidentID} ) {
        @WorkNotesHistory = $IncidentObject->GetWorkNotesHistory(
            IncidentID => $Param{IncidentID},
        );
        
        @IncidentHistory = $IncidentObject->GetIncidentHistory(
            IncidentID => $Param{IncidentID},
            UserID     => $Self->{UserID},
        );
        
        # Combine and sort both histories chronologically
        my @AllHistoryEntries;
        
        # Add work notes with type identifier
        for my $WorkNote (@WorkNotesHistory) {
            push @AllHistoryEntries, {
                %{$WorkNote},
                HistoryType => 'WorkNote',
                SortDate => $WorkNote->{Created} || '',
            };
        }
        
        # Add incident updates with existing type
        for my $IncidentUpdate (@IncidentHistory) {
            push @AllHistoryEntries, {
                %{$IncidentUpdate},
                SortDate => $IncidentUpdate->{Created} || '',
            };
        }
        
        # Sort by date (newest first)
        @CombinedHistory = sort { 
            ($b->{SortDate} || '') cmp ($a->{SortDate} || '') 
        } @AllHistoryEntries;
    }

    # Add CSS block
    $LayoutObject->Block(
        Name => 'IncidentFormCSS',
    );

    # Check if Easy MSI Escalation integration is enabled
    my $EBondingEnabled = $ConfigObject->Get('EBondingIntegration::Enabled') ? 1 : 0;

    # Load MSI work notes if EBonding is enabled and incident exists
    my @MSIWorkNotes;
    if ( $EBondingEnabled && $Param{IncidentID} ) {
        my $EBondingObject = $Kernel::OM->Get('Kernel::System::EBonding');
        @MSIWorkNotes = $EBondingObject->GetMSIWorkNotes(
            TicketID => $Param{IncidentID},
        );
    }

    # Output
    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();

    # Show notifications
    if ( $Param{IncidentCreated} ) {
        $Output .= $LayoutObject->Notify(
            Priority => 'Success',
            Info     => Translatable('Incident created successfully!'),
        );
    }
    elsif ( $Param{IncidentUpdated} ) {
        $Output .= $LayoutObject->Notify(
            Priority => 'Success',
            Info     => Translatable('Incident updated successfully!'),
        );
    }

    # Render combined history blocks (chronologically sorted)
    if (@CombinedHistory) {
        for my $HistoryEntry (@CombinedHistory) {
            if ($HistoryEntry->{HistoryType} eq 'WorkNote') {
                # Render as work note
                $LayoutObject->Block(
                    Name => 'CombinedHistoryRow',
                    Data => {
                        %{$HistoryEntry},
                        NoteHTML => $HistoryEntry->{Note},  # Add as HTML field
                        IncludeInMSIText => $HistoryEntry->{IncludeInMSI} ? 'Yes' : 'No',
                        IsWorkNote => 1,
                    },
                );
            } else {
                # Render as incident update
                $LayoutObject->Block(
                    Name => 'CombinedHistoryRow',
                    Data => {
                        %{$HistoryEntry},
                        IsIncidentUpdate => 1,
                    },
                );
            }
        }
    }
    
    # Map system date fields for template
    my %SystemDateFields = (
        Opened    => $Param{Created} || '',
        OpenedBy  => '',
        Updated   => $Param{Changed} || '',
        UpdatedBy => '',
        Response  => $Param{ResponseTime} || '',
        Resolved  => $Param{ResolvedTime} || '',
        AssignedDate => '',
        ResolutionDate => '',
        ClosedDate => '',
        FinalStatus => '',
    );
    
    # OpenedBy and UpdatedBy are already formatted strings from the dynamic fields
    if ($Param{CreatedBy}) {
        $SystemDateFields{OpenedBy} = $Param{CreatedBy};
    }
    
    if ($Param{ChangedBy}) {
        $SystemDateFields{UpdatedBy} = $Param{ChangedBy};
    }
    
    # Get ticket history to retrieve assignment, resolution, and closed dates
    if ($Param{IncidentID}) {
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
        
        # Get ticket history
        my @History = $TicketObject->HistoryGet(
            TicketID => $Param{IncidentID},
            UserID   => $Self->{UserID},
        );
        
        # Process history to find relevant dates
        for my $HistoryEntry (@History) {
            # Safety check for HistoryTypeID
            next if !defined $HistoryEntry->{HistoryTypeID};
            
            # Check for initial ticket creation with owner (NewTicket = type 1)
            if ($HistoryEntry->{HistoryTypeID} == 1 && !$SystemDateFields{AssignedDate}) {
                # Check if ticket was created with an owner other than root (ID 1) or unassigned (ID 99)
                if (defined $HistoryEntry->{OwnerID} && $HistoryEntry->{OwnerID} && $HistoryEntry->{OwnerID} != 1 && $HistoryEntry->{OwnerID} != 99) {
                    $SystemDateFields{AssignedDate} = $HistoryEntry->{CreateTime} || '';
                }
            }
            # Check for owner/assignment changes (OwnerUpdate = type 23)
            elsif ($HistoryEntry->{HistoryTypeID} == 23 && !$SystemDateFields{AssignedDate}) {
                # Skip if assigned to root user (ID 1) or unassigned (ID 99)
                if (defined $HistoryEntry->{OwnerID} && $HistoryEntry->{OwnerID} && $HistoryEntry->{OwnerID} != 1 && $HistoryEntry->{OwnerID} != 99) {
                    $SystemDateFields{AssignedDate} = $HistoryEntry->{CreateTime} || '';
                }
            }
            
            # Check for state changes (StateUpdate = type 27)
            elsif ($HistoryEntry->{HistoryTypeID} == 27) {
                my $StateName = $HistoryEntry->{Name} || '';
                
                # Parse state name from history entry format (e.g., "%%new%%assigned%%")
                # The format is typically: %%OldState%%NewState%%
                if ($StateName =~ /%%([^%]+)%%([^%]+)%%/) {
                    my $NewState = $2 || '';
                    
                    # Check for resolution state
                    if ($NewState =~ /resolved/i && !$SystemDateFields{ResolutionDate}) {
                        $SystemDateFields{ResolutionDate} = $HistoryEntry->{CreateTime} || '';
                    }
                    
                    # Check for closed state (including "closed successful")
                    elsif ($NewState =~ /closed/i && !$SystemDateFields{ClosedDate}) {
                        $SystemDateFields{ClosedDate} = $HistoryEntry->{CreateTime} || '';
                        $SystemDateFields{FinalStatus} = 'Closed';
                    }
                    
                    # Check for cancelled state
                    elsif ($NewState =~ /cancelled/i && !$SystemDateFields{ClosedDate}) {
                        $SystemDateFields{ClosedDate} = $HistoryEntry->{CreateTime} || '';
                        $SystemDateFields{FinalStatus} = 'Cancelled';
                    }
                }
                # Fallback: check the whole string if pattern doesn't match
                else {
                    # Check for resolution state
                    if ($StateName =~ /resolved/i && !$SystemDateFields{ResolutionDate}) {
                        $SystemDateFields{ResolutionDate} = $HistoryEntry->{CreateTime} || '';
                    }
                    
                    # Check for closed state
                    elsif ($StateName =~ /closed/i && !$SystemDateFields{ClosedDate}) {
                        $SystemDateFields{ClosedDate} = $HistoryEntry->{CreateTime} || '';
                        $SystemDateFields{FinalStatus} = 'Closed';
                    }
                    
                    # Check for cancelled state
                    elsif ($StateName =~ /cancelled/i && !$SystemDateFields{ClosedDate}) {
                        $SystemDateFields{ClosedDate} = $HistoryEntry->{CreateTime} || '';
                        $SystemDateFields{FinalStatus} = 'Cancelled';
                    }
                }
            }
        }
        
        # If incident is currently closed/cancelled but no history entry, use current state
        if (!$SystemDateFields{FinalStatus} && $Param{State}) {
            if ($Param{State} =~ /closed/i) {
                $SystemDateFields{FinalStatus} = 'Closed';
            }
            elsif ($Param{State} =~ /cancelled/i) {
                $SystemDateFields{FinalStatus} = 'Cancelled';
            }
        }
    }

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentIncidentForm',
        Data         => {
            %Param,
            %SystemDateFields,
            PriorityList        => \%PriorityList,
            StateList           => \%AllowedStateList,
            UserList            => \%AssignmentUserList,
            CategoryOptions     => \%CategoryOptions,
            CombinedHistory     => \@CombinedHistory,
            Action              => $Param{Action},
            ReadOnly            => $ReadOnly,
            EBondingEnabled     => $EBondingEnabled,
            MSIWorkNotes        => \@MSIWorkNotes,
        },
    );

    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _LoadCategories {
    my ( $Self, %Param ) = @_;

    my $LayoutObject   = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $CategoryObject = $Kernel::OM->Get('Kernel::System::IncidentCategory');
    my $ParamObject    = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LogObject      = $Kernel::OM->Get('Kernel::System::Log');

    # Get parameters from AJAX request
    my $Level    = $ParamObject->GetParam( Param => 'Level' ) || $ParamObject->GetParam( Param => 'Tier' ) || 1;
    my $ParentID = $ParamObject->GetParam( Param => 'ParentID' ) || 0;
    my $Type     = $ParamObject->GetParam( Param => 'Type' ) || 'product';  # product, operational, or resolution
    my $Tier1    = $ParamObject->GetParam( Param => 'Tier1' ) || '';
    my $Tier2    = $ParamObject->GetParam( Param => 'Tier2' ) || '';
    my $Tier3    = $ParamObject->GetParam( Param => 'Tier3' ) || '';
    
    # Get categories based on type and level
    my $Categories = [];
    
    if ($Type eq 'product' || lc($Type) eq 'product') {
        my %Params = ( Tier => $Level );
        
        # Use new tier-based parameters if available, otherwise fall back to ParentID
        if ($Tier1) {
            $Params{Tier1} = $Tier1;
        } elsif ($Level == 2 && $ParentID) {
            $Params{Tier1} = $ParentID;
        }
        
        if ($Tier2) {
            $Params{Tier2} = $Tier2;
        } elsif ($Level == 3 && $ParentID) {
            $Params{Tier2} = $ParentID;
        }
        
        if ($Tier3) {
            $Params{Tier3} = $Tier3;
        } elsif ($Level == 4 && $ParentID) {
            $Params{Tier3} = $ParentID;
        }

        $Categories = $CategoryObject->GetProductCategories(%Params);

        # Filter ProductCat1 based on licensed technology (only for Tier 1)
        if ($Level == 1) {
            my $LicenseObject = $Kernel::OM->Get('Kernel::System::AdminAddLicense');
            my $LicensedTech = $LicenseObject->GetLicensedTechnology();

            # Map license technology to tier1 category values
            my %TechMapping = (
                'WAVE On Prem' => 'WAVE',
                'ASTRO'        => 'ASTRO Infrastructure',
                'DIMETRA'      => 'DIMETRA',
            );

            # LSMP is always shown regardless of license
            my $LSMPName = 'Local Service Management Platform (LSMP)';

            # Filter categories based on license
            if ($LicensedTech && exists $TechMapping{$LicensedTech}) {
                my $AllowedTier1 = $TechMapping{$LicensedTech};
                $Categories = [
                    grep { $_->{Name} eq $AllowedTier1 || $_->{Name} eq $LSMPName }
                    @{$Categories}
                ];
            }
        }
    }
    elsif ($Type eq 'operational') {
        my %Params = ( Tier => $Level );
        
        # Use new tier-based parameters if available, otherwise fall back to ParentID
        if ($Tier1) {
            $Params{Tier1} = $Tier1;
        } elsif ($Level == 2 && $ParentID) {
            $Params{Tier1} = $ParentID;
        }
        
        if ($Tier2) {
            $Params{Tier2} = $Tier2;
        } elsif ($Level == 3 && $ParentID) {
            $Params{Tier2} = $ParentID;
        }
        
        $Categories = $CategoryObject->GetOperationalCategories(%Params);
    }
    elsif ($Type eq 'resolution') {
        my %Params = ( Tier => $Level );
        
        # Use new tier-based parameters if available, otherwise fall back to ParentID
        if ($Tier1) {
            $Params{Tier1} = $Tier1;
        } elsif ($Level == 2 && $ParentID) {
            $Params{Tier1} = $ParentID;
        }
        
        if ($Tier2) {
            $Params{Tier2} = $Tier2;
        } elsif ($Level == 3 && $ParentID) {
            $Params{Tier2} = $ParentID;
        }
        
        $Categories = $CategoryObject->GetResolutionCategories(%Params);
    }

    # Format response
    my @FormattedCategories;
    for my $Cat (@{$Categories}) {
        push @FormattedCategories, {
            ID   => $Cat->{Name} || $Cat->{Tier1} || $Cat->{Tier2} || $Cat->{Tier3},
            Name => $Cat->{Name} || '',
        };
    }

    # Return JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json',
        Content     => $LayoutObject->JSONEncode(
            Data => {
                Categories => \@FormattedCategories,
                Success    => 1,
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

sub _ValidateStateTransition {
    my ( $Self, %Param ) = @_;

    my $LayoutObject   = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $IncidentObject = $Kernel::OM->Get('Kernel::System::Incident');

    my $IsValid = $IncidentObject->ValidateStateTransition(
        CurrentState => $Param{CurrentState},
        NewState     => $Param{NewState},
    );

    # Return JSON
    return $LayoutObject->Attachment(
        ContentType => 'application/json',
        Content     => $LayoutObject->JSONEncode(
            Data => {
                Valid => $IsValid ? 1 : 0,
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

sub _AddWorkNote {
    my ( $Self, %Param ) = @_;

    my $LayoutObject   = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $IncidentObject = $Kernel::OM->Get('Kernel::System::Incident');
    my $ParamObject    = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $UserObject     = $Kernel::OM->Get('Kernel::System::User');
    
    # Get all parameters (work note + all incident fields)
    my %GetParam;
    for my $Param (
        qw(TicketID IncidentID WorkNoteText IncludeInMSI
        Priority State CI AssignedTo ShortDescription Description
        ProductCat1 ProductCat2 ProductCat3 ProductCat4
        OperationalCat1 OperationalCat2 OperationalCat3
        ResolutionCat1 ResolutionCat2 ResolutionCat3 ResolutionNotes)
    ) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }
    
    # Validate input - need either TicketID or IncidentID, and WorkNoteText
    if ( (!$GetParam{TicketID} && !$GetParam{IncidentID}) || !$GetParam{WorkNoteText} ) {
        return $LayoutObject->Attachment(
            ContentType => 'application/json',
            Content     => $LayoutObject->JSONEncode(
                Data => {
                    Success => 0,
                    Message => 'Missing required parameters: ' . (!$GetParam{TicketID} && !$GetParam{IncidentID} ? 'TicketID/IncidentID ' : '') . (!$GetParam{WorkNoteText} ? 'WorkNoteText' : ''),
                },
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }
    
    # Get user info
    my %User = $UserObject->GetUserData(
        UserID => $Self->{UserID},
    );
    
    # Use IncidentID if available, otherwise try to convert TicketID
    my $UseIncidentID = $GetParam{IncidentID};
    if (!$UseIncidentID && $GetParam{TicketID}) {
        # Try to find IncidentID from TicketID if needed
        # For now, assume TicketID = IncidentID in this context
        $UseIncidentID = $GetParam{TicketID};
    }
    
    # First update the incident with all form fields
    my $UpdateSuccess = 1;
    if ($UseIncidentID) {
        $UpdateSuccess = $IncidentObject->IncidentUpdate(
            IncidentID       => $UseIncidentID,
            Priority         => $GetParam{Priority},
            State            => $GetParam{State},
            CI               => $GetParam{CI},
            AssignedTo       => $GetParam{AssignedTo},
            ShortDescription => $GetParam{ShortDescription},
            Description      => $GetParam{Description},
            ProductCat1      => $GetParam{ProductCat1},
            ProductCat2      => $GetParam{ProductCat2},
            ProductCat3      => $GetParam{ProductCat3},
            ProductCat4      => $GetParam{ProductCat4},
            OperationalCat1  => $GetParam{OperationalCat1},
            OperationalCat2  => $GetParam{OperationalCat2},
            OperationalCat3  => $GetParam{OperationalCat3},
            ResolutionCat1   => $GetParam{ResolutionCat1},
            ResolutionCat2   => $GetParam{ResolutionCat2},
            ResolutionCat3   => $GetParam{ResolutionCat3},
            ResolutionNotes  => $GetParam{ResolutionNotes},
            UserID           => $Self->{UserID},
        );
    }
    
    # Then add the work note
    my $WorkNoteSuccess = 0;
    if ($UpdateSuccess) {
        $WorkNoteSuccess = $IncidentObject->AddWorkNote(
            IncidentID    => $UseIncidentID,
            Note          => $GetParam{WorkNoteText},
            IncludeInMSI  => 1,  # Always include in MSI
            UserID        => $Self->{UserID},
        );
    }
    
    return $LayoutObject->Attachment(
        ContentType => 'application/json',
        Content     => $LayoutObject->JSONEncode(
            Data => {
                Success => ($UpdateSuccess && $WorkNoteSuccess) ? 1 : 0,
                Message => ($UpdateSuccess && $WorkNoteSuccess) ? 'Work note and changes saved successfully' : 'Failed to save changes',
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

sub _AddResolutionNote {
    my ( $Self, %Param ) = @_;

    my $LayoutObject   = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $IncidentObject = $Kernel::OM->Get('Kernel::System::Incident');
    my $ParamObject    = $Kernel::OM->Get('Kernel::System::Web::Request');
    
    # Get parameters
    my $TicketID        = $ParamObject->GetParam( Param => 'TicketID' ) || '';
    my $IncidentID      = $ParamObject->GetParam( Param => 'IncidentID' ) || '';
    my $ResolutionCat1  = $ParamObject->GetParam( Param => 'ResolutionCat1' ) || '';
    my $ResolutionCat2  = $ParamObject->GetParam( Param => 'ResolutionCat2' ) || '';
    my $ResolutionCat3  = $ParamObject->GetParam( Param => 'ResolutionCat3' ) || '';
    my $ResolutionNotes = $ParamObject->GetParam( Param => 'ResolutionNotes' ) || '';
    
    # Validate required parameters
    if ( !$ResolutionNotes ) {
        return $LayoutObject->Attachment(
            ContentType => 'application/json',
            Content     => $LayoutObject->JSONEncode(
                Data => {
                    Success => 0,
                    Message => 'Resolution notes are required',
                },
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }
    
    # Determine incident ID to use
    my $UseIncidentID = $IncidentID;
    if ( !$UseIncidentID && $TicketID ) {
        # For now, assume TicketID = IncidentID in this context
        $UseIncidentID = $TicketID;
    }
    
    my $Success = $IncidentObject->AddResolutionNote(
        IncidentID       => $UseIncidentID,
        ResolutionCat1   => $ResolutionCat1,
        ResolutionCat2   => $ResolutionCat2,
        ResolutionCat3   => $ResolutionCat3,
        ResolutionNotes  => $ResolutionNotes,
        UserID           => $Self->{UserID},
    );
    
    return $LayoutObject->Attachment(
        ContentType => 'application/json',
        Content     => $LayoutObject->JSONEncode(
            Data => {
                Success => $Success ? 1 : 0,
                Message => $Success ? 'Resolution note added successfully' : 'Failed to add resolution note',
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

sub _LoadAssignedUsers {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
    
    # Get parameters
    my $GroupID = $ParamObject->GetParam( Param => 'GroupID' ) || '';
    
    # Validate input
    if ( !$GroupID ) {
        return $LayoutObject->Attachment(
            ContentType => 'application/json',
            Content     => $LayoutObject->JSONEncode(
                Data => {
                    Success => 0,
                    Message => 'Missing GroupID parameter',
                    Users   => [],
                },
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }
    
    # Get users in the group
    my @Users;
    my %GroupUsers;
    
    # Try to get users in the group
    eval {
        %GroupUsers = $GroupObject->PermissionGroupUserGet(
            GroupID => $GroupID,
            Type    => 'rw',
        );
    };
    
    # If that fails, try alternative method
    if ($@ || !%GroupUsers) {
        eval {
            %GroupUsers = $GroupObject->PermissionGroupUserGet(
                GroupID => $GroupID,
                Type    => 'ro',
            );
        };
    }
    
    # If still no users, try getting all users in group regardless of permission type
    if ($@ || !%GroupUsers) {
        eval {
            my @UserIDs = $GroupObject->GroupMemberList(
                GroupID => $GroupID,
                Type    => 'rw',
                Result  => 'ID',
            );
            %GroupUsers = map { $_ => 1 } @UserIDs;
        };
    }
    
    # Build user list
    for my $UserID ( sort keys %GroupUsers ) {
        my %User = $UserObject->GetUserData(
            UserID => $UserID,
        );
        
        # Only include valid users
        if ( %User && $User{ValidID} == 1 ) {
            push @Users, {
                ID   => $UserID,
                Name => "$User{UserFirstname} $User{UserLastname} ($User{UserLogin})",
            };
        }
    }
    
    # Sort users by name
    @Users = sort { $a->{Name} cmp $b->{Name} } @Users;
    
    # Return results - even if no users found, return success with empty array
    return $LayoutObject->Attachment(
        ContentType => 'application/json',
        Content     => $LayoutObject->JSONEncode(
            Data => {
                Success => 1,
                Users   => \@Users,
                Message => scalar(@Users) ? sprintf("Found %d users", scalar(@Users)) : "No users found in group $GroupID",
                Debug   => {
                    GroupID => $GroupID,
                    UserCount => scalar(@Users),
                },
            },
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

sub _SubmitToServiceNow {
    my ( $Self, %Param ) = @_;

    my $LayoutObject   = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject    = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $IncidentObject = $Kernel::OM->Get('Kernel::System::Incident');
    my $JSONObject     = $Kernel::OM->Get('Kernel::System::JSON');
    my $LogObject      = $Kernel::OM->Get('Kernel::System::Log');

    # Challenge token check for write action
    $LayoutObject->ChallengeTokenCheck();

    # Get incident ID
    my $IncidentID = $ParamObject->GetParam( Param => 'IncidentID' ) || '';

    # Validate incident ID
    if ( !$IncidentID ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => '_SubmitToServiceNow: Missing IncidentID parameter',
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    Message => 'Missing incident ID',
                }
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }

    # Get incident details
    my %Incident = $IncidentObject->IncidentGet(
        IncidentID => $IncidentID,
        UserID     => $Self->{UserID},
    );

    if ( !%Incident ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_SubmitToServiceNow: Incident $IncidentID not found",
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    Message => 'Incident not found',
                }
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }

    # Check if already submitted
    if ( $Incident{MSITicketNumber} ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "_SubmitToServiceNow: Incident $IncidentID already submitted. MSI Ticket: $Incident{MSITicketNumber}",
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    Message => "This incident has already been submitted to MSI ServiceNow. Ticket number: $Incident{MSITicketNumber}",
                }
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }

    # Submit to ServiceNow via EBonding module
    my $EBondingObject = $Kernel::OM->Get('Kernel::System::EBonding');
    my ( $Success, $MSITicketNumber, $ErrorMessage ) = $EBondingObject->SubmitToServiceNow(
        IncidentID => $IncidentID,
        UserID     => $Self->{UserID},
    );

    # Build response
    my $ResponseMessage;
    if ($Success) {
        $ResponseMessage = "Successfully submitted to MSI ServiceNow. Ticket number: $MSITicketNumber";
        $LogObject->Log(
            Priority => 'info',
            Message  => "_SubmitToServiceNow: Successfully submitted incident $IncidentID. MSI Ticket: $MSITicketNumber",
        );
    }
    else {
        $ResponseMessage = "Failed to submit to MSI ServiceNow: $ErrorMessage";
        $LogObject->Log(
            Priority => 'error',
            Message  => "_SubmitToServiceNow: Failed to submit incident $IncidentID. Error: $ErrorMessage",
        );
    }

    # Return JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json',
        Content     => $JSONObject->Encode(
            Data => {
                Success         => $Success,
                MSITicketNumber => $MSITicketNumber || '',
                Message         => $ResponseMessage,
            }
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

sub _PullFromServiceNow {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    # Get incident ID
    my $IncidentID = $ParamObject->GetParam( Param => 'IncidentID' ) || '';

    # Validate incident ID
    if ( !$IncidentID ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => '_PullFromServiceNow: Missing IncidentID parameter',
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json',
            Content     => $JSONObject->Encode(
                Data => {
                    Success => 0,
                    Message => 'Missing incident ID',
                }
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }

    # Pull from ServiceNow via EBonding module
    my $EBondingObject = $Kernel::OM->Get('Kernel::System::EBonding');
    my ( $Success, $UpdateSummary, $ErrorMessage ) = $EBondingObject->PullFromServiceNow(
        IncidentID => $IncidentID,
        UserID     => $Self->{UserID},
    );

    # Build response
    my $ResponseMessage;
    if ($Success) {
        $ResponseMessage = "Successfully synced with MSI ServiceNow. $UpdateSummary";
        $LogObject->Log(
            Priority => 'info',
            Message  => "_PullFromServiceNow: Successfully pulled updates for incident $IncidentID. $UpdateSummary",
        );

        # Set 10-minute cooldown in bulk_update_cooldown table (same as escalation view)
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        my $CooldownSet = $DBObject->Do(
            SQL => "INSERT INTO bulk_update_cooldown (ticket_id, cooldown_until, create_time, update_time)
                    VALUES (?, NOW() + INTERVAL '10 minutes', NOW(), NOW())
                    ON CONFLICT (ticket_id)
                    DO UPDATE SET
                        cooldown_until = NOW() + INTERVAL '10 minutes',
                        update_time = NOW()",
            Bind => [ \$IncidentID ],
        );

        if ( !$CooldownSet ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "_PullFromServiceNow: Failed to set cooldown for incident $IncidentID",
            );
        }
    }
    else {
        $ResponseMessage = "Failed to sync with MSI ServiceNow: $ErrorMessage";
        $LogObject->Log(
            Priority => 'error',
            Message  => "_PullFromServiceNow: Failed to pull updates for incident $IncidentID. Error: $ErrorMessage",
        );
    }

    # Return JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json',
        Content     => $JSONObject->Encode(
            Data => {
                Success       => $Success,
                UpdateSummary => $UpdateSummary || '',
                Message       => $ResponseMessage,
            }
        ),
        Type    => 'inline',
        NoCache => 1,
    );
}

1;
