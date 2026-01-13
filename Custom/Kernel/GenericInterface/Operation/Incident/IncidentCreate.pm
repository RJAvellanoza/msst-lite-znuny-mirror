# --
# Copyright (C) 2024 Radiant Digital, radiant.digital
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::GenericInterface::Operation::Incident::IncidentCreate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsStringWithData IsHashRefWithData);

use parent qw(
    Kernel::GenericInterface::Operation::Common
);

our $ObjectManagerDisabled = 1;

# Device type mapping configuration
# Dynamic path resolution - find the Znuny installation root
our $DeviceTypeMappingFile;
BEGIN {
    # Get the path to this module and derive the Znuny root from it
    my $module_path = __FILE__;
    $module_path =~ s{/Kernel/GenericInterface/Operation/Incident/IncidentCreate\.pm$}{};
    $DeviceTypeMappingFile = "$module_path/var/categories/[LSMP] Prod Cat Mapping by Device Type - Master Mapping.csv";
}
our %DeviceTypeMapping;
our $MappingFileModTime = 0;

=head1 NAME

Kernel::GenericInterface::Operation::Incident::IncidentCreate - GenericInterface Incident Create Operation backend

=head1 DESCRIPTION

=head2 new()

usually, you want to create an instance of this
by using Kernel::GenericInterface::Operation->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw(DebuggerObject WebserviceID)) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    return $Self;
}

=head2 Run()

perform IncidentCreate Operation. This will return the created IncidentID and TicketID.

The operation supports automatic product category mapping based on CIDeviceType. When CIDeviceType 
is provided, the system will automatically populate ProductCat1-4 fields using a CSV mapping file.
User-provided ProductCat values will always take precedence over auto-populated values.

    my $Result = $OperationObject->Run(
        Data => {
            SessionID => '1234567890123456',  # Optional, if not provided UserLogin and Password must be provided
            UserLogin => 'some agent',       # Optional, if not provided SessionID must be provided  
            Password  => 'some password',    # Optional, if not provided SessionID must be provided

            Incident => {
                # Core Required Fields
                Source           => 'Event Monitoring',                       # Required - Must be 'Event Monitoring'
                Priority         => 'P1-Critical',                 # Required
                ShortDescription => 'Brief description',           # Required
                ProductCat1      => 'Product Category 1',         # Required (can be auto-populated from CIDeviceType)
                ProductCat2      => 'Product Category 2',         # Optional (can be auto-populated from CIDeviceType)
                OperationalCat1  => 'Operational Category 1',     # Required
                OperationalCat2  => 'Operational Category 2',     # Required

                # Core Optional Fields
                State            => 'New',                         # Optional, defaults to 'New'
                CI               => 'Configuration Item Name',     # Optional
                AssignedTo       => 'agent_login',                 # Optional
                AssignmentGroup  => 'Support Group',              # Optional
                Description      => 'Detailed description',       # Optional

                # Category Fields
                ProductCat3      => 'Product Category 3',         # Optional (can be auto-populated from CIDeviceType)
                ProductCat4      => 'Product Category 4',         # Optional (can be auto-populated from CIDeviceType)
                OperationalCat3  => 'Operational Category 3',     # Optional
                ResolutionCat1   => 'Resolution Category 1',      # Optional
                ResolutionCat2   => 'Resolution Category 2',      # Optional
                ResolutionCat3   => 'Resolution Category 3',      # Optional
                ResolutionCode   => 'Solved',                     # Optional
                ResolutionNotes  => 'Resolution notes',           # Optional
                WorkNotes        => 'Work notes',                 # Optional

                # Timestamp Fields
                Opened           => '2024-01-01 12:00:00',        # Optional
                OpenedBy         => 'system',                     # Optional
                Updated          => '2024-01-01 12:00:00',        # Optional
                UpdatedBy        => 'system',                     # Optional
                Response         => '2024-01-01 12:00:00',        # Optional
                Resolved         => '2024-01-01 12:00:00',        # Optional

                # Event Fields
                AlarmID          => 'ALM-001',                    # Optional
                EventID          => 'EVT-001',                    # Optional
                EventSite        => 'Site A',                     # Optional
                SourceDevice     => 'Device Name',               # Optional
                EventMessage     => 'Event description',         # Optional
                EventBeginTime   => '2024-01-01 12:00:00',       # Optional
                EventDetectTime  => '2024-01-01 12:00:00',       # Optional
                CIDeviceType     => 'Router',                     # Optional - Auto-populates ProductCat1-4 from CSV mapping

                # MSI Integration Fields
                MSITicketNumber           => 'MSI-001',          # Optional
                Customer                  => 'Customer Name',    # Optional
                MSITicketSite            => 'MSI Site',          # Optional
                MSITicketState           => 'Open',              # Optional
                MSITicketStateReason     => 'Initial State',     # Optional
                MSITicketPriority        => 'High',              # Optional
                MSITicketAssignee        => 'assignee',          # Optional
                MSITicketShortDescription => 'MSI Short Desc',   # Optional
                MSITicketResolutionNote  => 'MSI Resolution',    # Optional
                MSITicketCreatedTime     => '2024-01-01 12:00:00', # Optional
                MSITicketLastUpdateTime  => '2024-01-01 12:00:00', # Optional
                MSITicketEbondLastUpdateTime => '2024-01-01 12:00:00', # Optional
                MSITicketResolvedTime    => '2024-01-01 12:00:00', # Optional
                MSIEbondAPIResponse      => 'API Response',       # Optional
                MSITicketComment         => 'MSI Comment',        # Optional
            },
        },
    );

    # Example with CIDeviceType auto-mapping:
    my $Result = $OperationObject->Run(
        Data => {
            Incident => {
                Source           => 'Event Monitoring',
                Priority         => 'P1-Critical',
                ShortDescription => 'Device failure detected',
                CIDeviceType     => 'EBTS',                    # Will auto-populate ProductCat1-4
                OperationalCat1  => 'Network Issues',
                OperationalCat2  => 'Device Down',
                # ProductCat1-4 will be automatically filled from CSV mapping:
                # ProductCat1 => 'DIMETRA'
                # ProductCat2 => 'DIMETRA IP X-Core'  
                # ProductCat3 => 'RF Subsystem'
                # ProductCat4 => 'EBTS'
            },
        },
    );

    $Result = {
        Success => 1,                       # 0 or 1
        ErrorMessage => '',                 # In case of an error
        Data => {
            IncidentID => 123,
            TicketID   => 456,
            Error => {
                ErrorCode    => 'IncidentCreate.InvalidParameter',
                ErrorMessage => 'Incident parameter is missing!',
            },
        },
    };

=cut

=head2 _LoadDeviceTypeMapping()

Load device type to product category mapping from CSV file.
Uses caching to avoid re-parsing the file on every request.

=cut

sub _LoadDeviceTypeMapping {
    my ($Self) = @_;

    # Check if mapping file exists
    if (!-f $DeviceTypeMappingFile) {
        $Self->{DebuggerObject}->Error(
            Summary => "Device type mapping file not found: $DeviceTypeMappingFile"
        );
        return 0;
    }

    # Get file modification time
    my $currentModTime = (stat($DeviceTypeMappingFile))[9];
    
    # Return cached data if file hasn't changed
    if (%DeviceTypeMapping && $currentModTime == $MappingFileModTime) {
        return 1;
    }

    # Clear existing mapping and reload
    %DeviceTypeMapping = ();
    
    # Open and parse CSV file
    my $fh;
    if (!open($fh, '<', $DeviceTypeMappingFile)) {
        $Self->{DebuggerObject}->Error(
            Summary => "Cannot open device type mapping file: $DeviceTypeMappingFile - $!"
        );
        return 0;
    }

    my $lineNum = 0;
    my $currentSection = '';
    
    while (my $line = <$fh>) {
        $lineNum++;
        chomp $line;
        
        # Skip empty lines
        next if $line =~ /^\s*$/;
        
        # Split CSV line (handle quoted fields)
        my @fields;
        eval {
            @fields = split /,(?=(?:[^"]*"[^"]*")*[^"]*$)/, $line;
            
            # Clean up fields (remove quotes and trim whitespace)
            @fields = map { 
                s/^\s+|\s+$//g;  # trim whitespace
                s/^"(.*)"$/$1/;  # remove surrounding quotes
                $_ 
            } @fields;
        };
        if ($@) {
            $Self->{DebuggerObject}->Notice(
                Summary => "Skipped malformed CSV line $lineNum: $line"
            );
            next;
        }
        
        # Skip if not enough fields
        next if @fields < 5;
        
        # Identify section headers
        if ($fields[0] =~ /^Unique\s+(\w+)\s+.*Device Type$/i) {
            $currentSection = lc($1);  # dimetra, astro, wave
            next;
        }
        
        # Skip header rows
        next if $fields[0] =~ /^Unique.*Device Type$/i;
        next if $fields[1] =~ /^Prod Cat - T1$/i;
        
        # Store mapping: device_type => [[ProductCat1, ...], [ProductCat1, ...]]
        my $deviceType = $fields[0];
        my @categories = ($fields[1], $fields[2], $fields[3], $fields[4]);
        
        # Only store if device type is not empty
        if ($deviceType && $deviceType !~ /^\s*$/) {
            push @{ $DeviceTypeMapping{$deviceType} }, \@categories;
            
            # Also store with section prefix for disambiguation if needed
            if ($currentSection) {
                my $prefixedDeviceType = "${currentSection}_${deviceType}";
                push @{ $DeviceTypeMapping{$prefixedDeviceType} }, \@categories;
            }
        }
    }
    
    close($fh);
    
    # Update file modification time
    $MappingFileModTime = $currentModTime;
    
    my $mappingCount = keys %DeviceTypeMapping;
    $Self->{DebuggerObject}->Notice(
        Summary => "Loaded mappings for $mappingCount unique device types from $DeviceTypeMappingFile"
    );
    
    return 1;
}

sub Run {
    my ( $Self, %Param ) = @_;


    # check needed stuff
    if ( !IsHashRefWithData( $Param{Data} ) ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentCreate.MissingParameter',
            ErrorMessage => "IncidentCreate: The request is empty!",
        );
    }

    # Check if data is directly in Param{Data} instead of Param{Data}->{Incident}
    my %Incident;
    if ( IsHashRefWithData( $Param{Data}->{Incident} ) ) {
        %Incident = %{ $Param{Data}->{Incident} };
    }
    elsif ( $Param{Data}->{Source} && $Param{Data}->{Priority} ) {
        # Data might be directly in the root
        %Incident = %{ $Param{Data} };
    }
    else {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentCreate.MissingParameter',
            ErrorMessage => "IncidentCreate: Incident parameter is missing!",
        );
    }

    # check Incident mandatory fields (ProductCat1/2 are validated later after auto-population from CIDeviceType)
    for my $Needed (qw(Source Priority ShortDescription OperationalCat1 OperationalCat2 CIDeviceType)) {
        if ( !IsStringWithData( $Incident{$Needed} ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'IncidentCreate.MissingParameter',
                ErrorMessage => "IncidentCreate: Incident->$Needed parameter is missing!",
            );
        }
    }

    # Validate Source - only accept "Event Monitoring"
    if ( $Incident{Source} ne 'Event Monitoring' ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentCreate.InvalidSource',
            ErrorMessage => "IncidentCreate: Source must be 'Event Monitoring' (received: '$Incident{Source}')!",
        );
    }

    # check authentication
    my ($UserID, $UserType) = $Self->Auth(
        Data => $Param{Data},
    );
    
    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentCreate.AuthFail',
            ErrorMessage => "IncidentCreate: Authorization failing!",
        );
    }

    # Auto-populate Product Categories from CIDeviceType if provided
    $Self->{DebuggerObject}->Notice(
        Summary => "CIDeviceType provided: " . ($Incident{CIDeviceType} || 'NONE')
    );
    
    if ($Incident{CIDeviceType} && IsStringWithData($Incident{CIDeviceType})) {
        # Load device type mapping (graceful failure - continue even if mapping fails)
        eval {
            if ($Self->_LoadDeviceTypeMapping()) {
                my $deviceType = $Incident{CIDeviceType};
                my $all_mappings = $DeviceTypeMapping{$deviceType};

                # Try with different section prefixes if direct lookup fails
                if (!$all_mappings) {
                    for my $prefix (qw(dimetra astro wave)) {
                        my $prefixedKey = "${prefix}_${deviceType}";
                        if ($DeviceTypeMapping{$prefixedKey}) {
                            $all_mappings = $DeviceTypeMapping{$prefixedKey};
                            last;
                        }
                    }
                }

                if ($all_mappings && ref($all_mappings) eq 'ARRAY' && @$all_mappings) {
                    my $selected_categories;

                    if (@$all_mappings > 1 && !IsStringWithData($Incident{ProductCat1})) {
                        return $Self->ReturnError(
                            ErrorCode    => 'IncidentCreate.AmbiguousCIDeviceType',
                            ErrorMessage => "CIDeviceType '$deviceType' has multiple possible product category mappings. Please specify ProductCat1 to disambiguate.",
                        );
                    }
                    elsif (@$all_mappings > 1 && IsStringWithData($Incident{ProductCat1})) {
                        # Find the mapping that matches the provided ProductCat1
                        for my $mapping (@$all_mappings) {
                            if ($mapping->[0] eq $Incident{ProductCat1}) {
                                $selected_categories = $mapping;
                                last;
                            }
                        }
                    }
                    else {
                        # Only one mapping found, so use it
                        $selected_categories = $all_mappings->[0];
                    }

                    if ($selected_categories) {
                        # Only set ProductCat fields if they're not already provided by user
                        if (!IsStringWithData($Incident{ProductCat1}) && $selected_categories->[0]) {
                            $Incident{ProductCat1} = $selected_categories->[0];
                        }
                        if (!IsStringWithData($Incident{ProductCat2}) && $selected_categories->[1]) {
                            $Incident{ProductCat2} = $selected_categories->[1];
                        }
                        if (!IsStringWithData($Incident{ProductCat3}) && $selected_categories->[2]) {
                            $Incident{ProductCat3} = $selected_categories->[2];
                        }
                        if (!IsStringWithData($Incident{ProductCat4}) && $selected_categories->[3]) {
                            $Incident{ProductCat4} = $selected_categories->[3];
                        }
                        
                        $Self->{DebuggerObject}->Notice(
                            Summary => "Auto-populated Product Categories for CIDeviceType: $deviceType"
                        );
                    } else {
                        $Self->{DebuggerObject}->Notice(
                            Summary => "No matching mapping found for CIDeviceType: $deviceType and ProductCat1: " . ($Incident{ProductCat1} || '')
                        );
                    }
                } else {
                    $Self->{DebuggerObject}->Notice(
                        Summary => "No mapping found for CIDeviceType: $deviceType"
                    );
                }
            }
        };
        if ($@) {
            $Self->{DebuggerObject}->Error(
                Summary => "Error during device type mapping: $@"
            );
        }
    } else {
        $Self->{DebuggerObject}->Notice(
            Summary => "No CIDeviceType provided or empty - skipping auto-mapping"
        );
    }

    # Validate that ProductCat1 is now available (either provided or auto-populated)
    # ProductCat2 is now optional
    $Self->{DebuggerObject}->Notice(
        Summary => "Final validation - ProductCat1: " . ($Incident{ProductCat1} || 'EMPTY') . 
                  ", ProductCat2: " . ($Incident{ProductCat2} || 'EMPTY')
    );
    
    # Only ProductCat1 is required
    if ( !IsStringWithData( $Incident{ProductCat1} ) ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentCreate.MissingParameter',
            ErrorMessage => "IncidentCreate: Incident->ProductCat1 parameter is missing and could not be auto-populated from CIDeviceType!",
        );
    }

    # get incident object
    my $IncidentObject = $Kernel::OM->Get('Kernel::System::Incident');

    # Priority mapping: P1, P2, P3, P4 -> Znuny ticket priorities
    my %PriorityMapping = (
        'P1' => 'P1-Critical',
        'P2' => 'P2-High',
        'P3' => 'P3-Medium',
        'P4' => 'P4-Low',
    );

    # Handle priority mapping for both Ticket Priority and IncidentPriority dynamic field
    if ( $Incident{Priority} && exists $PriorityMapping{$Incident{Priority}} ) {
        my $OriginalPriority = $Incident{Priority};  # Store P1, P2, etc.
        
        # Set Znuny Ticket Priority (system field)
        $Incident{Priority} = $PriorityMapping{$OriginalPriority};
        
        # Set IncidentPriority dynamic field to P1, P2, etc.
        $Incident{IncidentPriority} = $OriginalPriority;
    }

    # set defaults
    $Incident{State}       ||= 'New';
    $Incident{Description} ||= '';
    $Incident{CI}          ||= '';
    $Incident{AssignedTo}  ||= '';

    # create incident
    my $IncidentID = $IncidentObject->IncidentCreate(
        %Incident,
        UserID => $UserID,
    );

    if ( !$IncidentID ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentCreate.IncidentCreateFailed',
            ErrorMessage => "IncidentCreate: Incident could not be created!",
        );
    }

    # Force set the ticket priority if it was mapped (IncidentCreate might ignore it)
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    if ( $Incident{Priority} && $Incident{Priority} =~ /^P[1-4]-/ ) {
        $TicketObject->TicketPrioritySet(
            TicketID => $IncidentID,
            Priority => $Incident{Priority},
            UserID   => $UserID,
        );
    }

    # Set dynamic fields that might not have been set by IncidentCreate
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    
    # List of dynamic fields to set
    my @DynamicFieldsToSet = qw(
        IncidentSource IncidentPriority CI IncidentAssignmentGroup IncidentAssignedTo
        IncidentShortDescription Description ProductCat1 ProductCat2 ProductCat3 ProductCat4
        OperationalCat1 OperationalCat2 OperationalCat3 WorkNotes ResolutionCat1 ResolutionCat2
        ResolutionCat3 ResolutionCode ResolutionNotes Opened OpenedBy Updated UpdatedBy
        Response Resolved AlarmID EventID EventSite SourceDevice EventMessage
        EventBeginTime EventDetectTime CIDeviceType MSITicketNumber Customer MSITicketSite
        MSITicketState MSITicketStateReason MSITicketPriority MSITicketAssignee
        MSITicketShortDescription MSITicketResolutionNote MSITicketCreatedTime
        MSITicketLastUpdateTime MSITicketEbondLastUpdateTime MSITicketResolvedTime
        MSIEbondAPIResponse MSITicketComment
    );
    
    for my $FieldName (@DynamicFieldsToSet) {
        next if !defined $Incident{$FieldName} || $Incident{$FieldName} eq '';
        
        my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
            Name => $FieldName,
        );
        
        if ($DynamicFieldConfig) {
            $DynamicFieldBackendObject->ValueSet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ObjectID           => $IncidentID,
                Value              => $Incident{$FieldName},
                UserID             => $UserID,
            );
        }
    }

    # The IncidentID returned from IncidentCreate is actually the TicketID
    # Get the actual incident data using the TicketID (reuse TicketObject from above)
    my %TicketData = $TicketObject->TicketGet(
        TicketID      => $IncidentID,  # IncidentID is actually TicketID
        UserID        => $UserID,
        DynamicFields => 1,
        Extended      => 1,
    );

    # Get incident data using the ticket ID as IncidentID
    my %IncidentData = $IncidentObject->IncidentGet(
        IncidentID => $IncidentID,
        UserID     => $UserID,
    );

    # Send SMS notification using the proper SMS event handler
    eval {
        my $SMSNotificationObject = $Kernel::OM->Get('Kernel::System::Ticket::Event::SMSNotification');
        
        $Self->{DebuggerObject}->Notice(
            Summary => "Calling SMS event handler for new incident $IncidentID"
        );
        
        # Call the SMS event handler with proper parameters
        my $result = $SMSNotificationObject->Run(
            Event  => 'TicketCreate',
            Data   => {
                TicketID => $IncidentID,
            },
            Config => {},
            UserID => $UserID,
        );
        
        $Self->{DebuggerObject}->Notice(
            Summary => "SMS event handler completed for incident $IncidentID, result: " . ($result || 'NO RESULT')
        );
    };
    if ($@) {
        $Self->{DebuggerObject}->Error(
            Summary => "EXCEPTION calling SMS event handler for incident $IncidentID: $@"
        );
    }

    return {
        Success => 1,
        Data    => {
            IncidentID     => $IncidentID,
            TicketID       => $IncidentID,  # Same as IncidentID
            TicketNumber   => $TicketData{TicketNumber} || '',
            State          => $TicketData{State} || '',
            Priority       => $TicketData{Priority} || '',
            Source         => $TicketData{DynamicField_IncidentSource} || $Incident{Source} || '',
            Title          => $TicketData{Title} || '',
            Created        => $TicketData{Created} || '',
            Queue          => $TicketData{Queue} || '',
            ProductCat1    => $TicketData{DynamicField_ProductCat1} || $Incident{ProductCat1} || '',
            ProductCat2    => $TicketData{DynamicField_ProductCat2} || $Incident{ProductCat2} || '',
            ProductCat3    => $TicketData{DynamicField_ProductCat3} || $Incident{ProductCat3} || '',
            ProductCat4    => $TicketData{DynamicField_ProductCat4} || $Incident{ProductCat4} || '',
            Message        => "Incident $IncidentID created successfully" .
                            ($TicketData{TicketNumber} ? " with ticket number " . $TicketData{TicketNumber} : ""),
        },
    };
}

1;