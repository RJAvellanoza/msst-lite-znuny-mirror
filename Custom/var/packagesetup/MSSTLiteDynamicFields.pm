# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package var::packagesetup::MSSTLiteDynamicFields;

use strict;
use warnings;

# List of dynamic fields to create
my @DynamicFields = (
    # Incident Core Fields
    {
        Name       => 'IncidentNumber',
        Label      => 'Incident Number',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'IncidentSource',
        Label      => 'Incident Source',
        FieldType  => 'Dropdown',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue   => '',
            Link           => '',
            PossibleNone   => 1,
            PossibleValues => {
                'Event Monitoring'    => 'Event Monitoring',
                'Direct Input'     => 'Direct Input',
            },
        },
    },
    {
        Name       => 'IncidentPriority',
        Label      => 'Incident Priority',
        FieldType  => 'Dropdown',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue   => '',
            Link           => '',
            PossibleNone   => 1,
            PossibleValues => {
                'P1' => '1 - Critical',
                'P2' => '2 - High',
                'P3' => '3 - Moderate',
                'P4' => '4 - Low',
                'P5' => '5 - Planning',
            },
        },
    },
    {
        Name       => 'IncidentState',
        Label      => 'Incident State',
        FieldType  => 'Dropdown',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue   => 'new',
            Link           => '',
            PossibleNone   => 0,
            PossibleValues => {
                'new'        => 'New',
                'in progress' => 'In Progress',
                'pending'    => 'Pending',
                'resolved'   => 'Resolved',
                'closed'     => 'Closed',
                'cancelled'  => 'Cancelled',
            },
        },
    },
    {
        Name       => 'CI',
        Label      => 'Configuration Item',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'IncidentAssignmentGroup',
        Label      => 'Assignment Group',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'IncidentAssignedTo',
        Label      => 'Assigned To',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'IncidentShortDescription',
        Label      => 'Short Description',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'Description',
        Label      => 'Incident Description',
        FieldType  => 'TextArea',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Rows         => 7,
            Cols         => 50,
        },
    },
    
    # Category Fields
    {
        Name       => 'ProductCat1',
        Label      => 'Product Category 1',
        FieldType  => 'Dropdown',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue   => '',
            Link           => '',
            PossibleNone   => 1,
            PossibleValues => {
                'ASTRO'     => 'ASTRO',
                'DIMETRA'   => 'DIMETRA',
                'WAVE'      => 'WAVE',
            },
        },
    },
    {
        Name       => 'ProductCat2',
        Label      => 'Product Category 2',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'ProductCat3',
        Label      => 'Product Category 3',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'ProductCat4',
        Label      => 'Product Category 4',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'OperationalCat1',
        Label      => 'Operation Category Tier 1',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'OperationalCat2',
        Label      => 'Operation Category Tier 2',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'OperationalCat3',
        Label      => 'Operation Category Tier 3',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    
    # Work and Resolution
    {
        Name       => 'WorkNotes',
        Label      => 'Work Notes',
        FieldType  => 'TextArea',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Rows         => 7,
            Cols         => 50,
        },
    },
    {
        Name       => 'ResolutionCat1',
        Label      => 'Resolution Category Tier 1',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'ResolutionCat2',
        Label      => 'Resolution Category Tier 2',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'ResolutionCat3',
        Label      => 'Resolution Category Tier 3',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'ResolutionCode',
        Label      => 'Resolution Code',
        FieldType  => 'Dropdown',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue   => '',
            Link           => '',
            PossibleNone   => 1,
            PossibleValues => {
                'Solved'            => 'Solved',
                'Workaround'        => 'Workaround',
                'Cancelled'         => 'Cancelled',
                'Duplicate'         => 'Duplicate',
                'Not Reproducible'  => 'Not Reproducible',
                'Known Error'       => 'Known Error',
            },
        },
    },
    {
        Name       => 'ResolutionNotes',
        Label      => 'Resolution Notes',
        FieldType  => 'TextArea',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Rows         => 7,
            Cols         => 50,
        },
    },
    
    # Timestamps
    {
        Name       => 'Opened',
        Label      => 'Opened',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    {
        Name       => 'OpenedBy',
        Label      => 'Opened By',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'Updated',
        Label      => 'Updated',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    {
        Name       => 'UpdatedBy',
        Label      => 'Updated By',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'Response',
        Label      => 'Response',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    {
        Name       => 'Resolved',
        Label      => 'Resolved',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    
    # Event Fields
    {
        Name       => 'AlarmID',
        Label      => 'Alarm ID',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'EventID',
        Label      => 'Event ID',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'EventSite',
        Label      => 'Event Site',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'SourceDevice',
        Label      => 'Source Device',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'EventMessage',
        Label      => 'Event Message',
        FieldType  => 'TextArea',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Rows         => 5,
            Cols         => 50,
        },
    },
    {
        Name       => 'EventBeginTime',
        Label      => 'Event Begin Time',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    {
        Name       => 'EventDetectTime',
        Label      => 'Event Detect Time',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    {
        Name       => 'CIDeviceType',
        Label      => 'CI Device Type',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    
    # MSI Fields
    {
        Name       => 'MSITicketNumber',
        Label      => 'MSI Ticket Number',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'MSITicketSysID',
        Label      => 'MSI Ticket Sys ID',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'MSITicketURL',
        Label      => 'MSI Ticket URL',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'Customer',
        Label      => 'Customer',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'MSITicketSite',
        Label      => 'MSI Ticket Site',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'MSITicketState',
        Label      => 'MSI Ticket State',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'MSITicketStateReason',
        Label      => 'MSI Ticket State Reason',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'MSITicketPriority',
        Label      => 'MSI Ticket Priority',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'MSITicketAssignee',
        Label      => 'MSI Ticket Assignee',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'MSITicketShortDescription',
        Label      => 'MSI Ticket Short Description',
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Link         => '',
        },
    },
    {
        Name       => 'MSITicketResolutionNote',
        Label      => 'MSI Ticket Resolution Note',
        FieldType  => 'TextArea',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Rows         => 5,
            Cols         => 50,
        },
    },
    {
        Name       => 'MSITicketCreatedTime',
        Label      => 'MSI Ticket Created Time',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    {
        Name       => 'MSITicketLastUpdateTime',
        Label      => 'MSI Ticket Last Update Time',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    {
        Name       => 'MSITicketEbondLastUpdateTime',
        Label      => 'MSI Ticket Ebond Last Update Time',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    {
        Name       => 'MSITicketResolvedTime',
        Label      => 'MSI Ticket Resolved Time',
        FieldType  => 'DateTime',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue  => '',
            Link          => '',
            YearsPeriod   => '0',
            YearsInFuture => '5',
            YearsInPast   => '5',
        },
    },
    {
        Name       => 'MSIEbondAPIResponse',
        Label      => 'MSI Ebond API Response',
        FieldType  => 'TextArea',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Rows         => 10,
            Cols         => 50,
        },
    },
    {
        Name       => 'MSITicketComment',
        Label      => 'MSI Ticket Comment',
        FieldType  => 'TextArea',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            Rows         => 5,
            Cols         => 50,
        },
    },
    {
        Name       => 'AssignedTo',
        Label      => 'Assigned To',
        FieldType  => 'Dropdown',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue   => '99',
            Link           => '',
            PossibleNone   => 0,
            PossibleValues => {
                '99'  => 'Unassigned',
                '5'  => 'nocadmin1 Auto',
                '6'  => 'nocadmin2 Auto',
                '7'  => 'nocuser1 Auto',
                '8'  => 'nocuser2 Auto',
                '9'  => 'nocuser3 Auto',
                '10' => 'nocuser4 Auto',
                '11' => 'nocuser5 Auto',
                '12' => 'nocuser6 Auto',
                '13' => 'nocuser7 Auto',
                '14' => 'nocuser8 Auto',
            },
        },
    },
);

# Function to create dynamic fields
sub CreateDynamicFields {
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
    
    my $CreatedCount = 0;
    my $UpdatedCount = 0;
    my $FailedCount = 0;
    
    for my $DynamicFieldConfig (@DynamicFields) {
        # Check if field already exists
        my $ExistingField = $DynamicFieldObject->DynamicFieldGet(
            Name => $DynamicFieldConfig->{Name},
        );
        
        if ($ExistingField && $ExistingField->{ID}) {
            # Update existing field
            my $Success = $DynamicFieldObject->DynamicFieldUpdate(
                ID         => $ExistingField->{ID},
                Name       => $DynamicFieldConfig->{Name},
                Label      => $DynamicFieldConfig->{Label},
                FieldOrder => $ExistingField->{FieldOrder},
                FieldType  => $DynamicFieldConfig->{FieldType},
                ObjectType => $DynamicFieldConfig->{ObjectType},
                Config     => $DynamicFieldConfig->{Config},
                ValidID    => 1,
                UserID     => 1,
            );
            
            if ($Success) {
                $UpdatedCount++;
                print "Updated dynamic field: $DynamicFieldConfig->{Name}\n";
            } else {
                $FailedCount++;
                print "Failed to update dynamic field: $DynamicFieldConfig->{Name}\n";
            }
        } else {
            # Create new field
            my $FieldID = $DynamicFieldObject->DynamicFieldAdd(
                Name       => $DynamicFieldConfig->{Name},
                Label      => $DynamicFieldConfig->{Label},
                FieldOrder => 9999,
                FieldType  => $DynamicFieldConfig->{FieldType},
                ObjectType => $DynamicFieldConfig->{ObjectType},
                Config     => $DynamicFieldConfig->{Config},
                ValidID    => 1,
                UserID     => 1,
            );
            
            if ($FieldID) {
                $CreatedCount++;
                print "Created dynamic field: $DynamicFieldConfig->{Name} (ID: $FieldID)\n";
            } else {
                $FailedCount++;
                print "Failed to create dynamic field: $DynamicFieldConfig->{Name}\n";
            }
        }
    }
    
    print "\n=== Dynamic Field Creation Summary ===\n";
    print "Created: $CreatedCount\n";
    print "Updated: $UpdatedCount\n";
    print "Failed: $FailedCount\n";
    print "Total: " . scalar(@DynamicFields) . "\n";
    
    return ($FailedCount == 0);
}

1;