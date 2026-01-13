# --
# Copyright (C) 2025 MSST, https://msst.com/
# Based on Znuny GmbH AgentTicketEscalationView
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Modules::AgentTicketEscalationView;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::Modules::AgentTicketEscalationView - Custom escalation view for MSI-escalated incidents

=head1 DESCRIPTION

Shows only incidents that have been escalated to MSI ServiceNow (MSITicketNumber populated).
Replaces core escalation view which shows SLA-based escalation.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get session object
    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');

    # store last queue screen
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenOverview',
        Value     => $Self->{RequestedURL},
    );

    # store last screen
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenView',
        Value     => $Self->{RequestedURL},
    );

    # get user object
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');

    # get filters stored in the user preferences
    my %Preferences = $UserObject->GetPreferences(
        UserID => $Self->{UserID},
    );
    my $StoredFiltersKey = 'UserStoredFilterColumns-' . $Self->{Action};
    my $JSONObject       = $Kernel::OM->Get('Kernel::System::JSON');
    my $StoredFilters    = $JSONObject->Decode(
        Data => $Preferences{$StoredFiltersKey},
    );

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # delete stored filters if needed
    if ( $ParamObject->GetParam( Param => 'DeleteFilters' ) ) {
        $StoredFilters = {};
    }

    # get the column filters from the web request or user preferences
    my %ColumnFilter;
    my %GetColumnFilter;
    COLUMNNAME:
    for my $ColumnName (
        qw(Owner Responsible State Queue Priority Type Lock Service SLA CustomerID CustomerUserID)
        )
    {
        # get column filter from web request
        my $FilterValue = $ParamObject->GetParam( Param => 'ColumnFilter' . $ColumnName )
            || '';

        # if filter is not present in the web request, try with the user preferences
        if ( $FilterValue eq '' ) {
            if ( $ColumnName eq 'CustomerID' ) {
                $FilterValue = $StoredFilters->{$ColumnName}->[0] || '';
            }
            elsif ( $ColumnName eq 'CustomerUserID' ) {
                $FilterValue = $StoredFilters->{CustomerUserLogin}->[0] || '';
            }
            else {
                $FilterValue = $StoredFilters->{ $ColumnName . 'IDs' }->[0] || '';
            }
        }
        next COLUMNNAME if $FilterValue eq '';
        next COLUMNNAME if $FilterValue eq 'DeleteFilter';

        if ( $ColumnName eq 'CustomerID' ) {
            push @{ $ColumnFilter{$ColumnName} }, $FilterValue;
            push @{ $ColumnFilter{ $ColumnName . 'Raw' } }, $FilterValue;
            $GetColumnFilter{$ColumnName} = $FilterValue;
        }
        elsif ( $ColumnName eq 'CustomerUserID' ) {
            push @{ $ColumnFilter{CustomerUserLogin} },    $FilterValue;
            push @{ $ColumnFilter{CustomerUserLoginRaw} }, $FilterValue;
            $GetColumnFilter{$ColumnName} = $FilterValue;
        }
        else {
            push @{ $ColumnFilter{ $ColumnName . 'IDs' } }, $FilterValue;
            $GetColumnFilter{$ColumnName} = $FilterValue;
        }
    }

    # get all dynamic fields
    $Self->{DynamicField} = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid      => 1,
        ObjectType => ['Ticket'],
    );

    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
        next DYNAMICFIELD if !$DynamicFieldConfig->{Name};

        # get filter from web request
        my $FilterValue = $ParamObject->GetParam(
            Param => 'ColumnFilterDynamicField_' . $DynamicFieldConfig->{Name}
        );

        # if no filter from web request, try from user preferences
        if ( !defined $FilterValue || $FilterValue eq '' ) {
            $FilterValue = $StoredFilters->{ 'DynamicField_' . $DynamicFieldConfig->{Name} }->{Equals};
        }

        next DYNAMICFIELD if !defined $FilterValue;
        next DYNAMICFIELD if $FilterValue eq '';
        next DYNAMICFIELD if $FilterValue eq 'DeleteFilter';

        $ColumnFilter{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = {
            Equals => $FilterValue,
        };
        $GetColumnFilter{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = $FilterValue;
    }

    # starting with page ...
    my $Refresh = '';
    if ( $Self->{UserRefreshTime} ) {
        $Refresh = 60 * $Self->{UserRefreshTime};
    }

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $Output;
    if ( $Self->{Subaction} ne 'AJAXFilterUpdate' ) {
        $Output = $LayoutObject->Header(
            Refresh => $Refresh,
        );
        $Output .= $LayoutObject->NavigationBar();
    }

    # Notify if there are tickets which are not updated.
    $Output .= $LayoutObject->NotifyNonUpdatedTickets() // '';

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $Config       = $ConfigObject->Get("Ticket::Frontend::$Self->{Action}");

    # get params
    my $SortBy = $ParamObject->GetParam( Param => 'SortBy' )
        || $Config->{'SortBy::Default'}
        || 'Priority';
    my $OrderBy = $ParamObject->GetParam( Param => 'OrderBy' )
        || $Config->{'Order::Default'}
        || 'Down';

    # Get Incident Type ID dynamically
    my $TypeObject = $Kernel::OM->Get('Kernel::System::Type');
    my %TypeList = $TypeObject->TypeList();
    my $IncidentTypeID;
    for my $TypeID ( keys %TypeList ) {
        if ( $TypeList{$TypeID} eq 'Incident' ) {
            $IncidentTypeID = $TypeID;
            last;
        }
    }

    # Build base search parameters for MSI-escalated incidents
    my %BaseSearch = (
        # MSI Escalation Filter - show only tickets escalated to MSI
        'DynamicField_MSITicketNumber' => {
            Empty => 0,  # NOT empty - must have MSI ticket number
        },
        # Only Incident type
        TypeIDs => $IncidentTypeID ? [$IncidentTypeID] : [2],  # Fallback to 2 if lookup fails
        # Only open states (exclude closed/merged)
        StateType => ['new', 'open', 'pending reminder', 'pending auto'],
        # User permissions
        OrderBy    => $OrderBy,
        SortBy     => $SortBy,
        UserID     => $Self->{UserID},
        Permission => $Config->{'TicketPermission'} || 'ro',
    );

    # Single filter for all MSI-escalated tickets
    my %Filters = (
        All => {
            Name   => Translatable('All'),
            Prio   => 1000,
            Search => \%BaseSearch,
        },
    );

    my $Filter = $ParamObject->GetParam( Param => 'Filter' ) || 'All';

    # check if filter is valid
    if ( !$Filters{$Filter} ) {
        $LayoutObject->FatalError(
            Message => $LayoutObject->{LanguageObject}->Translate( 'Invalid Filter: %s!', $Filter ),
        );
    }

    # Get personal page shown count
    my $View = $ParamObject->GetParam( Param => 'View' ) || '';
    my $PageShownPreferencesKey = 'UserTicketOverview' . $View . 'PageShown';
    my $PageShown = $Self->{$PageShownPreferencesKey} || 25;

    # Get StartHit parameter for pagination
    my $StartHit = $ParamObject->GetParam( Param => 'StartHit' ) || 1;

    # do shown tickets lookup
    my $Limit         = 10_000;
    my $OriginalLimit = 10_000;

    my $ElementChanged = $ParamObject->GetParam( Param => 'ElementChanged' ) || '';
    my $HeaderColumn   = $ElementChanged;
    $HeaderColumn =~ s{\A ColumnFilter }{}msxg;
    my @OriginalViewableTickets;
    my @ViewableTickets;
    my $CountTotal = 0;

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # get ticket values
    if (
        !IsStringWithData($HeaderColumn)
        || (
            IsStringWithData($HeaderColumn)
            && (
                $ConfigObject->Get('OnlyValuesOnTicket') ||
                $HeaderColumn eq 'CustomerID' ||
                $HeaderColumn eq 'CustomerUserID'
            )
        )
        )
    {

        @OriginalViewableTickets = $TicketObject->TicketSearch(
            %{ $Filters{$Filter}->{Search} },
            Limit  => $OriginalLimit,
            Result => 'ARRAY',
        );

        # Get total count for pagination
        $CountTotal = $TicketObject->TicketSearch(
            %{ $Filters{$Filter}->{Search} },
            %ColumnFilter,
            Result => 'COUNT',
        );

        @ViewableTickets = $TicketObject->TicketSearch(
            %{ $Filters{$Filter}->{Search} },
            %ColumnFilter,
            Result => 'ARRAY',
            Limit  => $StartHit + $PageShown - 1,
        );
    }

    if ( $Self->{Subaction} eq 'AJAXFilterUpdate' ) {

        my $FilterContent = $LayoutObject->TicketListShow(
            FilterContentOnly   => 1,
            HeaderColumn        => $HeaderColumn,
            ElementChanged      => $ElementChanged,
            OriginalTicketIDs   => \@OriginalViewableTickets,
            Action              => 'AgentTicketEscalationView',
            Env                 => $Self,
            View                => $View,
            EnableColumnFilters => 1,
        );

        if ( !$FilterContent ) {
            $LayoutObject->FatalError(
                Message => $LayoutObject->{LanguageObject}
                    ->Translate( 'Can\'t get filter content data of %s!', $HeaderColumn ),
            );
        }

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $FilterContent,
            Type        => 'inline',
            NoCache     => 1,
        );
    }
    else {

        # store column filters
        my $StoredFilters = \%ColumnFilter;

        my $StoredFiltersKey = 'UserStoredFilterColumns-' . $Self->{Action};
        $UserObject->SetPreferences(
            UserID => $Self->{UserID},
            Key    => $StoredFiltersKey,
            Value  => $JSONObject->Encode( Data => $StoredFilters ),
        );
    }

    # Build navigation bar filter with ticket count
    my %NavBarFilter;
    my @FilterTickets = $TicketObject->TicketSearch(
        %{ $Filters{All}->{Search} },
        %ColumnFilter,
        Result => 'ARRAY',
        Limit  => $Limit,
    );
    $NavBarFilter{ $Filters{All}->{Prio} } = {
        Count  => scalar @FilterTickets,
        Filter => 'All',
        %{ $Filters{All} },
    };

    my $ColumnFilterLink = '';
    COLUMNNAME:
    for my $ColumnName ( sort keys %GetColumnFilter ) {
        next COLUMNNAME if !$ColumnName;
        next COLUMNNAME if !$GetColumnFilter{$ColumnName};
        $ColumnFilterLink
            .= ';' . $LayoutObject->Ascii2Html( Text => 'ColumnFilter' . $ColumnName )
            . '=' . $LayoutObject->LinkEncode( $GetColumnFilter{$ColumnName} );
    }

    # show ticket's
    my $LinkPage = 'Filter='
        . $LayoutObject->Ascii2Html( Text => $Filter )
        . ';View=' . $LayoutObject->Ascii2Html( Text => $View )
        . ';SortBy=' . $LayoutObject->Ascii2Html( Text => $SortBy )
        . ';OrderBy=' . $LayoutObject->Ascii2Html( Text => $OrderBy )
        . $ColumnFilterLink
        . ';';
    my $LinkSort = 'Filter='
        . $LayoutObject->Ascii2Html( Text => $Filter )
        . ';View=' . $LayoutObject->Ascii2Html( Text => $View )
        . $ColumnFilterLink
        . ';';
    my $LinkFilter = 'SortBy=' . $LayoutObject->Ascii2Html( Text => $SortBy )
        . ';OrderBy=' . $LayoutObject->Ascii2Html( Text => $OrderBy )
        . ';View=' . $LayoutObject->Ascii2Html( Text => $View )
        . ';';

    my $LastColumnFilter = $ParamObject->GetParam( Param => 'LastColumnFilter' ) || '';

    if ( !$LastColumnFilter && $ColumnFilterLink ) {

        # is planned to have a link to go back here
        $LastColumnFilter = 1;
    }

    # MSSTLITE-345: Query cooldown tickets and output bulk update toolbar
    my %CooldownData = ();  # ticket_id => update_time
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Query tickets in cooldown (PostgreSQL syntax)
    my $Success = $DBObject->Prepare(
        SQL => "SELECT ticket_id, update_time FROM bulk_update_cooldown WHERE cooldown_until > NOW()",
    );

    if ($Success) {
        while ( my @Row = $DBObject->FetchrowArray() ) {
            my $TicketID = $Row[0];
            my $UpdateTime = $Row[1];

            # Strip microseconds from timestamp (PostgreSQL TIMESTAMP includes them)
            $UpdateTime =~ s/\.\d+$//;

            # Format timestamp
            my $FormattedTime = $LayoutObject->{LanguageObject}->FormatTimeString(
                $UpdateTime,
                'DateFormat',
                'NoSeconds',
            );

            $CooldownData{$TicketID} = $FormattedTime;
        }
    }

    # Convert cooldown data to JSON object
    my $CooldownJSON = $JSONObject->Encode( Data => \%CooldownData );

    # Output bulk update toolbar HTML (BEFORE TicketListShow)
    my $BulkUpdateToolbar = qq{
<div class="EscalationViewBulkUpdateToolbar">
    <button type="button" id="BulkUpdateButton" class="BulkUpdateButton" disabled>Bulk Update</button>
</div>
<div id="BulkUpdateCooldownData" data-cooldown-tickets='$CooldownJSON' style="display:none;"></div>
};

    $Output .= $BulkUpdateToolbar;

    # NOTE: JavaScript initialization is handled by Core.Init.RegisterNamespace
    # Do NOT call Init() here - it will be called automatically when DOM is ready

    $Output .= $LayoutObject->TicketListShow(
        TicketIDs         => \@ViewableTickets,
        OriginalTicketIDs => \@OriginalViewableTickets,
        GetColumnFilter   => \%GetColumnFilter,
        LastColumnFilter  => $LastColumnFilter,
        Action            => 'AgentTicketEscalationView',
        RequestedURL      => $Self->{RequestedURL},

        Total    => $CountTotal,
        StartHit => $StartHit,

        View => $View,

        Filter     => $Filter,
        Filters    => \%NavBarFilter,
        LinkFilter => $LinkFilter,

        TitleName  => Translatable('MSI Escalated Incidents'),
        TitleValue => $Filters{$Filter}->{Name},
        Bulk       => 0,  # MSSTLITE-345: Disable built-in bulk action

        Env      => $Self,
        LinkPage => $LinkPage,
        LinkSort => $LinkSort,

        OrderBy             => $OrderBy,
        SortBy              => $SortBy,
        EnableColumnFilters => 1,
        ColumnFilterForm    => {
            Filter => $Filter || '',
        },

        # do not print the result earlier, but return complete content
        Output => 1,
    );

    $Output .= $LayoutObject->Footer();
    return $Output;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST Lite project.

This software comes with ABSOLUTELY NO WARRANTY.

=cut
