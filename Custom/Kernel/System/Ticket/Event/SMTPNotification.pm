# --
# Copyright (C) 2025 MSST-Lite
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Ticket::Event::SMTPNotification;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
    'Kernel::System::SMTPDirect',
    'Kernel::System::User',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $SMTPDirect   = $Kernel::OM->Get('Kernel::System::SMTPDirect');

    # Check if SMTP notifications are enabled
    if ( !$ConfigObject->Get('SMTPNotification::Enabled') ) {
        return 1;
    }

    # Get parameters (handle both direct and transaction calls)
    my $TicketID = $Param{TicketID} || $Param{Data}->{TicketID};
    my $Event    = $Param{Event} || $Param{Data}->{Event};
    my $UserID   = $Param{UserID} || $Param{Data}->{UserID} || 1;
    
    # Check needed params
    if ( !$TicketID ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "SMTPNotification: Need TicketID!",
        );
        return 1;
    }

    # Get ticket data
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $TicketID,
        DynamicFields => 1,
        UserID        => $UserID,
    );

    return 1 if !%Ticket;

    # Determine event type
    my $EventType = '';
    my $SendNotification = 0;
    
    if ( $Event && $Event =~ /TicketCreate/ ) {
        $EventType = 'Created';
        $SendNotification = 1;
    }
    elsif ( $Event && $Event =~ /TicketStateUpdate/ ) {
        # Check if ticket is resolved or reopened
        if ( $Ticket{State} =~ /^(resolved|closed successful)/i ) {
            $EventType = 'Resolved';
            $SendNotification = 1;
        }
        elsif ( $Param{Data}->{OldTicketData} ) {
            my $OldState = $Param{Data}->{OldTicketData}->{State} || '';
            # Check if reopened (from resolved/closed to any open state)
            # Open states for incidents: new, assigned, in progress, pending
            if ( $OldState =~ /^(resolved|closed successful)/i && 
                 $Ticket{State} =~ /^(new|assigned|in progress|pending)/i ) {
                $EventType = 'Reopened';
                $SendNotification = 1;
            }
        }
    }
    
    return 1 if !$SendNotification;

    # Map P1-P4 priority names to their configuration keys
    my %PriorityMapping = (
        'P1-Critical' => 1,
        'P2-High'     => 2,
        'P3-Medium'   => 3,
        'P4-Low'      => 4,
    );
    
    # Get the configuration key based on the ticket's priority name
    my $ConfigKey = $PriorityMapping{$Ticket{Priority}} || 0;
    
    # Check priority filter (if configured)
    my $PriorityEnabled = $ConfigKey ? $ConfigObject->Get("SMTPNotification::Priority::$ConfigKey") : undef;
    
    $LogObject->Log(
        Priority => 'info',
        Message  => "SMTPNotification: Ticket $TicketID has Priority=$Ticket{Priority}, ConfigKey=$ConfigKey, PriorityEnabled=" . (defined $PriorityEnabled ? $PriorityEnabled : 'undefined'),
    );
    
    # Get recipients based on priority configuration
    my @RecipientList = $Self->_GetNotificationRecipients(\%Ticket, $PriorityEnabled);
    
    return 1 if !@RecipientList;

    $LogObject->Log(
        Priority => 'info',
        Message  => "SMTPNotification: Sending $EventType notification for ticket $Ticket{TicketNumber} to " . scalar(@RecipientList) . " recipients",
    );

    # Build email content with all required fields
    my $Subject = $Self->_BuildSubject(
        Ticket    => \%Ticket,
        EventType => $EventType,
    );
    
    my $Body = $Self->_BuildBody(
        Ticket    => \%Ticket,
        EventType => $EventType,
    );

    # Send email to each recipient
    my $Success = 1;
    for my $Recipient (@RecipientList) {
        next if !$Recipient;
        
        $LogObject->Log(
            Priority => 'info',
            Message  => "SMTPNotification: Sending notification for ticket $Ticket{TicketNumber} to $Recipient",
        );
        
        my $Result = $SMTPDirect->SendEmail(
            To      => $Recipient,
            Subject => $Subject,
            Body    => $Body,
        );
        
        if ( !$Result ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "SMTPNotification: Failed to send email to $Recipient for ticket $Ticket{TicketNumber}",
            );
            $Success = 0;
        }
    }

    return $Success;
}

sub _GetNotificationRecipients {
    my ( $Self, $Ticket, $PriorityEnabled ) = @_;
    
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    my @RecipientList;
    my %SeenEmail;
    
    # 1. Get assigned user's email if ticket is assigned
    if ( $Ticket->{OwnerID} && $Ticket->{OwnerID} != 1 ) {  # 1 is usually root/admin
        my %User = $UserObject->GetUserData(
            UserID => $Ticket->{OwnerID},
        );
        if ( %User && $User{UserEmail} ) {
            push @RecipientList, $User{UserEmail};
            $SeenEmail{$User{UserEmail}} = 1;
            $LogObject->Log(
                Priority => 'info',
                Message  => "SMTPNotification: Added assigned user: $User{UserFullname} ($User{UserEmail})",
            );
        }
    }
    
    # 2. Get responsible user's email if set
    if ( $Ticket->{ResponsibleID} && $Ticket->{ResponsibleID} != 1 ) {
        my %User = $UserObject->GetUserData(
            UserID => $Ticket->{ResponsibleID},
        );
        if ( %User && $User{UserEmail} && !$SeenEmail{$User{UserEmail}} ) {
            push @RecipientList, $User{UserEmail};
            $SeenEmail{$User{UserEmail}} = 1;
            $LogObject->Log(
                Priority => 'info',
                Message  => "SMTPNotification: Added responsible user: $User{UserFullname} ($User{UserEmail})",
            );
        }
    }
    
    # 3. Add default configured recipients only if priority is enabled
    # If priority is not defined or is enabled (1), add default recipients
    # If priority is disabled (0), skip default recipients
    $LogObject->Log(
        Priority => 'error',
        Message  => "SMTPNotification: _GetNotificationRecipients - PriorityEnabled=" . (defined $PriorityEnabled ? "'$PriorityEnabled'" : 'undefined') . " for ticket " . ($Ticket->{TicketID} || 'unknown'),
    );
    
    # Only add default recipients if priority is explicitly enabled (1)
    if ( defined $PriorityEnabled && $PriorityEnabled ) {
        my $Recipients = $Kernel::OM->Get('Kernel::Config')->Get('SMTPNotification::Recipients') || '';
        if ( $Recipients ) {
            # Split on comma, semicolon, or newline (supports "one per line" entry)
            my @ConfiguredRecipients = split( /\s*[,;\n\r]+\s*/, $Recipients );
            for my $Email (@ConfiguredRecipients) {
                # Trim any remaining whitespace
                $Email =~ s/^\s+|\s+$//g;
                if ($Email && !$SeenEmail{$Email}) {
                    push @RecipientList, $Email;
                    $SeenEmail{$Email} = 1;
                    $LogObject->Log(
                        Priority => 'info',
                        Message  => "SMTPNotification: Added default recipient: $Email",
                    );
                }
            }
        }
    } else {
        $LogObject->Log(
            Priority => 'info',
            Message  => "SMTPNotification: Skipping default recipients - Priority $Ticket->{PriorityID} notifications disabled",
        );
    }
    
    return @RecipientList;
}

sub _BuildSubject {
    my ( $Self, %Param ) = @_;
    
    my $Ticket = $Param{Ticket};
    my $EventType = $Param{EventType};
    
    # Include all required information in subject (no brackets to avoid Gmail threading)
    return sprintf(
        "%s - Ticket #%s: %s - Priority: %s",
        $EventType,
        $Ticket->{TicketNumber},
        $Ticket->{Title} || 'No Title',
        $Ticket->{Priority}
    );
}

sub _BuildBody {
    my ( $Self, %Param ) = @_;
    
    my $Ticket = $Param{Ticket};
    my $EventType = $Param{EventType};
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    
    # Get creator/owner information
    my %CreatorUser;
    if ($Ticket->{CreateBy}) {
        %CreatorUser = $UserObject->GetUserData(
            UserID => $Ticket->{CreateBy},
        );
    }
    
    my %OwnerUser;
    if ($Ticket->{OwnerID} && $Ticket->{OwnerID} != 1) {
        %OwnerUser = $UserObject->GetUserData(
            UserID => $Ticket->{OwnerID},
        );
    }
    
    my $Body = "=== Motorola Solutions LSMP Incident Notification ===\n\n";
    
    $Body .= "Event Type: $EventType\n";
    $Body .= "Date/Time: " . localtime() . "\n\n";
    
    $Body .= "TICKET INFORMATION\n";
    $Body .= "-" x 50 . "\n";
    $Body .= "Ticket Number: $Ticket->{TicketNumber}\n";
    $Body .= "Title (Summary): " . ($Ticket->{Title} || 'No Title') . "\n";
    $Body .= "Priority: $Ticket->{Priority}\n";
    $Body .= "Status: $EventType\n";
    $Body .= "Current State: $Ticket->{State}\n";
    $Body .= "Queue: $Ticket->{Queue}\n\n";
    
    # Site and CI information
    $Body .= "IMPACT INFORMATION\n";
    $Body .= "-" x 50 . "\n";
    
    # Impacted Site (from dynamic field)
    my $ImpactedSite = $Ticket->{DynamicField_MSITicketSite} || 
                       $Ticket->{DynamicField_Site} || 
                       $Ticket->{DynamicField_EventSite} ||
                       'Not specified';
    $Body .= "Impacted Site: $ImpactedSite\n";
    
    # Impacted CI
    my $ImpactedCI = $Ticket->{DynamicField_ImpactedCI} || 
                     $Ticket->{DynamicField_IncidentCI} || 
                     $Ticket->{DynamicField_SourceDevice} ||
                     'Not specified';
    $Body .= "Impacted CI: $ImpactedCI\n\n";
    
    $Body .= "REQUESTOR DETAILS\n";
    $Body .= "-" x 50 . "\n";
    $Body .= "Created By: " . ($CreatorUser{UserFullname} || 'System') . "\n";
    $Body .= "Email: " . ($CreatorUser{UserEmail} || 'N/A') . "\n";
    if (%OwnerUser) {
        $Body .= "Assigned To: $OwnerUser{UserFullname}\n";
        $Body .= "Assignee Email: $OwnerUser{UserEmail}\n";
    } else {
        $Body .= "Assigned To: Not assigned\n";
    }
    $Body .= "\n";
    
    # Add incident specific information if available
    if ($Ticket->{DynamicField_IncidentNumber}) {
        $Body .= "INCIDENT DETAILS\n";
        $Body .= "-" x 50 . "\n";
        $Body .= "Incident Number: " . ($Ticket->{DynamicField_IncidentNumber} || 'N/A') . "\n";
        $Body .= "Category: " . ($Ticket->{DynamicField_ProductCat1} || 'N/A') . "\n";
        $Body .= "Subcategory: " . ($Ticket->{DynamicField_ProductCat2} || 'N/A') . "\n";
        
        # Add alarm/monitoring details if available
        if ($Ticket->{DynamicField_AlarmID}) {
            $Body .= "Alarm ID: $Ticket->{DynamicField_AlarmID}\n";
        }
        if ($Ticket->{DynamicField_EventID}) {
            $Body .= "Event ID: $Ticket->{DynamicField_EventID}\n";
        }
        $Body .= "\n";
    }
    
    # Add appropriate message based on event type
    if ($EventType eq 'Created') {
        $Body .= "A new ticket has been created and requires attention.\n";
    }
    elsif ($EventType eq 'Resolved') {
        $Body .= "This ticket has been resolved.\n";
    }
    elsif ($EventType eq 'Reopened') {
        $Body .= "This ticket has been reopened and requires further attention.\n";
    }
    
    $Body .= "\n" . "=" x 60 . "\n";
    
    # Add ticket link
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $HttpType = $ConfigObject->Get('HttpType') || 'http';
    my $FQDN = $ConfigObject->Get('FQDN') || 'localhost';
    my $ScriptAlias = $ConfigObject->Get('ScriptAlias') || 'otrs/';
    
    # Check if this is an incident ticket
    if ($Ticket->{DynamicField_IncidentNumber}) {
        my $TicketURL = sprintf(
            "%s://%s/%sindex.pl?Action=AgentIncidentForm;Subaction=Update;IncidentNumber=%s",
            $HttpType,
            $FQDN,
            $ScriptAlias,
            $Ticket->{DynamicField_IncidentNumber}
        );
        $Body .= "\n\nView Ticket: $TicketURL\n";
    } else {
        # Fallback to regular ticket zoom
        my $TicketURL = sprintf(
            "%s://%s/%sindex.pl?Action=AgentTicketZoom;TicketID=%s",
            $HttpType,
            $FQDN,
            $ScriptAlias,
            $Ticket->{TicketID}
        );
        $Body .= "\n\nView Ticket: $TicketURL\n";
    }
    
    $Body .= "\nThis is an automated notification from MSST-Lite\n";
    
    return $Body;
}

1;