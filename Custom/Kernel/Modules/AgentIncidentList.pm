# --
# Copyright (C) 2025 MSST Solutions
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AgentIncidentList;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

use Kernel::Language qw(Translatable);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject    = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $TicketObject    = $Kernel::OM->Get('Kernel::System::Ticket');
    my $SessionObject   = $Kernel::OM->Get('Kernel::System::AuthSession');
    my $UserObject      = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject     = $Kernel::OM->Get('Kernel::System::Group');
    my $CustomerObject  = $Kernel::OM->Get('Kernel::System::CustomerUser');
    my $ConfigObject    = $Kernel::OM->Get('Kernel::Config');
    my $TimeObject      = $Kernel::OM->Get('Kernel::System::Time');
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $ParamObject     = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $IncidentObject  = $Kernel::OM->Get('Kernel::System::Incident');
    
    # Get parameters
    my %GetParam;
    for my $Param (qw(SortBy OrderBy StartHit)) {
        $GetParam{$Param} = $ParamObject->GetParam( Param => $Param ) || '';
    }
    
    # Store last screen
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenView',
        Value     => $Self->{RequestedURL},
    );
    
    # Set default values
    $GetParam{SortBy}  ||= 'TicketNumber';
    $GetParam{OrderBy} ||= 'Down';
    
    # Build output
    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();
    
    # Get all incident type tickets
    my @TicketIDs = $TicketObject->TicketSearch(
        Types => [
            'Incident',
            'Incident::Critical',
            'Incident::Major',
            'Incident::Minor',
        ],
        UserID => $Self->{UserID},
        Result => 'ARRAY',
        Permission => 'ro',
        Limit => 10000,
    );
    
    # Prepare incident data
    my @IncidentList;
    my %StateColors = (
        'New'         => 'new',
        'Assigned'    => 'open',
        'In Progress' => 'open',
        'Resolved'    => 'pending reminder',
        'Closed'      => 'closed successful',
        'Cancelled'   => 'closed unsuccessful',
    );
    
    for my $TicketID (@TicketIDs) {
        # Get ticket data
        my %Ticket = $TicketObject->TicketGet(
            TicketID      => $TicketID,
            DynamicFields => 1,
            UserID        => $Self->{UserID},
        );
        
        # Skip if not an incident
        next if !$Ticket{DynamicField_IncidentNumber};
        
        # Get incident data from database
        my $IncidentData = $IncidentObject->IncidentGet(
            TicketID => $TicketID,
        );
        
        if ($IncidentData) {
            # Merge ticket and incident data
            $IncidentData->{TicketID} = $TicketID;
            $IncidentData->{TicketNumber} = $Ticket{TicketNumber};
            $IncidentData->{Title} = $Ticket{Title};
            $IncidentData->{Age} = $Ticket{Age};
            
            # Format dates
            if ($IncidentData->{opened}) {
                my $OpenedTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String => $IncidentData->{opened},
                    }
                );
                $IncidentData->{OpenedString} = $OpenedTimeObject ? $OpenedTimeObject->ToString() : '';
            }
            
            if ($IncidentData->{updated}) {
                my $UpdatedTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String => $IncidentData->{updated},
                    }
                );
                $IncidentData->{UpdatedString} = $UpdatedTimeObject ? $UpdatedTimeObject->ToString() : '';
            }
            
            # Get state color
            $IncidentData->{StateColor} = $StateColors{$IncidentData->{state}} || 'open';
            
            push @IncidentList, $IncidentData;
        }
    }
    
    # Sort incidents
    if ($GetParam{SortBy} eq 'IncidentNumber') {
        if ($GetParam{OrderBy} eq 'Up') {
            @IncidentList = sort { $a->{incident_number} cmp $b->{incident_number} } @IncidentList;
        } else {
            @IncidentList = sort { $b->{incident_number} cmp $a->{incident_number} } @IncidentList;
        }
    }
    elsif ($GetParam{SortBy} eq 'Priority') {
        my %PriorityOrder = ( P1 => 1, P2 => 2, P3 => 3, P4 => 4 );
        if ($GetParam{OrderBy} eq 'Up') {
            @IncidentList = sort { 
                ($PriorityOrder{$a->{priority}} || 5) <=> ($PriorityOrder{$b->{priority}} || 5) 
            } @IncidentList;
        } else {
            @IncidentList = sort { 
                ($PriorityOrder{$b->{priority}} || 5) <=> ($PriorityOrder{$a->{priority}} || 5) 
            } @IncidentList;
        }
    }
    elsif ($GetParam{SortBy} eq 'State') {
        if ($GetParam{OrderBy} eq 'Up') {
            @IncidentList = sort { $a->{state} cmp $b->{state} } @IncidentList;
        } else {
            @IncidentList = sort { $b->{state} cmp $a->{state} } @IncidentList;
        }
    }
    elsif ($GetParam{SortBy} eq 'Created') {
        if ($GetParam{OrderBy} eq 'Up') {
            @IncidentList = sort { $a->{opened} cmp $b->{opened} } @IncidentList;
        } else {
            @IncidentList = sort { $b->{opened} cmp $a->{opened} } @IncidentList;
        }
    }
    elsif ($GetParam{SortBy} eq 'Updated') {
        if ($GetParam{OrderBy} eq 'Up') {
            @IncidentList = sort { ($a->{updated} || '') cmp ($b->{updated} || '') } @IncidentList;
        } else {
            @IncidentList = sort { ($b->{updated} || '') cmp ($a->{updated} || '') } @IncidentList;
        }
    }
    else {  # Default to TicketNumber
        if ($GetParam{OrderBy} eq 'Up') {
            @IncidentList = sort { $a->{TicketNumber} <=> $b->{TicketNumber} } @IncidentList;
        } else {
            @IncidentList = sort { $b->{TicketNumber} <=> $a->{TicketNumber} } @IncidentList;
        }
    }
    
    # Pass data to template
    $LayoutObject->Block(
        Name => 'IncidentList',
        Data => {
            %GetParam,
            IncidentCount => scalar @IncidentList,
        },
    );
    
    # Show incidents
    for my $Incident (@IncidentList) {
        $LayoutObject->Block(
            Name => 'IncidentRow',
            Data => {
                %{$Incident},
                %GetParam,
            },
        );
    }
    
    # Generate pagination
    my $StartHit = $GetParam{StartHit} || 1;
    my $PageSize = 50;
    my $TotalHits = scalar @IncidentList;
    
    if ($TotalHits > $PageSize) {
        $LayoutObject->Block(
            Name => 'PageNavBar',
            Data => {
                Limit     => $PageSize,
                StartHit  => $StartHit,
                TotalHits => $TotalHits,
                %GetParam,
            },
        );
    }
    
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AgentIncidentList',
        Data         => {
            %GetParam,
        },
    );
    
    $Output .= $LayoutObject->Footer();
    
    return $Output;
}

1;