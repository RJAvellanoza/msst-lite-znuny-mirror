# --
# Copyright (C) 2024 Radiant Digital, radiant.digital
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::GenericInterface::Operation::Incident::IncidentGet;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsStringWithData IsHashRefWithData IsArrayRefWithData);

use parent qw(
    Kernel::GenericInterface::Operation::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Operation::Incident::IncidentGet - GenericInterface Incident Get Operation backend

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

perform IncidentGet Operation. This will retrieve incident details.

    my $Result = $OperationObject->Run(
        Data => {
            SessionID => '1234567890123456',  # Optional, if not provided UserLogin and Password must be provided
            UserLogin => 'some agent',       # Optional, if not provided SessionID must be provided  
            Password  => 'some password',    # Optional, if not provided SessionID must be provided

            IncidentID => 123,               # Required - Either IncidentID or TicketID or IncidentNumber
            TicketID   => 456,               # Alternative to IncidentID
            IncidentNumber => 'INC00001',    # Alternative to IncidentID/TicketID
            
            IncludeAttachments => 1,         # Optional - Include attachments in response
            IncludeArticles    => 1,         # Optional - Include articles/notes in response
        },
    );

    $Result = {
        Success => 1,                       # 0 or 1
        ErrorMessage => '',                 # In case of an error
        Data => {
            IncidentID => 123,
            TicketID   => 456,
            TicketNumber => 'INC00001',
            Incident => {
                # All incident fields
            },
            Articles => [
                # Article/note data if requested
            ],
            Attachments => [
                # Attachment data if requested
            ],
            Error => {
                ErrorCode    => 'IncidentGet.InvalidParameter',
                ErrorMessage => 'Incident not found!',
            },
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !IsHashRefWithData( $Param{Data} ) ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentGet.MissingParameter',
            ErrorMessage => "IncidentGet: The request is empty!",
        );
    }

    # Check authentication
    my ($UserID, $UserType) = $Self->Auth(
        Data => $Param{Data},
    );
    
    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentGet.AuthFail',
            ErrorMessage => "IncidentGet: Authorization failing!",
        );
    }

    # Get incident/ticket ID
    my $TicketID;
    my $IncidentID;
    
    # URL path parameter comes through $Param{Data}->{IncidentID} for GET requests
    my $URLParam = $Param{Data}->{IncidentID};
    
    if ( $URLParam ) {
        if ( $URLParam =~ /^INC-/ ) {
            # This is an incident number from URL path, look it up
            my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
            $TicketID = $TicketObject->TicketIDLookup(
                TicketNumber => $URLParam,
            );
            $IncidentID = $TicketID if $TicketID;
        }
        else {
            # This is a numeric incident ID
            $IncidentID = $URLParam;
            $TicketID = $IncidentID;
        }
    }
    elsif ( $Param{Data}->{TicketID} ) {
        $TicketID = $Param{Data}->{TicketID};
        $IncidentID = $TicketID;
    }
    elsif ( $Param{Data}->{IncidentNumber} ) {
        # Look up ticket by incident number
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
        $TicketID = $TicketObject->TicketIDLookup(
            TicketNumber => $Param{Data}->{IncidentNumber},
            UserID       => $UserID,
        );
        $IncidentID = $TicketID if $TicketID;
    }

    if ( !$TicketID ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentGet.MissingParameter',
            ErrorMessage => "IncidentGet: IncidentID, TicketID, or IncidentNumber is required!",
        );
    }

    # Get ticket data
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my %TicketData = $TicketObject->TicketGet(
        TicketID      => $TicketID,
        UserID        => $UserID,
        DynamicFields => 1,
        Extended      => 1,
    );

    if ( !%TicketData ) {
        return $Self->ReturnError(
            ErrorCode    => 'IncidentGet.NotFound',
            ErrorMessage => "IncidentGet: Incident not found or access denied!",
        );
    }

    # Get incident data
    my $IncidentObject = $Kernel::OM->Get('Kernel::System::Incident');
    my %IncidentData = $IncidentObject->IncidentGet(
        IncidentID => $IncidentID,
        UserID     => $UserID,
    );

    # Prepare simple response data with ALL dynamic fields
    my %ResponseData = (
        IncidentID      => $IncidentID,
        TicketID        => $TicketID,
        TicketNumber    => $TicketData{TicketNumber} || '',
        State           => $TicketData{State} || '',
        Priority        => $TicketData{Priority} || '',
        Title           => $TicketData{Title} || '',
        
        # Core Incident Fields
        Source          => $TicketData{DynamicField_IncidentSource} || '',
        CI              => $TicketData{DynamicField_CI} || '',
        AssignedTo      => ($TicketData{OwnerID} && $TicketData{OwnerID} != 1) ? $TicketData{OwnerID} : '',
        AssignmentGroup => $TicketData{DynamicField_AssignmentGroup} || '',
        ShortDescription=> $TicketData{DynamicField_IncidentShortDescription} || '',
        Description     => $TicketData{DynamicField_Description} || '',
        
        # Category Fields
        ProductCat1     => $TicketData{DynamicField_ProductCat1} || '',
        ProductCat2     => $TicketData{DynamicField_ProductCat2} || '',
        ProductCat3     => $TicketData{DynamicField_ProductCat3} || '',
        ProductCat4     => $TicketData{DynamicField_ProductCat4} || '',
        OperationalCat1 => $TicketData{DynamicField_OperationalCat1} || '',
        OperationalCat2 => $TicketData{DynamicField_OperationalCat2} || '',
        OperationalCat3 => $TicketData{DynamicField_OperationalCat3} || '',
        ResolutionCat1  => $TicketData{DynamicField_ResolutionCat1} || '',
        ResolutionCat2  => $TicketData{DynamicField_ResolutionCat2} || '',
        ResolutionCat3  => $TicketData{DynamicField_ResolutionCat3} || '',
        ResolutionCode  => $TicketData{DynamicField_ResolutionCode} || '',
        ResolutionNotes => $TicketData{DynamicField_ResolutionNotes} || '',
        
        # Timestamp Fields
        Opened          => $TicketData{DynamicField_Opened} || '',
        OpenedBy        => $TicketData{DynamicField_OpenedBy} || '',
        Updated         => $TicketData{DynamicField_Updated} || '',
        UpdatedBy       => $TicketData{DynamicField_UpdatedBy} || '',
        Response        => $TicketData{DynamicField_Response} || '',
        Resolved        => $TicketData{DynamicField_Resolved} || '',
        
        # Event Fields
        AlarmID         => $TicketData{DynamicField_AlarmID} || '',
        EventID         => $TicketData{DynamicField_EventID} || '',
        EventSite       => $TicketData{DynamicField_EventSite} || '',
        SourceDevice    => $TicketData{DynamicField_SourceDevice} || '',
        EventMessage    => $TicketData{DynamicField_EventMessage} || '',
        EventBeginTime  => $TicketData{DynamicField_EventBeginTime} || '',
        EventDetectTime => $TicketData{DynamicField_EventDetectTime} || '',
        CIDeviceType    => $TicketData{DynamicField_CIDeviceType} || '',
        
        # MSI Integration Fields
        MSITicketNumber           => $TicketData{DynamicField_MSITicketNumber} || '',
        Customer                  => $TicketData{DynamicField_Customer} || '',
        MSITicketSite            => $TicketData{DynamicField_MSITicketSite} || '',
        MSITicketState           => $TicketData{DynamicField_MSITicketState} || '',
        MSITicketStateReason     => $TicketData{DynamicField_MSITicketStateReason} || '',
        MSITicketPriority        => $TicketData{DynamicField_MSITicketPriority} || '',
        MSITicketAssignee        => $TicketData{DynamicField_MSITicketAssignee} || '',
        MSITicketShortDescription => $TicketData{DynamicField_MSITicketShortDescription} || '',
        MSITicketResolutionNote  => $TicketData{DynamicField_MSITicketResolutionNote} || '',
        MSITicketCreatedTime     => $TicketData{DynamicField_MSITicketCreatedTime} || '',
        MSITicketLastUpdateTime  => $TicketData{DynamicField_MSITicketLastUpdateTime} || '',
        MSITicketEbondLastUpdateTime => $TicketData{DynamicField_MSITicketEbondLastUpdateTime} || '',
        MSITicketResolvedTime    => $TicketData{DynamicField_MSITicketResolvedTime} || '',
        MSIEbondAPIResponse      => $TicketData{DynamicField_MSIEbondAPIResponse} || '',
        MSITicketComment         => $TicketData{DynamicField_MSITicketComment} || '',
    );

    # Include articles if requested
    if ( $Param{Data}->{IncludeArticles} ) {
        my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
        my @ArticleIndex = $ArticleObject->ArticleList(
            TicketID => $TicketID,
            UserID   => $UserID,
        );

        my @Articles;
        for my $ArticleMetaData (@ArticleIndex) {
            my %Article = $ArticleObject->ArticleGet(
                TicketID  => $TicketID,
                ArticleID => $ArticleMetaData->{ArticleID},
                UserID    => $UserID,
            );
            
            push @Articles, {
                ArticleID       => $Article{ArticleID},
                Subject         => $Article{Subject} || '',
                From            => $Article{From} || '',
                To              => $Article{To} || '',
                Body            => $Article{Body} || '',
                ContentType     => $Article{ContentType} || '',
                ArticleType     => $Article{ArticleType} || '',
                SenderType      => $Article{SenderType} || '',
                CreateTime      => $Article{CreateTime} || '',
                CreateBy        => $Article{CreateBy} || '',
                ChangeTime      => $Article{ChangeTime} || '',
                ChangeBy        => $Article{ChangeBy} || '',
            };
        }
        $ResponseData{Articles} = \@Articles;
    }

    # Include attachments if requested
    if ( $Param{Data}->{IncludeAttachments} ) {
        my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
        my @ArticleIndex = $ArticleObject->ArticleList(
            TicketID => $TicketID,
            UserID   => $UserID,
        );

        my @AllAttachments;
        for my $ArticleMetaData (@ArticleIndex) {
            my %AttachmentIndex = $ArticleObject->ArticleAttachmentIndex(
                ArticleID => $ArticleMetaData->{ArticleID},
                UserID    => $UserID,
            );

            for my $FileID ( sort keys %AttachmentIndex ) {
                my %Attachment = $ArticleObject->ArticleAttachment(
                    ArticleID => $ArticleMetaData->{ArticleID},
                    FileID    => $FileID,
                    UserID    => $UserID,
                );
                
                push @AllAttachments, {
                    ArticleID    => $ArticleMetaData->{ArticleID},
                    FileID       => $FileID,
                    Filename     => $Attachment{Filename} || '',
                    ContentType  => $Attachment{ContentType} || '',
                    FilesizeRaw  => $Attachment{FilesizeRaw} || 0,
                    Content      => $Attachment{Content} || '',  # Base64 encoded
                    ContentID    => $Attachment{ContentID} || '',
                    Disposition  => $Attachment{Disposition} || '',
                };
            }
        }
        $ResponseData{Attachments} = \@AllAttachments;
    }

    return {
        Success => 1,
        Data    => \%ResponseData,
    };
}

1;