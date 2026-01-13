# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentReportTickets;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
    'Kernel::System::Time',
    'Kernel::System::DB',
    'Kernel::System::Queue',
    'Kernel::System::Priority',
    'Kernel::System::State',
    'Kernel::System::User',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');

    # Get ALL URL parameters
    my %GetParam;
    for my $Param ( $ParamObject->GetParamNames() ) {
        my @Values = $ParamObject->GetArray( Param => $Param );
        if ( @Values > 1 ) {
            $GetParam{$Param} = \@Values;
        }
        elsif ( @Values == 1 ) {
            $GetParam{$Param} = $Values[0];
        }
    }

    # Handle comma-separated array parameters (from URL like Priorities=P1,P2)
    # ALWAYS convert to array refs, even for single values
    for my $ArrayParam (qw(
        StateIDs States StateTypeIDs QueueIDs Queues PriorityIDs Priorities
        OwnerIDs ResponsibleIDs WatchUserIDs TypeIDs Types ServiceIDs Services
        SLAIDs SLAs LockIDs Locks CreatedQueueIDs CreatedUserIDs CreatedTypes
        CreatedTypeIDs CreatedPriorities CreatedPriorityIDs CreatedStates CreatedStateIDs
    )) {
        if ( $GetParam{$ArrayParam} && ref( $GetParam{$ArrayParam} ) ne 'ARRAY' ) {
            my @Values = split( /,/, $GetParam{$ArrayParam} );
            $GetParam{$ArrayParam} = \@Values;  # Always convert to array ref
        }
    }

    # Handle DynamicField_ parameters - convert to proper TicketSearch format
    # URL format: DynamicField_ProductCat3=VMware/ESXi
    # TicketSearch format: DynamicField_ProductCat3 => { Equals => 'VMware/ESXi' }
    # Special case: "Unknown" means NULL/empty values - these require post-search filtering
    my %DynamicFieldUnknown;  # Track dynamic fields where we need to filter for NULL/empty
    my %DynamicFieldOriginal; # Preserve original values for URL building
    for my $Param ( keys %GetParam ) {
        if ( $Param =~ /^DynamicField_(.+)$/ && ref( $GetParam{$Param} ) ne 'HASH' ) {
            my $FieldName = $1;
            my $Value = delete $GetParam{$Param};

            # Preserve original value for URL building
            $DynamicFieldOriginal{$Param} = $Value;

            # Special case: "Unknown" means the field is NULL or empty
            # TicketSearch can't handle this directly, so we do post-search filtering
            if ( $Value eq 'Unknown' ) {
                $DynamicFieldUnknown{$FieldName} = 1;
                # Don't add to GetParam - we'll filter after search
            }
            else {
                $GetParam{$Param} = {
                    Equals => $Value,
                };
            }
        }
    }

    # Handle CSV export
    if ( $GetParam{Subaction} && $GetParam{Subaction} eq 'ExportCSV' ) {
        return $Self->_ExportCSV(
            %GetParam,
            DynamicFieldUnknown => \%DynamicFieldUnknown,
        );
    }

    # Handle SearchInArchive parameter
    if ( $GetParam{SearchInArchive} ) {
        if ( $GetParam{SearchInArchive} eq 'AllTickets' ) {
            $GetParam{ArchiveFlags} = [ 'y', 'n' ];
        }
        elsif ( $GetParam{SearchInArchive} eq 'ArchivedTickets' ) {
            $GetParam{ArchiveFlags} = ['y'];
        }
        else {
            $GetParam{ArchiveFlags} = ['n'];
        }
    }

    # Handle AssignedOnly parameter - filter to exclude unassigned users (1 and 99)
    my $AssignedOnly = delete $GetParam{AssignedOnly};  # Remove from GetParam so it doesn't break TicketSearch

    # Handle Unresponded parameter - filter for tickets that have NEVER been assigned
    my $Unresponded = delete $GetParam{Unresponded};

    # Handle resolution time filtering (for MTTR breakdown links)
    # These are custom parameters not supported by TicketSearch, so we filter post-search
    my $ResolutionTimeNewerDate = delete $GetParam{ResolutionTimeNewerDate};
    my $ResolutionTimeOlderDate = delete $GetParam{ResolutionTimeOlderDate};

    # Handle TicketCloseTime filtering (for closure report drilldown)
    # TicketSearch interprets these differently than the closure report's ticket_history-based counting
    # We use post-search filtering to match the closure report's logic
    my $TicketCloseTimeNewerDate = delete $GetParam{TicketCloseTimeNewerDate};
    my $TicketCloseTimeOlderDate = delete $GetParam{TicketCloseTimeOlderDate};

    # Handle AssignmentStatus from filter form
    my $AssignmentStatus = delete $GetParam{AssignmentStatus};
    if ($AssignmentStatus) {
        if ($AssignmentStatus eq 'assigned') {
            $AssignedOnly = 1;
        } elsif ($AssignmentStatus eq 'unassigned') {
            $GetParam{OwnerIDs} = ['99'];  # Filter to unassigned
        }
    }

    # IMPORTANT: When StateType=Closed is used, exclude 'cancelled' state
    # The cancelled state has type_id=3 (closed type) but should never appear in closure reports
    if ( $GetParam{StateType} && $GetParam{StateType} eq 'Closed' ) {
        my $StateObject = $Kernel::OM->Get('Kernel::System::State');
        my %StateList = $StateObject->StateList( UserID => 1, Valid => 1 );

        # Get state IDs for all closed-type states EXCEPT cancelled
        my @ClosedStateIDs;
        for my $StateID ( keys %StateList ) {
            my %State = $StateObject->StateGet( ID => $StateID );
            if ( $State{TypeName} eq 'closed' && lc($State{Name}) ne 'cancelled' ) {
                push @ClosedStateIDs, $StateID;
            }
        }

        # Replace StateType with explicit StateIDs to exclude cancelled
        if (@ClosedStateIDs) {
            delete $GetParam{StateType};
            $GetParam{StateIDs} = \@ClosedStateIDs;
        }
    }

    # Set defaults for sorting and pagination
    my $SortBy      = $GetParam{SortBy}      || 'Age';
    my $OrderBy     = $GetParam{OrderBy}     || 'Down';
    my $PageSize    = $GetParam{PageSize}    || 25;     # Tickets per page
    my $CurrentPage = $GetParam{Page}        || 1;

    # Get the REAL total count first (no limit)
    my $TotalCount = $TicketObject->TicketSearch(
        Result   => 'COUNT',
        UserID   => $Self->{UserID},
        %GetParam,
    );

    # Search tickets using Znuny's TicketSearch API
    # Note: We fetch all matching ticket IDs for proper pagination, but only get details for current page
    my @AllTicketIDs = $TicketObject->TicketSearch(
        Result   => 'ARRAY',
        SortBy   => $SortBy,
        OrderBy  => $OrderBy,
        Limit    => 100000,    # Override default 10000 limit
        UserID   => $Self->{UserID},
        %GetParam,    # Pass ALL URL parameters through
    );

    # If AssignedOnly is set, filter to tickets CURRENTLY assigned (user_id NOT IN 1, 99)
    if ( $AssignedOnly && @AllTicketIDs ) {
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        my $TicketIDList = join(',', @AllTicketIDs);

        # Get tickets that are currently assigned (user_id is not 1 or 99)
        my @FilteredTicketIDs;
        my $SQL = qq{
            SELECT id FROM ticket
            WHERE id IN ($TicketIDList)
            AND user_id IS NOT NULL
            AND user_id NOT IN (1, 99)
        };

        if ($DBObject->Prepare(SQL => $SQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                push @FilteredTicketIDs, $Row[0];
            }
        }

        # Preserve the original order from TicketSearch
        my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
        @AllTicketIDs = grep { $FilteredSet{$_} } @AllTicketIDs;
    }

    # If Unresponded is set, filter to tickets that are CURRENTLY unassigned
    if ( $Unresponded && @AllTicketIDs ) {
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        my $TicketIDList = join(',', @AllTicketIDs);

        # Get tickets that are currently unassigned (user_id is root or unassigned)
        my @FilteredTicketIDs;
        my $SQL = qq{
            SELECT id FROM ticket
            WHERE id IN ($TicketIDList)
            AND user_id IN (1, 99)
        };

        if ($DBObject->Prepare(SQL => $SQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                push @FilteredTicketIDs, $Row[0];
            }
        }

        # Preserve the original order from TicketSearch
        my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
        @AllTicketIDs = grep { $FilteredSet{$_} } @AllTicketIDs;
    }

    # If resolution time filters are set, filter to tickets resolved within the date range
    # Resolution time = first time ticket moved to a closed state (type_id = 3) WITHIN the date range
    # This matches the MTTR breakdown logic - tickets reopened and re-resolved are counted in the correct period
    # Fallback to change_time for tickets without StateUpdate history
    if ( ($ResolutionTimeNewerDate || $ResolutionTimeOlderDate) && @AllTicketIDs ) {
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        my $TicketIDList = join(',', @AllTicketIDs);

        # Build date range conditions
        my $StartDate = $ResolutionTimeNewerDate || '1970-01-01 00:00:00';
        my $EndDate = $ResolutionTimeOlderDate || '2099-12-31 23:59:59';

        # Find tickets that have a resolution (StateUpdate to closed state) within the date range
        # OR tickets currently in closed state with change_time in range (fallback for no history)
        my $SQL = qq{
            WITH first_resolution_in_range AS (
                SELECT
                    th.ticket_id,
                    MIN(th.create_time) as resolved_time
                FROM ticket_history th
                JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
                WHERE th.ticket_id IN ($TicketIDList)
                  AND th.history_type_id = 27
                  AND ts_hist.type_id = 3
                  AND ts_hist.name != 'cancelled'
                  AND th.create_time >= ?
                  AND th.create_time <= ?
                GROUP BY th.ticket_id
            )
            SELECT DISTINCT t.id as ticket_id
            FROM ticket t
            JOIN ticket_state ts ON t.ticket_state_id = ts.id
            LEFT JOIN first_resolution_in_range fr ON t.id = fr.ticket_id
            WHERE t.id IN ($TicketIDList)
              AND (
                  fr.ticket_id IS NOT NULL
                  OR (ts.type_id = 3 AND ts.name != 'cancelled'
                      AND t.change_time >= ? AND t.change_time <= ?)
              )
        };

        my @FilteredTicketIDs;
        if ($DBObject->Prepare(SQL => $SQL, Bind => [\$StartDate, \$EndDate, \$StartDate, \$EndDate])) {
            while (my @Row = $DBObject->FetchrowArray()) {
                push @FilteredTicketIDs, $Row[0];
            }
        }

        # Preserve the original order from TicketSearch
        my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
        @AllTicketIDs = grep { $FilteredSet{$_} } @AllTicketIDs;
    }

    # If TicketCloseTime filters are set, filter to tickets CLOSED within the date range
    # This matches the closure report's logic - using ticket_history StateUpdate events
    if ( ($TicketCloseTimeNewerDate || $TicketCloseTimeOlderDate) && @AllTicketIDs ) {
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        my $TicketIDList = join(',', @AllTicketIDs);

        # Build date range conditions
        my $StartDate = $TicketCloseTimeNewerDate || '1970-01-01 00:00:00';
        my $EndDate = $TicketCloseTimeOlderDate || '2099-12-31 23:59:59';

        # Find tickets that were CLOSED (not just resolved) within the date range
        my $SQL = qq{
            SELECT DISTINCT th.ticket_id
            FROM ticket_history th
            JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
            WHERE th.ticket_id IN ($TicketIDList)
              AND th.history_type_id = 27
              AND ts_hist.name = 'closed'
              AND th.create_time >= ?
              AND th.create_time <= ?
        };

        my @FilteredTicketIDs;
        if ($DBObject->Prepare(SQL => $SQL, Bind => [\$StartDate, \$EndDate])) {
            while (my @Row = $DBObject->FetchrowArray()) {
                push @FilteredTicketIDs, $Row[0];
            }
        }

        # Preserve the original order from TicketSearch
        my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
        @AllTicketIDs = grep { $FilteredSet{$_} } @AllTicketIDs;
    }

    # If DynamicFieldUnknown is set, filter to tickets where the dynamic field is NULL or empty
    # This handles the "Unknown" category in reports - tickets with no value set for the field
    if ( %DynamicFieldUnknown && @AllTicketIDs ) {
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        my $TicketIDList = join(',', @AllTicketIDs);

        for my $FieldName ( keys %DynamicFieldUnknown ) {
            # Get the dynamic field ID
            my $FieldIDSQL = q{SELECT id FROM dynamic_field WHERE name = ?};
            my $FieldID;

            if ( $DBObject->Prepare( SQL => $FieldIDSQL, Bind => [\$FieldName] ) ) {
                while ( my @Row = $DBObject->FetchrowArray() ) {
                    $FieldID = $Row[0];
                }
            }

            next if !$FieldID;

            # Find tickets where the dynamic field value is NULL or empty
            # Either no record in dynamic_field_value, or value_text is NULL/empty
            my $SQL = qq{
                SELECT t.id
                FROM ticket t
                LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id AND dfv.field_id = ?
                WHERE t.id IN ($TicketIDList)
                  AND (dfv.value_text IS NULL OR dfv.value_text = '')
            };

            my @FilteredTicketIDs;
            if ( $DBObject->Prepare( SQL => $SQL, Bind => [\$FieldID] ) ) {
                while ( my @Row = $DBObject->FetchrowArray() ) {
                    push @FilteredTicketIDs, $Row[0];
                }
            }

            # Preserve the original order from TicketSearch
            my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
            @AllTicketIDs = grep { $FilteredSet{$_} } @AllTicketIDs;
        }
    }

    # Update TotalCount to match filtered results (AssignedOnly/Unresponded/ResolutionTime reduce the count)
    $TotalCount = scalar @AllTicketIDs;

    # Calculate pagination
    my $TotalPages  = int( ( $TotalCount + $PageSize - 1 ) / $PageSize ) || 1;
    $CurrentPage = 1 if $CurrentPage < 1;
    $CurrentPage = $TotalPages if $CurrentPage > $TotalPages;

    my $StartIndex = ( $CurrentPage - 1 ) * $PageSize;
    my $EndIndex   = $StartIndex + $PageSize - 1;
    $EndIndex = $TotalCount - 1 if $EndIndex >= $TotalCount;

    # Get only the ticket IDs for current page
    my @PageTicketIDs = $TotalCount > 0 ? @AllTicketIDs[ $StartIndex .. $EndIndex ] : ();

    # Get ticket details for display - ONLY for current page
    my @Tickets;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Get FirstAssigned, ResolvedTime, and ClosedTime ONLY for page tickets
    my %FirstAssigned;
    my %ResolvedTime;
    my %ClosedTime;

    if (@PageTicketIDs) {
        my $TicketIDList = join(',', @PageTicketIDs);

        # Get first assignment time:
        # - If ticket was created with owner assigned, use create_time (MTRD = 0)
        # - If ticket was assigned later via OwnerUpdate, use first OwnerUpdate time
        my $AssignedSQL = qq{
            SELECT
                t.id as ticket_id,
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 23
                       AND th.owner_id NOT IN (1, 99)),
                    CASE WHEN t.user_id NOT IN (1, 99) THEN t.create_time ELSE NULL END
                ) as first_assigned
            FROM ticket t
            WHERE t.id IN ($TicketIDList)
        };

        if ($DBObject->Prepare(SQL => $AssignedSQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                $FirstAssigned{$Row[0]} = $Row[1];
            }
        }

        # Get resolved time (first time ticket moved to closed state - history_type_id = 27 is StateUpdate)
        my $ResolvedSQL = qq{
            SELECT th.ticket_id, MIN(th.create_time) as resolved_time
            FROM ticket_history th
            JOIN ticket_state ts ON th.state_id = ts.id
            WHERE th.ticket_id IN ($TicketIDList)
              AND th.history_type_id = 27
              AND ts.type_id = 3
            GROUP BY th.ticket_id
        };

        if ($DBObject->Prepare(SQL => $ResolvedSQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                $ResolvedTime{$Row[0]} = $Row[1];
            }
        }

        # Get closed time (first time ticket moved specifically to 'closed' state, not 'resolved')
        my $ClosedSQL = qq{
            SELECT th.ticket_id, MIN(th.create_time) as closed_time
            FROM ticket_history th
            JOIN ticket_state ts ON th.state_id = ts.id
            WHERE th.ticket_id IN ($TicketIDList)
              AND th.history_type_id = 27
              AND ts.name = 'closed'
            GROUP BY th.ticket_id
        };

        if ($DBObject->Prepare(SQL => $ClosedSQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                $ClosedTime{$Row[0]} = $Row[1];
            }
        }
    }

    for my $TicketID (@PageTicketIDs) {
        my %Ticket = $TicketObject->TicketGet(
            TicketID      => $TicketID,
            DynamicFields => 1,
            UserID        => $Self->{UserID},
        );

        # Calculate age in human-readable format
        my $CreateSystemTime = $TimeObject->TimeStamp2SystemTime(
            String => $Ticket{Created},
        );
        my $CurrentTime = $TimeObject->SystemTime();
        my $AgeSeconds  = $CurrentTime - $CreateSystemTime;

        my $Age = $Self->_FormatAge($AgeSeconds);

        # Calculate MTRD (Hours) - time from create to first assignment
        my $MTRD = '-';
        if ($FirstAssigned{$TicketID}) {
            my $AssignedTime = $TimeObject->TimeStamp2SystemTime(String => $FirstAssigned{$TicketID});
            my $DiffSeconds = $AssignedTime - $CreateSystemTime;
            $MTRD = sprintf("%.1f", $DiffSeconds / 3600) if $DiffSeconds >= 0;
        }

        # Calculate MTTR (Days) - time from create to resolution (only if currently closed)
        my $MTTR = '-';
        if ($ResolvedTime{$TicketID} && $Ticket{StateType} eq 'closed') {
            my $ResolvedTimeStamp = $TimeObject->TimeStamp2SystemTime(String => $ResolvedTime{$TicketID});
            my $DiffSeconds = $ResolvedTimeStamp - $CreateSystemTime;
            $MTTR = sprintf("%.1f", $DiffSeconds / 86400) if $DiffSeconds >= 0;
        }

        push @Tickets,
            {
            TicketID      => $Ticket{TicketID},
            TicketNumber  => $Ticket{TicketNumber},
            Title         => $Ticket{Title},
            Priority      => $Ticket{Priority},
            State         => $Ticket{State},
            Queue         => $Ticket{Queue},
            Owner         => $Ticket{Owner} || 'Unassigned',
            ProductCat3   => $Ticket{DynamicField_ProductCat3} || '-',
            CreateTime    => $Ticket{Created},
            Age           => $Age,
            FirstAssigned => $FirstAssigned{$TicketID} || '-',
            ResolvedTime  => $ResolvedTime{$TicketID} || '-',
            ClosedTime    => $ClosedTime{$TicketID} || '-',
            MTRD          => $MTRD,
            MTTR          => $MTTR,
            };
    }

    # Format filters for display
    my %DisplayFilters = $Self->_FormatFiltersForDisplay(%GetParam);

    # Add AssignedOnly/Unresponded to display filters if set
    if ($AssignedOnly) {
        $DisplayFilters{Owner} = 'Responded (Ever Assigned)';
    }
    if ($Unresponded) {
        $DisplayFilters{Owner} = 'Unresponded (Never Assigned)';
    }
    # Add resolution time to display filters if set
    if ($ResolutionTimeNewerDate || $ResolutionTimeOlderDate) {
        my $ResolutionRange = '';
        if ($ResolutionTimeNewerDate && $ResolutionTimeOlderDate) {
            $ResolutionRange = "$ResolutionTimeNewerDate to $ResolutionTimeOlderDate";
        } elsif ($ResolutionTimeNewerDate) {
            $ResolutionRange = "from $ResolutionTimeNewerDate";
        } else {
            $ResolutionRange = "until $ResolutionTimeOlderDate";
        }
        $DisplayFilters{'Resolution Date'} = $ResolutionRange;
    }
    # Add close time to display filters if set
    if ($TicketCloseTimeNewerDate || $TicketCloseTimeOlderDate) {
        my $CloseRange = '';
        if ($TicketCloseTimeNewerDate && $TicketCloseTimeOlderDate) {
            $CloseRange = "$TicketCloseTimeNewerDate to $TicketCloseTimeOlderDate";
        } elsif ($TicketCloseTimeNewerDate) {
            $CloseRange = "from $TicketCloseTimeNewerDate";
        } else {
            $CloseRange = "until $TicketCloseTimeOlderDate";
        }
        $DisplayFilters{'Close Date'} = $CloseRange;
    }

    # Build title based on filters
    my $PageTitle = 'Report Tickets';
    if ( $DisplayFilters{Priority} ) {
        $PageTitle .= " - $DisplayFilters{Priority}";
    }

    # Build base URL for pagination (exclude Page, Action, SortBy, OrderBy params)
    # SortBy and OrderBy are excluded because:
    # 1. They are passed separately via Data.SortBy/Data.OrderBy for the template
    # 2. They are appended by the template when building sorting links
    # Including them in BaseURL causes duplicate parameters in the URL
    my @BaseURLParts;
    for my $Key ( sort keys %GetParam ) {
        next if $Key eq 'Page';
        next if $Key eq 'Action';
        next if $Key eq 'Subaction';
        next if $Key eq 'SortBy';
        next if $Key eq 'OrderBy';
        # Skip DynamicField_ HASH refs - they're handled separately below
        next if $Key =~ /^DynamicField_/ && ref( $GetParam{$Key} ) eq 'HASH';
        next if !defined $GetParam{$Key};
        next if !ref($GetParam{$Key}) && $GetParam{$Key} eq '';
        if ( ref( $GetParam{$Key} ) eq 'ARRAY' ) {
            push @BaseURLParts, "$Key=" . join( ',', @{ $GetParam{$Key} } );
        }
        else {
            push @BaseURLParts, "$Key=$GetParam{$Key}";
        }
    }
    # Add DynamicField_ parameters using their original URL values
    for my $Key ( sort keys %DynamicFieldOriginal ) {
        my $Value = $DynamicFieldOriginal{$Key};
        # URL-encode the value to handle special characters like /
        $Value = $LayoutObject->LinkEncode($Value);
        push @BaseURLParts, "$Key=$Value";
    }
    # Add AssignedOnly/Unresponded to base URL if set
    if ($AssignedOnly) {
        push @BaseURLParts, "AssignedOnly=1";
    }
    if ($Unresponded) {
        push @BaseURLParts, "Unresponded=1";
    }
    # Add resolution time filters to base URL if set (URL-encode to handle spaces/colons)
    if ($ResolutionTimeNewerDate) {
        push @BaseURLParts, "ResolutionTimeNewerDate=" . $LayoutObject->LinkEncode($ResolutionTimeNewerDate);
    }
    if ($ResolutionTimeOlderDate) {
        push @BaseURLParts, "ResolutionTimeOlderDate=" . $LayoutObject->LinkEncode($ResolutionTimeOlderDate);
    }
    # Add close time filters to base URL if set (URL-encode to handle spaces/colons)
    if ($TicketCloseTimeNewerDate) {
        push @BaseURLParts, "TicketCloseTimeNewerDate=" . $LayoutObject->LinkEncode($TicketCloseTimeNewerDate);
    }
    if ($TicketCloseTimeOlderDate) {
        push @BaseURLParts, "TicketCloseTimeOlderDate=" . $LayoutObject->LinkEncode($TicketCloseTimeOlderDate);
    }
    my $BaseURL = $LayoutObject->{Baselink} . 'Action=AgentReportTickets;' . join( ';', @BaseURLParts );

    # Get filter options for dropdowns
    my %FilterOptions = $Self->_GetFilterOptions();

    # Get current filter values from URL params (handle array refs)
    my %CurrentFilters;
    for my $Key (qw(QueueIDs Priorities StateType StateIDs TypeIDs)) {
        my $Value = $GetParam{$Key} || '';
        if (ref($Value) eq 'ARRAY') {
            $CurrentFilters{$Key} = $Value->[0] || '';  # Use first value for single-select
        } else {
            $CurrentFilters{$Key} = $Value;
        }
    }
    # Also check alternate param names
    $CurrentFilters{QueueIDs} ||= (ref($GetParam{Queues}) eq 'ARRAY' ? $GetParam{Queues}[0] : $GetParam{Queues}) || '';
    # Handle States param - convert state name to ID for dropdown matching
    if (!$CurrentFilters{StateIDs} && $GetParam{States}) {
        my $StateName = ref($GetParam{States}) eq 'ARRAY' ? $GetParam{States}[0] : $GetParam{States};
        if ($StateName) {
            my $StateObject = $Kernel::OM->Get('Kernel::System::State');
            my %StateList = $StateObject->StateList( UserID => 1, Valid => 1 );
            for my $StateID (keys %StateList) {
                if (lc($StateList{$StateID}) eq lc($StateName)) {
                    $CurrentFilters{StateIDs} = $StateID;
                    last;
                }
            }
        }
    }

    # Set AssignmentStatus based on URL params
    if ($AssignedOnly) {
        $CurrentFilters{AssignmentStatus} = 'assigned';
    } elsif ($GetParam{AssignmentStatus}) {
        $CurrentFilters{AssignmentStatus} = $GetParam{AssignmentStatus};
    } elsif ($GetParam{OwnerIDs} && $GetParam{OwnerIDs} eq '99') {
        $CurrentFilters{AssignmentStatus} = 'unassigned';
    } else {
        $CurrentFilters{AssignmentStatus} = '';
    }

    # Prepare template data
    my %Data = (
        Title          => $PageTitle,
        Tickets        => \@Tickets,
        TotalCount     => $TotalCount,
        DisplayFilters => \%DisplayFilters,
        SortBy         => $SortBy,
        OrderBy        => $OrderBy,
        CurrentPage    => $CurrentPage,
        TotalPages     => $TotalPages,
        PageSize       => $PageSize,
        StartItem      => $TotalCount > 0 ? $StartIndex + 1 : 0,
        EndItem        => $TotalCount > 0 ? $StartIndex + scalar(@Tickets) : 0,
        BaseURL        => $BaseURL,
        Source         => $GetParam{Source} || '',
        FilterOptions  => \%FilterOptions,
        CurrentFilters => \%CurrentFilters,
    );

    # Build output
    my $Output = $LayoutObject->Header(
        Title => $PageTitle,
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentReportTickets',
        Data         => \%Data,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _FormatAge {
    my ( $Self, $AgeSeconds ) = @_;

    my $Days  = int( $AgeSeconds / ( 24 * 3600 ) );
    my $Hours = int( ( $AgeSeconds % ( 24 * 3600 ) ) / 3600 );
    my $Mins  = int( ( $AgeSeconds % 3600 ) / 60 );

    if ( $Days > 0 ) {
        return sprintf( "%dd %dh", $Days, $Hours );
    }
    elsif ( $Hours > 0 ) {
        return sprintf( "%dh %dm", $Hours, $Mins );
    }
    else {
        return sprintf( "%dm", $Mins );
    }
}

sub _ExportCSV {
    my ( $Self, %GetParam ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');

    # Remove Subaction from search params
    delete $GetParam{Subaction};

    # Handle AssignedOnly and Unresponded parameters
    my $AssignedOnly = delete $GetParam{AssignedOnly};
    my $Unresponded = delete $GetParam{Unresponded};

    # Handle resolution time filtering (for MTTR breakdown links)
    my $ResolutionTimeNewerDate = delete $GetParam{ResolutionTimeNewerDate};
    my $ResolutionTimeOlderDate = delete $GetParam{ResolutionTimeOlderDate};

    # Handle TicketCloseTime filtering (for closure report drilldown)
    my $TicketCloseTimeNewerDate = delete $GetParam{TicketCloseTimeNewerDate};
    my $TicketCloseTimeOlderDate = delete $GetParam{TicketCloseTimeOlderDate};

    # Handle DynamicFieldUnknown (for "Unknown" dynamic field values)
    my $DynamicFieldUnknown = delete $GetParam{DynamicFieldUnknown} || {};

    # IMPORTANT: When StateType=Closed is used, exclude 'cancelled' state
    # The cancelled state has type_id=3 (closed type) but should never appear in closure reports
    if ( $GetParam{StateType} && $GetParam{StateType} eq 'Closed' ) {
        my $StateObject = $Kernel::OM->Get('Kernel::System::State');
        my %StateList = $StateObject->StateList( UserID => 1, Valid => 1 );

        # Get state IDs for all closed-type states EXCEPT cancelled
        my @ClosedStateIDs;
        for my $StateID ( keys %StateList ) {
            my %State = $StateObject->StateGet( ID => $StateID );
            if ( $State{TypeName} eq 'closed' && lc($State{Name}) ne 'cancelled' ) {
                push @ClosedStateIDs, $StateID;
            }
        }

        # Replace StateType with explicit StateIDs to exclude cancelled
        if (@ClosedStateIDs) {
            delete $GetParam{StateType};
            $GetParam{StateIDs} = \@ClosedStateIDs;
        }
    }

    # Search tickets
    my @TicketIDs = $TicketObject->TicketSearch(
        Result   => 'ARRAY',
        SortBy   => $GetParam{SortBy} || 'Age',
        OrderBy  => $GetParam{OrderBy} || 'Down',
        Limit    => 100000,
        UserID   => $Self->{UserID},
        %GetParam,
    );

    # If AssignedOnly is set, filter to tickets that are CURRENTLY assigned
    if ( $AssignedOnly && @TicketIDs ) {
        my $TicketIDList = join(',', @TicketIDs);

        my @FilteredTicketIDs;
        my $SQL = qq{
            SELECT id FROM ticket
            WHERE id IN ($TicketIDList)
            AND user_id NOT IN (1, 99)
        };

        if ($DBObject->Prepare(SQL => $SQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                push @FilteredTicketIDs, $Row[0];
            }
        }

        my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
        @TicketIDs = grep { $FilteredSet{$_} } @TicketIDs;
    }

    # If Unresponded is set, filter to tickets that are CURRENTLY unassigned
    if ( $Unresponded && @TicketIDs ) {
        my $TicketIDList = join(',', @TicketIDs);

        my @FilteredTicketIDs;
        my $SQL = qq{
            SELECT id FROM ticket
            WHERE id IN ($TicketIDList)
            AND user_id IN (1, 99)
        };

        if ($DBObject->Prepare(SQL => $SQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                push @FilteredTicketIDs, $Row[0];
            }
        }

        my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
        @TicketIDs = grep { $FilteredSet{$_} } @TicketIDs;
    }

    # If resolution time filters are set, filter to tickets resolved within the date range
    # This matches the MTTR breakdown logic - tickets reopened and re-resolved are counted in the correct period
    if ( ($ResolutionTimeNewerDate || $ResolutionTimeOlderDate) && @TicketIDs ) {
        my $TicketIDList = join(',', @TicketIDs);

        # Build date range conditions
        my $StartDate = $ResolutionTimeNewerDate || '1970-01-01 00:00:00';
        my $EndDate = $ResolutionTimeOlderDate || '2099-12-31 23:59:59';

        # Find tickets that have a resolution (StateUpdate to closed state) within the date range
        # OR tickets currently in closed state with change_time in range (fallback for no history)
        my $SQL = qq{
            WITH first_resolution_in_range AS (
                SELECT
                    th.ticket_id,
                    MIN(th.create_time) as resolved_time
                FROM ticket_history th
                JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
                WHERE th.ticket_id IN ($TicketIDList)
                  AND th.history_type_id = 27
                  AND ts_hist.type_id = 3
                  AND ts_hist.name != 'cancelled'
                  AND th.create_time >= ?
                  AND th.create_time <= ?
                GROUP BY th.ticket_id
            )
            SELECT DISTINCT t.id as ticket_id
            FROM ticket t
            JOIN ticket_state ts ON t.ticket_state_id = ts.id
            LEFT JOIN first_resolution_in_range fr ON t.id = fr.ticket_id
            WHERE t.id IN ($TicketIDList)
              AND (
                  fr.ticket_id IS NOT NULL
                  OR (ts.type_id = 3 AND ts.name != 'cancelled'
                      AND t.change_time >= ? AND t.change_time <= ?)
              )
        };

        my @FilteredTicketIDs;
        if ($DBObject->Prepare(SQL => $SQL, Bind => [\$StartDate, \$EndDate, \$StartDate, \$EndDate])) {
            while (my @Row = $DBObject->FetchrowArray()) {
                push @FilteredTicketIDs, $Row[0];
            }
        }

        my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
        @TicketIDs = grep { $FilteredSet{$_} } @TicketIDs;
    }

    # If TicketCloseTime filters are set, filter to tickets that were CLOSED within the date range
    if ( ($TicketCloseTimeNewerDate || $TicketCloseTimeOlderDate) && @TicketIDs ) {
        my $TicketIDList = join(',', @TicketIDs);

        my $StartDate = $TicketCloseTimeNewerDate || '1970-01-01 00:00:00';
        my $EndDate = $TicketCloseTimeOlderDate || '2099-12-31 23:59:59';

        my $SQL = qq{
            SELECT DISTINCT th.ticket_id
            FROM ticket_history th
            JOIN ticket_state ts_hist ON th.state_id = ts_hist.id
            WHERE th.ticket_id IN ($TicketIDList)
              AND th.history_type_id = 27
              AND ts_hist.name = 'closed'
              AND th.create_time >= ?
              AND th.create_time <= ?
        };

        my @FilteredTicketIDs;
        if ($DBObject->Prepare(SQL => $SQL, Bind => [\$StartDate, \$EndDate])) {
            while (my @Row = $DBObject->FetchrowArray()) {
                push @FilteredTicketIDs, $Row[0];
            }
        }

        my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
        @TicketIDs = grep { $FilteredSet{$_} } @TicketIDs;
    }

    # If DynamicFieldUnknown is set, filter to tickets where the dynamic field is NULL or empty
    if ( %{$DynamicFieldUnknown} && @TicketIDs ) {
        my $TicketIDList = join(',', @TicketIDs);

        for my $FieldName ( keys %{$DynamicFieldUnknown} ) {
            # Get the dynamic field ID
            my $FieldIDSQL = q{SELECT id FROM dynamic_field WHERE name = ?};
            my $FieldID;

            if ( $DBObject->Prepare( SQL => $FieldIDSQL, Bind => [\$FieldName] ) ) {
                while ( my @Row = $DBObject->FetchrowArray() ) {
                    $FieldID = $Row[0];
                }
            }

            next if !$FieldID;

            # Find tickets where the dynamic field value is NULL or empty
            my $SQL = qq{
                SELECT t.id
                FROM ticket t
                LEFT JOIN dynamic_field_value dfv ON dfv.object_id = t.id AND dfv.field_id = ?
                WHERE t.id IN ($TicketIDList)
                  AND (dfv.value_text IS NULL OR dfv.value_text = '')
            };

            my @FilteredTicketIDs;
            if ( $DBObject->Prepare( SQL => $SQL, Bind => [\$FieldID] ) ) {
                while ( my @Row = $DBObject->FetchrowArray() ) {
                    push @FilteredTicketIDs, $Row[0];
                }
            }

            my %FilteredSet = map { $_ => 1 } @FilteredTicketIDs;
            @TicketIDs = grep { $FilteredSet{$_} } @TicketIDs;
        }
    }

    # Get FirstAssigned, ResolvedTime, and ClosedTime
    my %FirstAssigned;
    my %ResolvedTime;
    my %ClosedTime;

    if (@TicketIDs) {
        my $TicketIDList = join(',', @TicketIDs);

        # Get first assignment time:
        # - If ticket was created with owner assigned, use create_time (MTRD = 0)
        # - If ticket was assigned later via OwnerUpdate, use first OwnerUpdate time
        my $AssignedSQL = qq{
            SELECT
                t.id as ticket_id,
                COALESCE(
                    (SELECT MIN(th.create_time)
                     FROM ticket_history th
                     WHERE th.ticket_id = t.id
                       AND th.history_type_id = 23
                       AND th.owner_id NOT IN (1, 99)),
                    CASE WHEN t.user_id NOT IN (1, 99) THEN t.create_time ELSE NULL END
                ) as first_assigned
            FROM ticket t
            WHERE t.id IN ($TicketIDList)
        };

        if ($DBObject->Prepare(SQL => $AssignedSQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                $FirstAssigned{$Row[0]} = $Row[1];
            }
        }

        my $ResolvedSQL = qq{
            SELECT th.ticket_id, MIN(th.create_time) as resolved_time
            FROM ticket_history th
            JOIN ticket_state ts ON th.state_id = ts.id
            WHERE th.ticket_id IN ($TicketIDList)
              AND th.history_type_id = 27
              AND ts.type_id = 3
            GROUP BY th.ticket_id
        };

        if ($DBObject->Prepare(SQL => $ResolvedSQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                $ResolvedTime{$Row[0]} = $Row[1];
            }
        }

        # Get closed time (first time ticket moved specifically to 'closed' state, not 'resolved')
        my $ClosedSQL = qq{
            SELECT th.ticket_id, MIN(th.create_time) as closed_time
            FROM ticket_history th
            JOIN ticket_state ts ON th.state_id = ts.id
            WHERE th.ticket_id IN ($TicketIDList)
              AND th.history_type_id = 27
              AND ts.name = 'closed'
            GROUP BY th.ticket_id
        };

        if ($DBObject->Prepare(SQL => $ClosedSQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                $ClosedTime{$Row[0]} = $Row[1];
            }
        }
    }

    # Build CSV content
    my @CSVLines;
    push @CSVLines, "Ticket#,Title,Queue,Priority,State,Owner,Age,Created,First Assigned,Resolved,Closed";

    for my $TicketID (@TicketIDs) {
        my %Ticket = $TicketObject->TicketGet(
            TicketID      => $TicketID,
            DynamicFields => 0,
            UserID        => $Self->{UserID},
        );

        my $CreateSystemTime = $TimeObject->TimeStamp2SystemTime(String => $Ticket{Created});
        my $CurrentTime = $TimeObject->SystemTime();
        my $AgeSeconds  = $CurrentTime - $CreateSystemTime;
        my $Age = $Self->_FormatAge($AgeSeconds);

        # Escape CSV fields
        my $Title = $Ticket{Title} || '';
        $Title =~ s/"/""/g;

        push @CSVLines, sprintf(
            '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"',
            $Ticket{TicketNumber},
            $Title,
            $Ticket{Queue} || '',
            $Ticket{Priority} || '',
            $Ticket{State} || '',
            $Ticket{Owner} || 'Unassigned',
            $Age,
            $Ticket{Created} || '',
            $FirstAssigned{$TicketID} || '',
            $ResolvedTime{$TicketID} || '',
            $ClosedTime{$TicketID} || '',
        );
    }

    my $CSVContent = join("\n", @CSVLines);

    # Generate filename with timestamp
    my $Filename = 'report_tickets_' . $TimeObject->CurrentTimestamp();
    $Filename =~ s/[:\s]/_/g;
    $Filename .= '.csv';

    return $LayoutObject->Attachment(
        Filename    => $Filename,
        ContentType => 'text/csv; charset=utf-8',
        Content     => $CSVContent,
        Type        => 'attachment',
    );
}

sub _FormatFiltersForDisplay {
    my ( $Self, %GetParam ) = @_;

    my %FilterLabels = (
        Priorities     => 'Priority',
        States         => 'State',
        Queues         => 'Queue',
        OwnerIDs       => 'Owner',
        ResponsibleIDs => 'Responsible',
        Types          => 'Type',
        StateType      => 'State Type',
        ServiceIDs     => 'Service',
        SLAIDs         => 'SLA',
    );

    my %DisplayFilters;
    for my $Key ( keys %GetParam ) {
        next if !$GetParam{$Key};
        next if $Key =~ /^(SortBy|OrderBy|Limit|UserID|Result)$/;

        my $Value = $GetParam{$Key};
        next if ref($Value) eq 'ARRAY' && !@{$Value};

        my $Label = $FilterLabels{$Key} || $Key;

        # Format array values
        if ( ref($Value) eq 'ARRAY' ) {
            $DisplayFilters{$Label} = join( ', ', @{$Value} );
        }
        else {
            # Special handling for OwnerIDs
            if ( $Key eq 'OwnerIDs' && $Value eq '99' ) {
                $DisplayFilters{$Label} = 'Unassigned';
            }
            else {
                $DisplayFilters{$Label} = $Value;
            }
        }
    }

    return %DisplayFilters;
}

sub _GetFilterOptions {
    my ( $Self, %Param ) = @_;

    my $PriorityObject = $Kernel::OM->Get('Kernel::System::Priority');
    my $StateObject    = $Kernel::OM->Get('Kernel::System::State');
    my $DBObject       = $Kernel::OM->Get('Kernel::System::DB');

    my %FilterOptions;

    # Get Priorities
    my %Priorities = $PriorityObject->PriorityList( Valid => 1 );
    my @PriorityList;
    for my $PriorityID ( sort { $a <=> $b } keys %Priorities ) {
        push @PriorityList, {
            ID   => "$PriorityID",
            Name => $Priorities{$PriorityID},
        };
    }
    $FilterOptions{Priorities} = \@PriorityList;

    # Get States
    my %States = $StateObject->StateList( UserID => 1, Valid => 1 );
    my @StateList;
    for my $StateID ( sort { $States{$a} cmp $States{$b} } keys %States ) {
        push @StateList, {
            ID   => "$StateID",
            Name => $States{$StateID},
        };
    }
    $FilterOptions{States} = \@StateList;

    # Get State Types
    $FilterOptions{StateTypes} = [
        { ID => 'Open',   Name => 'Open' },
        { ID => 'Closed', Name => 'Closed' },
    ];

    # Get Types
    my @TypeList;
    my $TypeSQL = q{
        SELECT id, name FROM ticket_type WHERE valid_id = 1 ORDER BY name
    };
    if ( $DBObject->Prepare( SQL => $TypeSQL ) ) {
        while ( my @Row = $DBObject->FetchrowArray() ) {
            push @TypeList, {
                ID   => "$Row[0]",
                Name => $Row[1],
            };
        }
    }
    $FilterOptions{Types} = \@TypeList;

    return %FilterOptions;
}

1;
