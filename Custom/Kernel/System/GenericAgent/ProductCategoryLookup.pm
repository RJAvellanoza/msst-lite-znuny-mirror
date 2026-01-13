# --
# Kernel/System/GenericAgent/ProductCategoryLookup.pm - Generic Agent module to update product categories
# --

package Kernel::System::GenericAgent::ProductCategoryLookup;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::DB',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Get logger first
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # Get required objects
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $BackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Check for individual ticket parameters
    my $SingleTicketID = $Param{TicketID} || $Param{Param1};
    my $SingleTicketNumber = $Param{TicketNumber} || $Param{Param2};
    
    # Get dynamic field list without verbose logging
    my $DynamicFields = $DynamicFieldObject->DynamicFieldList(
        Valid      => 1,
        ObjectType => ['Ticket'],
    );

    # Handle different ways tickets might be passed
    my @TicketIDs = ();
    
    # Method 1: Standard GetTicketIDs array
    if ($Param{GetTicketIDs} && ref($Param{GetTicketIDs}) eq 'ARRAY') {
        @TicketIDs = @{ $Param{GetTicketIDs} };
    }
    # Method 2: Individual TicketID parameter
    elsif ($SingleTicketID) {
        @TicketIDs = ($SingleTicketID);
    }
    # Method 3: Search for tickets with CIDeviceType field set
    else {
        # Search for tickets that have CIDeviceType dynamic field set
        @TicketIDs = $TicketObject->TicketSearch(
            Result => 'ARRAY',
            UserID => 1,
            DynamicField_CIDeviceType => {
                Like => '*',  # Any value
            },
            Limit => 100,  # Reasonable limit
        );
    }
    
    # Exit if no tickets to process
    if (!@TicketIDs) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "No tickets found to process",
        );
        return 1;
    }

    # Get dynamic field configurations
    my $CIDeviceTypeField = $DynamicFieldObject->DynamicFieldGet(
        Name => 'CIDeviceType',
    );
    
    if (!$CIDeviceTypeField) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "CIDeviceType dynamic field not found!",
        );
        return;
    }

    my @ProductCatFields;
    for my $i (1..4) {
        my $Field = $DynamicFieldObject->DynamicFieldGet(
            Name => "ProductCat$i",
        );
        if ($Field) {
            push @ProductCatFields, $Field;
        } else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "ProductCat$i dynamic field not found!",
            );
        }
    }

    # Process each ticket
    TICKET:
    for my $TicketID (@TicketIDs) {
        # Get CI Device Type value
        my $DeviceTypeValue = $BackendObject->ValueGet(
            DynamicFieldConfig => $CIDeviceTypeField,
            ObjectID          => $TicketID,
        );

        if (!$DeviceTypeValue) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Ticket $TicketID has no CI Device Type value, skipping",
            );
            next TICKET;
        }

        # Query database for product categories
        my $SQL = "SELECT ProductCategory1, ProductCategory2, ProductCategory3, ProductCategory4 
                   FROM product_categories_mapping 
                   WHERE CIDeviceType = ?";
        
        # Prepare and execute query
        my $Success = $DBObject->Prepare(
            SQL   => $SQL,
            Bind  => [\$DeviceTypeValue],
        );

        if (!$Success) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Database query failed for CIDeviceType: '$DeviceTypeValue'. Check database permissions.",
            );
            next TICKET;
        }

        # Fetch results
        my @ProductCategories;
        while (my @Row = $DBObject->FetchrowArray()) {
            @ProductCategories = @Row;
            last;  # Only process first matching row
        }

        if (!@ProductCategories) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "No product categories found for CIDeviceType: '$DeviceTypeValue'",
            );
            next TICKET;
        }

        # Update dynamic fields
        for my $i (0..3) {
            my $CategoryValue = $ProductCategories[$i];
            next if !defined $CategoryValue || $CategoryValue eq '' || !$ProductCatFields[$i];

            my $Success = $BackendObject->ValueSet(
                DynamicFieldConfig => $ProductCatFields[$i],
                ObjectID          => $TicketID,
                Value             => $CategoryValue,
                UserID            => 1,
            );

            if (!$Success) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Failed to update ProductCat" . ($i+1) . " for ticket $TicketID",
                );
            }
        }
    }

    $LogObject->Log(
        Priority => 'error',
        Message  => "ProductCategoryLookup module completed processing",
    );

    return 1;
}

1;