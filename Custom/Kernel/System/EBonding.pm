# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::System::EBonding;

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use MIME::Base64;
use Encode;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::Config',
    'Kernel::System::JSON',
    'Kernel::System::Time',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Ticket',
);

# Hardcoded ServiceNow environment credentials
our %EnvironmentCredentials = (
    reference => {
        APIURL      => 'https://cmsosnowref.service-now.com/api/now/table/u_inbound_incident',
        APIUser     => 'lsmp.integration.ref',
        APIPassword => 'LyYbK+qo<9<M7Cbyup8nQ.9l<1wWg>E9!z!)w}eI',
    },
    production => {
        APIURL      => 'https://cmsosnow.service-now.com/api/now/table/u_inbound_incident',
        APIUser     => 'lsmp.integration.prod',
        APIPassword => 'G-xig68QsC,ZE<a4P_w4Q+I.kCV]B[=<<bT1fHQr',
    },
);

=head1 NAME

Kernel::System::EBonding - eBonding ServiceNow integration

=head1 DESCRIPTION

Handles submission of Znuny incidents to MSI CMSO ServiceNow system via REST API.

=head1 PUBLIC INTERFACE

=head2 new()

Create an object. Do not use it directly, instead use:

    my $EBondingObject = $Kernel::OM->Get('Kernel::System::EBonding');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 SubmitToServiceNow()

Submit an incident to MSI CMSO ServiceNow system.

    my ($Success, $MSITicketNumber, $ErrorMessage) = $EBondingObject->SubmitToServiceNow(
        IncidentID => 123,
        UserID     => 1,
    );

Returns:
    $Success         - 1 on success, 0 on failure
    $MSITicketNumber - ServiceNow ticket number if successful
    $ErrorMessage    - Error details if failed

=cut

sub SubmitToServiceNow {
    my ( $Self, %Param ) = @_;

    # Get required objects
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');

    # Check required parameters
    for my $Needed (qw(IncidentID UserID)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "SubmitToServiceNow: Need $Needed!",
            );
            return ( 0, undef, "Missing required parameter: $Needed" );
        }
    }

    # Check if eBonding integration is enabled
    my $Enabled = $ConfigObject->Get('EBondingIntegration::Enabled');
    if ( !$Enabled ) {
        my $ErrorMsg = 'eBonding integration is not enabled';
        $LogObject->Log(
            Priority => 'error',
            Message  => "SubmitToServiceNow: $ErrorMsg",
        );
        return ( 0, undef, $ErrorMsg );
    }

    # Get current environment and credentials
    my $Environment = $ConfigObject->Get('EBondingIntegration::Environment') || 'reference';
    my $EnvCreds = $EnvironmentCredentials{$Environment} || $EnvironmentCredentials{reference};

    my $APIURL      = $EnvCreds->{APIURL} || '';
    my $APIUser     = $EnvCreds->{APIUser} || '';
    my $APIPassword = $EnvCreds->{APIPassword} || '';

    if ( !$APIURL || !$APIUser || !$APIPassword ) {
        my $ErrorMsg = "ServiceNow API credentials not configured for environment: $Environment";
        $LogObject->Log(
            Priority => 'error',
            Message  => "SubmitToServiceNow: $ErrorMsg",
        );
        return ( 0, undef, $ErrorMsg );
    }

    $LogObject->Log(
        Priority => 'debug',
        Message  => "SubmitToServiceNow: Using environment '$Environment' with URL $APIURL",
    );

    # Get incident details from Znuny ticket system
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my %Incident = $TicketObject->TicketGet(
        TicketID      => $Param{IncidentID},
        DynamicFields => 1,
        UserID        => $Param{UserID},
    );

    if ( !%Incident ) {
        my $ErrorMsg = "Incident $Param{IncidentID} not found";
        $LogObject->Log(
            Priority => 'error',
            Message  => "SubmitToServiceNow: $ErrorMsg",
        );
        return ( 0, undef, $ErrorMsg );
    }

    # Map ticket fields to incident fields for easier access
    $Incident{IncidentID}     = $Incident{TicketID};
    $Incident{TicketNumber}   = $Incident{TicketNumber};
    $Incident{Priority}       = $Incident{Priority};  # Priority name from TicketGet (e.g., "P2-High")
    $Incident{PriorityName}   = $Incident{Priority};  # Alias for description building
    $Incident{CustomerUserID} = $Incident{CustomerUserID};
    $Incident{Description}    = $Incident{DynamicField_Description} || '';  # Get from Description dynamic field

    # Get license details for customer
    my %License = $Self->_GetLicenseByCustomer(
        CustomerUserID => $Incident{CustomerUserID},
    );

    if ( !%License ) {
        my $ErrorMsg = 'No valid license found for this customer';
        $LogObject->Log(
            Priority => 'error',
            Message  => "SubmitToServiceNow: $ErrorMsg for incident $Param{IncidentID}",
        );
        return ( 0, undef, $ErrorMsg );
    }

    # Get work notes flagged for MSI
    my @WorkNotes = $Self->_GetWorkNotesForMSI(
        IncidentID => $Param{IncidentID},
    );

    # Build ServiceNow API payload
    my %Payload = $Self->_BuildServiceNowPayload(
        Incident  => \%Incident,
        License   => \%License,
        WorkNotes => \@WorkNotes,
    );

    # Convert payload to JSON
    my $JSONPayload = $JSONObject->Encode(
        Data => \%Payload,
    );

    if ( !$JSONPayload ) {
        my $ErrorMsg = 'Failed to encode JSON payload';
        $LogObject->Log(
            Priority => 'error',
            Message  => "SubmitToServiceNow: $ErrorMsg for incident $Param{IncidentID}",
        );
        return ( 0, undef, $ErrorMsg );
    }

    # Log request timestamp
    my $RequestTime = $TimeObject->CurrentTimestamp();

    # Submit to ServiceNow API
    my $ua = LWP::UserAgent->new(
        timeout  => 30,
        ssl_opts => { verify_hostname => 1 },
    );

    my $request = HTTP::Request->new( POST => $APIURL );
    $request->header( 'Content-Type'  => 'application/json; charset=utf-8' );
    $request->header( 'Authorization' => 'Basic ' . encode_base64( "$APIUser:$APIPassword", '' ) );
    $request->content( Encode::encode_utf8($JSONPayload) );

    # Send request
    my $response = $ua->request($request);
    my $ResponseTime = $TimeObject->CurrentTimestamp();

    # Parse response
    my $Success          = 0;
    my $MSITicketNumber  = undef;
    my $ErrorMessage     = undef;
    my $ResponsePayload  = $response->content();
    my $ResponseStatus   = $response->code();

    if ( $response->is_success ) {
        # Parse JSON response
        my $ResponseData = $JSONObject->Decode(
            Data => $ResponsePayload,
        );

        if ( $ResponseData && ref($ResponseData) eq 'HASH' ) {
            # Extract all MSI fields from ServiceNow response
            my $Result = $ResponseData->{result} || {};

            # Get sys_target_sys_id.link and .value from response
            my $TargetSysID = $Result->{sys_target_sys_id}->{value} || '';
            my $TargetURL = $Result->{sys_target_sys_id}->{link} || '';

            if ($TargetSysID && $TargetURL) {
                $Success = 1;
                $LogObject->Log(
                    Priority => 'info',
                    Message  => "SubmitToServiceNow: Successfully submitted incident $Param{IncidentID} to ServiceNow. Incident sys_id: $TargetSysID",
                );

                # Query ServiceNow for human-readable incident number using the URL
                my $HumanReadableNumber = $Self->_GetIncidentNumberFromServiceNow(
                    TargetURL   => $TargetURL,
                    APIUser     => $APIUser,
                    APIPassword => $APIPassword,
                );

                # Use human-readable number if available, otherwise use incident sys_id
                $MSITicketNumber = $HumanReadableNumber || $TargetSysID;

                # Update all MSI dynamic fields
                my $UpdateSuccess = $Self->_UpdateAllMSIFields(
                    TicketID                => $Param{IncidentID},
                    MSITicketNumber         => $MSITicketNumber,
                    MSITicketSysID          => $TargetSysID,
                    MSITicketURL            => $TargetURL,
                    HumanReadableNumber     => $HumanReadableNumber,
                    ServiceNowResponse      => $Result,
                    ResponsePayload         => $ResponsePayload,
                    UserID                  => $Param{UserID},
                );

                if ( !$UpdateSuccess ) {
                    $LogObject->Log(
                        Priority => 'error',
                        Message  => "SubmitToServiceNow: Failed to update MSI dynamic fields for incident $Param{IncidentID}",
                    );
                }
            }
            else {
                $ErrorMessage = 'ServiceNow response missing ticket number';
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "SubmitToServiceNow: $ErrorMessage for incident $Param{IncidentID}",
                );
            }
        }
        else {
            $ErrorMessage = 'Failed to parse ServiceNow JSON response';
            $LogObject->Log(
                Priority => 'error',
                Message  => "SubmitToServiceNow: $ErrorMessage for incident $Param{IncidentID}",
            );
        }
    }
    else {
        # Try to parse JSON error response
        my $ErrorData = $JSONObject->Decode(
            Data => $ResponsePayload,
        );

        if ( $ErrorData && ref($ErrorData) eq 'HASH' && $ErrorData->{error} ) {
            # ServiceNow returned JSON error
            $ErrorMessage = $ErrorData->{error}->{message} || $ErrorData->{error}->{detail} || $response->status_line;
        }
        else {
            # Non-JSON error or unparseable
            $ErrorMessage = 'ServiceNow API returned error: ' . $response->status_line;
        }

        $LogObject->Log(
            Priority => 'error',
            Message  => "SubmitToServiceNow: $ErrorMessage for incident $Param{IncidentID}",
        );
    }

    # Log API request to database
    $Self->_LogAPIRequest(
        IncidentID         => $Param{IncidentID},
        IncidentNumber     => $Incident{TicketNumber},
        Action             => 'SubmitToServiceNow',
        RequestURL         => $APIURL,
        RequestPayload     => $JSONPayload,
        ResponsePayload    => $ResponsePayload,
        ResponseStatusCode => $ResponseStatus,
        MSITicketNumber    => $MSITicketNumber,
        Success            => $Success,
        ErrorMessage       => $ErrorMessage,
        UserID             => $Param{UserID},
    );

    return ( $Success, $MSITicketNumber, $ErrorMessage );
}

=head2 _GetLicenseByCustomer()

Get license details for a customer.

    my %License = $EBondingObject->_GetLicenseByCustomer(
        CustomerUserID => 'customer@example.com',
    );

Returns license hash with: mcn, systemTechnology, endCustomer, lsmpSiteID

=cut

sub _GetLicenseByCustomer {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');

    # Check required parameters
    if ( !$Param{CustomerUserID} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => '_GetLicenseByCustomer: Need CustomerUserID!',
        );
        return;
    }

    # Query license table
    # Note: In production, you'll need to join with customer/company tables
    # For now, we'll get the first valid license
    return if !$DBObject->Prepare(
        SQL => 'SELECT id, uid, mcn, systemtechnology, endcustomer, lsmpsiteid, contractcompany '
            . 'FROM license '
            . 'WHERE enddate >= current_timestamp '
            . 'ORDER BY id DESC '
            . 'LIMIT 1',
    );

    my %License;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        %License = (
            LicenseID        => $Row[0],
            UID              => $Row[1] || '',
            MCN              => $Row[2] || '',
            SystemTechnology => $Row[3] || '',
            EndCustomer      => $Row[4] || '',
            LSMPSiteID       => $Row[5] || '',
            ContractCompany  => $Row[6] || '',
        );
    }

    if ( !%License ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "_GetLicenseByCustomer: No valid license found for customer $Param{CustomerUserID}",
        );
    }

    return %License;
}

=head2 _BuildServiceNowPayload()

Build ServiceNow API payload from incident and license data.

    my %Payload = $EBondingObject->_BuildServiceNowPayload(
        Incident  => \%Incident,
        License   => \%License,
        WorkNotes => \@WorkNotes,
    );

Returns hash with all ServiceNow fields mapped.

=cut

sub _BuildServiceNowPayload {
    my ( $Self, %Param ) = @_;

    my $Incident  = $Param{Incident};
    my $License   = $Param{License};
    my $WorkNotes = $Param{WorkNotes} || [];

    # Map priority to impact/urgency
    my ( $Impact, $Urgency ) = $Self->_MapPriorityToImpactUrgency(
        Priority => $Incident->{Priority},
    );

    # Map technology to product category tier 1
    my $ProductCategoryTier1 = $Self->_MapTechnologyToProductCategory(
        Technology => $License->{SystemTechnology},
    );

    # Get actual product category from incident or use default
    my $ProductCategory = $Incident->{'DynamicField_ProductCat1'} || $ProductCategoryTier1;

    # Set assignment group to LSMP_AutoDispatch for all incidents
    my $AssignmentGroup = 'LSMP_AutoDispatch';

    # Build composite description
    my $Description = $Self->_BuildCompositeDescription(
        Incident => $Incident,
        License  => $License,
    );

    # Build composite close notes
    my $CloseNotes = $Self->_BuildCompositeCloseNotes(
        Incident => $Incident,
    );

    # Sanitize text fields for ServiceNow (remove problematic Unicode)
    my $ShortDesc = $Self->_SanitizeForServiceNow( Text => $Incident->{Title} || '' );
    $Description = $Self->_SanitizeForServiceNow( Text => $Description );
    $CloseNotes  = $Self->_SanitizeForServiceNow( Text => $CloseNotes );

    # Build payload
    my %Payload = (
        # Static fields
        u_contact_type => 'LSMP',
        u_email        => 'lsmp.user.com',
        u_first_name   => 'LSMP',
        u_last_name    => 'User',
        u_state        => 3,  # 3 = Assigned status in ServiceNow

        # From license
        u_mcn              => $License->{MCN} || '',
        u_site_id          => $License->{UID} || '',
        u_assignment_group => $AssignmentGroup,

        # From incident
        u_service_provider_ticket_number => $Incident->{TicketNumber} || '',
        u_short_description              => $ShortDesc,
        u_impact                         => $Impact,
        u_urgency                        => $Urgency,

        # Product categories from incident dynamic fields
        # For ASTRO/DIMETRA: Pad with technology as Tier 1, shift categories down
        # For WAVE: Use categories as-is
        u_product_category_tier_1 => $Self->_GetProductCategoryTier1($Incident, $ProductCategoryTier1),
        u_product_category_tier_2 => $Self->_GetProductCategoryTier2($Incident),
        u_product_category_tier_3 => $Self->_GetProductCategoryTier3($Incident),
        u_product_category_tier_4 => $Self->_GetProductCategoryTier4($Incident),
        u_product_name            => $Incident->{'DynamicField_ProductCat4'} || '',

        # Operational categories from incident dynamic fields
        u_operational_category_tier_1 => $Incident->{'DynamicField_OperationalCat1'} || '',
        u_operational_category_tier_2 => $Incident->{'DynamicField_OperationalCat2'} || '',
        u_operational_category_tier_3 => $Incident->{'DynamicField_OperationalCat3'} || '',

        # Description
        u_description => $Description,

        # Resolution notes (composite of all resolution fields)
        close_notes => $CloseNotes,
    );

    # Add work notes as comments (concatenated as single string)
    if ( @{$WorkNotes} ) {
        my @CommentParts;
        for my $Note ( @{$WorkNotes} ) {
            my $CommentText = "Author: " . ($Note->{Author} || 'Unknown') . "\n";
            $CommentText .= "Time: " . ($Note->{Timestamp} || 'N/A') . "\n";
            # Strip HTML from work note text and sanitize for ServiceNow
            my $NoteText = $Self->_StripHTML( HTML => $Note->{Text} ) || '';
            $NoteText = $Self->_SanitizeForServiceNow( Text => $NoteText );
            $CommentText .= $NoteText;
            push @CommentParts, $CommentText;
        }
        $Payload{u_comments} = join("\n\n---\n\n", @CommentParts);
    }

    return %Payload;
}

=head2 _MapPriorityToImpactUrgency()

Map Znuny priority to ServiceNow Impact/Urgency values.

    my ($Impact, $Urgency) = $EBondingObject->_MapPriorityToImpactUrgency(
        Priority => 2,
    );

Returns Impact and Urgency severity values.

=cut

sub _MapPriorityToImpactUrgency {
    my ( $Self, %Param ) = @_;

    my $Priority = $Param{Priority} || 'P4-Low';  # Default to P4

    # Priority mapping (using priority name for consistency across environments):
    # P1-Critical -> 1 / 1
    # P2-High     -> 2 / 2
    # P3-Medium   -> 3 / 3
    # P4-Low      -> 4 / 4

    my %Mapping = (
        'P1-Critical' => { Impact => '1', Urgency => '1' },
        'P2-High'     => { Impact => '2', Urgency => '2' },
        'P3-Medium'   => { Impact => '3', Urgency => '3' },
        'P4-Low'      => { Impact => '4', Urgency => '4' },
    );

    my $Map = $Mapping{$Priority} || $Mapping{'P4-Low'};  # Default to P4

    return ( $Map->{Impact}, $Map->{Urgency} );
}

=head2 _MapTechnologyToAssignmentGroup()

Map license technology to ServiceNow assignment group.

    my $AssignmentGroup = $EBondingObject->_MapTechnologyToAssignmentGroup(
        Technology => 'ASTRO',
    );

Returns assignment group name.

=cut

sub _MapTechnologyToAssignmentGroup {
    my ( $Self, %Param ) = @_;

    my $Technology = $Param{Technology} || '';

    # Map license technology to ServiceNow assignment group
    # Using NA_SWE_Flex_FrontOffice for all technologies since other groups are not configured in ServiceNow yet
    my %Mapping = (
        'ASTRO'      => 'NA_SWE_Flex_FrontOffice',
        'DIMETRA'    => 'NA_SWE_Flex_FrontOffice',
        'WAVEOnPrem' => 'NA_SWE_Flex_FrontOffice',
    );

    return $Mapping{$Technology} || 'NA_SWE_Flex_FrontOffice';  # Default
}

=head2 _MapTechnologyToProductCategory()

Map system technology to Product Category Tier 1.

    my $Category = $EBondingObject->_MapTechnologyToProductCategory(
        Technology => 'ASTRO',
    );

Returns product category tier 1 value.

=cut

sub _MapTechnologyToProductCategory {
    my ( $Self, %Param ) = @_;

    my $Technology = $Param{Technology} || '';

    # Map technology to Product Category Tier 1 values from CSV
    my %Mapping = (
        'ASTRO'      => 'ASTRO Infrastructure',
        'DIMETRA'    => 'DIMETRA',
        'WAVEOnPrem' => 'WAVE',
    );

    return $Mapping{$Technology} || 'ASTRO Infrastructure';  # Default
}

=head2 _StripHTML()

Strip HTML tags from text, converting to plain text.
Converts <p>, <br>, <div> to newlines for readability.

    my $PlainText = $EBondingObject->_StripHTML(
        HTML => '<p>Some text</p><p>More text</p>',
    );

Returns plain text string.

=cut

sub _StripHTML {
    my ( $Self, %Param ) = @_;

    my $HTML = $Param{HTML} || '';

    return '' if !$HTML;

    # Convert block elements to newlines
    $HTML =~ s{<br\s*/?>}{\n}gi;
    $HTML =~ s{</p>}{\n}gi;
    $HTML =~ s{</div>}{\n}gi;
    $HTML =~ s{</li>}{\n}gi;
    $HTML =~ s{<li[^>]*>}{- }gi;

    # Remove all remaining HTML tags
    $HTML =~ s{<[^>]+>}{}g;

    # Decode common HTML entities
    $HTML =~ s{&nbsp;}{ }g;
    $HTML =~ s{&amp;}{&}g;
    $HTML =~ s{&lt;}{<}g;
    $HTML =~ s{&gt;}{>}g;
    $HTML =~ s{&quot;}{"}g;
    $HTML =~ s{&#39;}{'}g;

    # Clean up excessive whitespace
    $HTML =~ s{\n{3,}}{\n\n}g;  # Max 2 consecutive newlines
    $HTML =~ s{[ \t]+}{ }g;     # Collapse spaces/tabs
    $HTML =~ s{^\s+}{}s;        # Trim leading whitespace
    $HTML =~ s{\s+$}{}s;        # Trim trailing whitespace

    return $HTML;
}

=head2 _SanitizeForServiceNow()

Sanitize text for ServiceNow API by removing problematic Unicode characters.
ServiceNow often misinterprets UTF-8 as Latin-1, causing characters like
Zero-Width Spaces (U+200B) to appear as garbage (â).

    my $CleanText = $EBondingObject->_SanitizeForServiceNow(
        Text => $Text,
    );

Returns sanitized text string safe for ServiceNow.

=cut

sub _SanitizeForServiceNow {
    my ( $Self, %Param ) = @_;

    my $Text = $Param{Text};
    return '' if !defined $Text;

    # Remove Zero-Width characters that cause display issues in ServiceNow
    # U+200B Zero Width Space
    # U+200C Zero Width Non-Joiner
    # U+200D Zero Width Joiner
    # U+FEFF Byte Order Mark (Zero Width No-Break Space)
    # U+00AD Soft Hyphen
    $Text =~ s/[\x{200B}\x{200C}\x{200D}\x{FEFF}\x{00AD}]//g;

    # Remove other invisible/formatting characters that cause issues
    # U+2028 Line Separator
    # U+2029 Paragraph Separator
    $Text =~ s/[\x{2028}\x{2029}]/\n/g;

    # Remove other problematic Unicode whitespace that may display as garbage
    # U+00A0 Non-Breaking Space -> regular space
    $Text =~ s/\x{00A0}/ /g;

    return $Text;
}

=head2 _BuildCompositeDescription()

Build composite u_description field from multiple sources.

    my $Description = $EBondingObject->_BuildCompositeDescription(
        Incident => \%Incident,
        License  => \%License,
    );

Returns formatted description text.

=cut

sub _BuildCompositeDescription {
    my ( $Self, %Param ) = @_;

    my $Incident = $Param{Incident};
    my $License  = $Param{License};

    my @DescriptionParts;

    # CI - FIRST
    push @DescriptionParts, "Configuration Item: " . ( $Incident->{DynamicField_CI} || 'N/A' );
    push @DescriptionParts, "";

    # Description - strip HTML from RichText field
    my $DescriptionText = $Self->_StripHTML( HTML => $Incident->{Description} ) || 'No description provided';
    push @DescriptionParts, "Description:";
    push @DescriptionParts, $DescriptionText;

    # Monitoring Event Details (if monitoring fields exist)
    my $HasMonitoringData = $Incident->{DynamicField_AlarmID} ||
                            $Incident->{DynamicField_EventID} ||
                            $Incident->{DynamicField_EventSite};

    if ( $HasMonitoringData ) {
        push @DescriptionParts, "";
        push @DescriptionParts, "Monitoring Event Details:";
        push @DescriptionParts, "- Alarm ID: " . ( $Incident->{DynamicField_AlarmID} || 'N/A' );
        push @DescriptionParts, "- Event ID: " . ( $Incident->{DynamicField_EventID} || 'N/A' );
        push @DescriptionParts, "- Event Site: " . ( $Incident->{DynamicField_EventSite} || 'N/A' );
        push @DescriptionParts, "- Source Device: " . ( $Incident->{DynamicField_SourceDevice} || 'N/A' );
        push @DescriptionParts, "- Event Begin Time: " . ( $Incident->{DynamicField_EventBeginTime} || 'N/A' );
        push @DescriptionParts, "- Event Detect Time: " . ( $Incident->{DynamicField_EventDetectTime} || 'N/A' );
    }

    return join( "\n", @DescriptionParts );
}

=head2 _BuildCompositeCloseNotes()

Build composite close notes from resolution fields.

    my $CloseNotes = $EBondingObject->_BuildCompositeCloseNotes(
        Incident => \%Incident,
    );

Returns concatenated close notes string.

=cut

sub _BuildCompositeCloseNotes {
    my ( $Self, %Param ) = @_;

    my $Incident = $Param{Incident};

    my @CloseNotesParts;

    # Resolution Categories
    push @CloseNotesParts, "Resolution Category Tier 1: " . ( $Incident->{DynamicField_ResolutionCat1} || 'N/A' );
    push @CloseNotesParts, "Resolution Category Tier 2: " . ( $Incident->{DynamicField_ResolutionCat2} || 'N/A' );
    push @CloseNotesParts, "Resolution Category Tier 3: " . ( $Incident->{DynamicField_ResolutionCat3} || 'N/A' );
    push @CloseNotesParts, "";

    # Resolution Code
    push @CloseNotesParts, "Resolution Code: " . ( $Incident->{DynamicField_ResolutionCode} || 'N/A' );
    push @CloseNotesParts, "";

    # Resolution Notes - strip HTML from RichText field
    my $ResolutionNotesText = $Self->_StripHTML( HTML => $Incident->{DynamicField_ResolutionNotes} ) || 'N/A';
    push @CloseNotesParts, "Resolution Notes:";
    push @CloseNotesParts, $ResolutionNotesText;
    push @CloseNotesParts, "";

    # MSI Ticket Resolution Note - strip HTML from RichText field
    my $MSIResolutionNoteText = $Self->_StripHTML( HTML => $Incident->{DynamicField_MSITicketResolutionNote} ) || 'N/A';
    push @CloseNotesParts, "MSI Ticket Resolution Note:";
    push @CloseNotesParts, $MSIResolutionNoteText;

    return join( "\n", @CloseNotesParts );
}

=head2 _GetWorkNotesForMSI()

Get work notes flagged for MSI inclusion.

    my @WorkNotes = $EBondingObject->_GetWorkNotesForMSI(
        IncidentID => 123,
    );

Returns array of work note hashes.

=cut

sub _GetWorkNotesForMSI {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');

    if ( !$Param{IncidentID} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => '_GetWorkNotesForMSI: Need IncidentID!',
        );
        return;
    }

    # Query work notes with include_in_msi flag enabled
    return if !$DBObject->Prepare(
        SQL => 'SELECT note_text, created_by_name, created_time '
            . 'FROM incident_work_notes '
            . 'WHERE ticket_id = ? AND include_in_msi = 1 '
            . 'ORDER BY created_time ASC',
        Bind => [ \$Param{IncidentID} ],
    );

    my @WorkNotes;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @WorkNotes, {
            Text      => $Row[0] || '',
            Author    => $Row[1] || '',
            Timestamp => $Row[2] || '',
        };
    }

    return @WorkNotes;
}

=head2 _LogAPIRequest()

Log API request/response to database.

    my $LogID = $EBondingObject->_LogAPIRequest(
        IncidentID         => 123,
        IncidentNumber     => 'INC123',
        Action             => 'SubmitToServiceNow',
        RequestURL         => 'https://...',
        RequestPayload     => '{}',
        ResponsePayload    => '{}',
        ResponseStatusCode => 200,
        MSITicketNumber    => 'MSI456',
        Success            => 1,
        ErrorMessage       => undef,
        UserID             => 1,
    );

Returns log ID on success.

=cut

sub _LogAPIRequest {
    my ( $Self, %Param ) = @_;

    my $LogObject  = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject   = $Kernel::OM->Get('Kernel::System::DB');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Insert log record
    return if !$DBObject->Do(
        SQL => 'INSERT INTO ebonding_api_log '
            . '(incident_id, incident_number, action, request_url, request_payload, '
            . 'response_payload, response_status_code, msi_ticket_number, success, '
            . 'error_message, create_time, create_by) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, ?)',
        Bind => [
            \$Param{IncidentID}, \$Param{IncidentNumber}, \$Param{Action},
            \$Param{RequestURL}, \$Param{RequestPayload}, \$Param{ResponsePayload},
            \$Param{ResponseStatusCode}, \$Param{MSITicketNumber}, \$Param{Success},
            \$Param{ErrorMessage}, \$Param{UserID},
        ],
    );

    $LogObject->Log(
        Priority => 'debug',
        Message  => "_LogAPIRequest: Logged API request for incident $Param{IncidentID}",
    );

    return 1;
}

=head2 _UpdateAllMSIFields()

Update all MSI dynamic fields from ServiceNow response.

    my $Success = $EBondingObject->_UpdateAllMSIFields(
        TicketID           => 123,
        MSITicketNumber    => 'MSI456',
        ServiceNowResponse => \%Response,
        ResponsePayload    => '{}',
        UserID             => 1,
    );

Returns 1 on success.

=cut

sub _UpdateAllMSIFields {
    my ( $Self, %Param ) = @_;

    my $LogObject                 = $Kernel::OM->Get('Kernel::System::Log');
    my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    # Check required parameters
    for my $Needed (qw(TicketID MSITicketNumber ServiceNowResponse UserID)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "_UpdateAllMSIFields: Need $Needed!",
            );
            return;
        }
    }

    my $SNResp = $Param{ServiceNowResponse};

    # Extract state - ONLY from actual incident table (GET/Sync response)
    # The CREATE response from staging table only has u_state with numeric value (e.g., "3")
    # We want to show the display_value (e.g., "Assigned") which is only available during Sync.
    # Response format: "state": { "display_value": "Assigned", "value": "3" }
    my $StateValue = '';
    if (ref($SNResp->{state}) eq 'HASH') {
        # GET/Sync response format: use display_value for user-friendly display
        $StateValue = $SNResp->{state}->{display_value} || $SNResp->{state}->{value} || '';
    } elsif (exists $SNResp->{state} && !ref($SNResp->{state})) {
        # Direct value from GET response (no nesting)
        $StateValue = $SNResp->{state} || '';
    }
    # Note: We intentionally do NOT use u_state from CREATE response (it's just numeric "3")

    # Extract assigned_to (individual assignee) with proper handling for both CREATE and GET responses
    # assigned_to contains the individual person assigned to the ticket
    # Response format: "assigned_to": { "display_value": "Yonathan Krista", "link": "...", "value": "6ac1dd00..." }
    my $AssigneeValue = '';
    if (ref($SNResp->{assigned_to}) eq 'HASH') {
        # GET response format - use display_value for the person's name
        $AssigneeValue = $SNResp->{assigned_to}->{display_value} || $SNResp->{assigned_to}->{value} || '';
    } elsif (ref($SNResp->{u_assigned_to}) eq 'HASH') {
        # CREATE response format with u_ prefix
        $AssigneeValue = $SNResp->{u_assigned_to}->{display_value} || $SNResp->{u_assigned_to}->{value} || '';
    } elsif (exists $SNResp->{assigned_to} && !ref($SNResp->{assigned_to})) {
        # Direct value
        $AssigneeValue = $SNResp->{assigned_to} || '';
    } elsif (exists $SNResp->{u_assigned_to} && !ref($SNResp->{u_assigned_to})) {
        # Direct value with u_ prefix
        $AssigneeValue = $SNResp->{u_assigned_to} || '';
    }

    # Extract datetime fields with proper handling
    my $CreatedTime = '';
    if (ref($SNResp->{sys_created_on}) eq 'HASH') {
        $CreatedTime = $SNResp->{sys_created_on}->{display_value} || $SNResp->{sys_created_on}->{value} || '';
    } else {
        $CreatedTime = $SNResp->{sys_created_on} || '';
    }

    my $UpdatedTime = '';
    if (ref($SNResp->{sys_updated_on}) eq 'HASH') {
        $UpdatedTime = $SNResp->{sys_updated_on}->{display_value} || $SNResp->{sys_updated_on}->{value} || '';
    } else {
        $UpdatedTime = $SNResp->{sys_updated_on} || '';
    }

    my $ResolvedTime = '';
    if (ref($SNResp->{resolved_at}) eq 'HASH') {
        # GET response format: resolved_at without u_ prefix
        $ResolvedTime = $SNResp->{resolved_at}->{display_value} || $SNResp->{resolved_at}->{value} || '';
    } elsif (ref($SNResp->{u_resolved_at}) eq 'HASH') {
        # Fallback: u_resolved_at with u_ prefix
        $ResolvedTime = $SNResp->{u_resolved_at}->{display_value} || $SNResp->{u_resolved_at}->{value} || '';
    } else {
        # Direct value
        $ResolvedTime = $SNResp->{resolved_at} || $SNResp->{u_resolved_at} || '';
    }

    # Extract priority - ONLY from actual incident table (GET/Sync response)
    # The CREATE response from staging table (u_inbound_incident) doesn't have priority -
    # ServiceNow calculates it when the incident is created from the staging record.
    # Priority is only available during Sync.
    # Response format: "priority": { "display_value": "P2", "value": "2" }
    my $PriorityValue = '';
    if (ref($SNResp->{priority}) eq 'HASH') {
        # GET response format: use display_value (e.g., "P2") for user-friendly display
        $PriorityValue = $SNResp->{priority}->{display_value} || $SNResp->{priority}->{value} || '';
    } elsif (exists $SNResp->{priority} && !ref($SNResp->{priority})) {
        # Direct value from GET response (no nesting)
        $PriorityValue = $SNResp->{priority} || '';
    }
    # Note: CREATE response doesn't have priority field - it's only on the incident table

    # Extract short_description with proper handling for both CREATE and GET responses
    my $ShortDescription = '';
    if (ref($SNResp->{short_description}) eq 'HASH') {
        # GET response format
        $ShortDescription = $SNResp->{short_description}->{display_value} || $SNResp->{short_description}->{value} || '';
    } elsif (ref($SNResp->{u_short_description}) eq 'HASH') {
        # CREATE response format with u_ prefix
        $ShortDescription = $SNResp->{u_short_description}->{display_value} || $SNResp->{u_short_description}->{value} || '';
    } else {
        # Direct value
        $ShortDescription = $SNResp->{short_description} || $SNResp->{u_short_description} || '';
    }

    # Extract close_notes/resolution_notes with proper handling for both CREATE and GET responses
    my $CloseNotes = '';
    if (ref($SNResp->{close_notes}) eq 'HASH') {
        # GET response format
        $CloseNotes = $SNResp->{close_notes}->{display_value} || $SNResp->{close_notes}->{value} || '';
    } elsif (ref($SNResp->{u_resolution_notes}) eq 'HASH') {
        # CREATE response format with u_ prefix
        $CloseNotes = $SNResp->{u_resolution_notes}->{display_value} || $SNResp->{u_resolution_notes}->{value} || '';
    } else {
        # Direct value
        $CloseNotes = $SNResp->{close_notes} || $SNResp->{u_resolution_notes} || '';
    }

    # Extract state_reason with proper handling for both CREATE and GET responses
    my $StateReason = '';
    if (ref($SNResp->{u_state_reason}) eq 'HASH') {
        # Both CREATE and GET should use u_state_reason
        $StateReason = $SNResp->{u_state_reason}->{display_value} || $SNResp->{u_state_reason}->{value} || '';
    } elsif (ref($SNResp->{state_reason}) eq 'HASH') {
        # Fallback if ServiceNow returns state_reason without u_ prefix
        $StateReason = $SNResp->{state_reason}->{display_value} || $SNResp->{state_reason}->{value} || '';
    } else {
        # Direct value
        $StateReason = $SNResp->{u_state_reason} || $SNResp->{state_reason} || '';
    }

    # Extract company (Customer) with proper handling for both CREATE and GET responses
    my $CompanyValue = '';
    if (ref($SNResp->{company}) eq 'HASH') {
        # GET response format: use display_value for user-friendly display
        $CompanyValue = $SNResp->{company}->{display_value} || $SNResp->{company}->{value} || '';
    } elsif (exists $SNResp->{company} && !ref($SNResp->{company})) {
        # Direct value
        $CompanyValue = $SNResp->{company} || '';
    }

    # Extract u_site with proper handling for both CREATE and GET responses
    my $SiteValue = '';
    if (ref($SNResp->{u_site}) eq 'HASH') {
        # GET response format: use display_value for user-friendly display
        $SiteValue = $SNResp->{u_site}->{display_value} || $SNResp->{u_site}->{value} || '';
    } elsif (exists $SNResp->{u_site} && !ref($SNResp->{u_site})) {
        # Direct value
        $SiteValue = $SNResp->{u_site} || '';
    }

    # Map ServiceNow fields to Znuny dynamic fields
    # Get current time for cooldown tracking
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');
    my $CurrentTimestamp = $TimeObject->CurrentTimestamp();

    my %FieldMapping = (
        MSITicketNumber              => $Param{MSITicketNumber} || '',  # Already calculated correctly in SubmitToServiceNow
        MSITicketSysID               => $Param{MSITicketSysID} || '',   # Incident sys_id
        MSITicketURL                 => $Param{MSITicketURL} || '',     # Full incident URL
        Customer                     => $CompanyValue,                   # Company from ServiceNow
        MSITicketSite                => $SiteValue,                      # u_site from ServiceNow
        MSITicketState               => $StateValue,
        MSITicketStateReason         => $StateReason,
        MSITicketPriority            => $PriorityValue,
        MSITicketAssignee            => $AssigneeValue,
        MSITicketShortDescription    => $ShortDescription,
        MSITicketResolutionNote      => $CloseNotes,
        MSITicketCreatedTime         => $CreatedTime,
        MSITicketLastUpdateTime      => $UpdatedTime,
        MSITicketEbondLastUpdateTime => $CurrentTimestamp,  # Always set to current time for cooldown tracking
        MSITicketResolvedTime        => $ResolvedTime,
        MSIEbondAPIResponse          => $Param{ResponsePayload} || '',
    );

    # Update each dynamic field
    my $UpdateCount = 0;
    for my $FieldName ( keys %FieldMapping ) {
        my $Value = $FieldMapping{$FieldName};

        # Skip empty values for optional fields
        next if !defined $Value || $Value eq '';

        # Get dynamic field config
        my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
            Name => $FieldName,
        );

        if ( !$DynamicFieldConfig ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "_UpdateAllMSIFields: Dynamic field '$FieldName' not found, skipping",
            );
            next;
        }

        # Set the dynamic field value
        my $Success = $DynamicFieldBackendObject->ValueSet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ObjectID           => $Param{TicketID},
            Value              => $Value,
            UserID             => $Param{UserID},
        );

        if ($Success) {
            $UpdateCount++;
            $LogObject->Log(
                Priority => 'debug',
                Message  => "_UpdateAllMSIFields: Set $FieldName for ticket $Param{TicketID}",
            );
        }
        else {
            $LogObject->Log(
                Priority => 'error',
                Message  => "_UpdateAllMSIFields: Failed to set $FieldName for ticket $Param{TicketID}",
            );
        }
    }

    $LogObject->Log(
        Priority => 'info',
        Message  => "_UpdateAllMSIFields: Updated $UpdateCount MSI fields for ticket $Param{TicketID}",
    );

    return 1;
}

=head2 _GetIncidentNumberFromServiceNow()

Query ServiceNow to get human-readable incident number using the incident URL.

    my $IncidentNumber = $EBondingObject->_GetIncidentNumberFromServiceNow(
        TargetURL   => 'https://.../.../incident/77ebeefa...',
        APIUser     => 'user',
        APIPassword => 'pass',
    );

Returns incident number (e.g., "INC0001234") or undef if not found.

=cut

sub _GetIncidentNumberFromServiceNow {
    my ( $Self, %Param ) = @_;

    my $LogObject  = $Kernel::OM->Get('Kernel::System::Log');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    # Check required parameters
    for my $Needed (qw(TargetURL APIUser APIPassword)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "_GetIncidentNumberFromServiceNow: Need $Needed!",
            );
            return;
        }
    }

    # Use the URL directly from sys_target_sys_id.link
    my $QueryURL = $Param{TargetURL};

    $LogObject->Log(
        Priority => 'debug',
        Message  => "_GetIncidentNumberFromServiceNow: Querying $QueryURL",
    );

    # Create HTTP request
    my $ua = LWP::UserAgent->new(
        timeout  => 15,
        ssl_opts => { verify_hostname => 1 },
    );

    my $request = HTTP::Request->new( GET => $QueryURL );
    $request->header( 'Content-Type'  => 'application/json' );
    $request->header( 'Authorization' => 'Basic ' . encode_base64( "$Param{APIUser}:$Param{APIPassword}", '' ) );

    # Send request
    my $response = $ua->request($request);

    if ( !$response->is_success ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "_GetIncidentNumberFromServiceNow: Query failed: " . $response->status_line,
        );
        return;
    }

    # Parse response
    my $ResponseData = $JSONObject->Decode(
        Data => $response->content(),
    );

    if ( !$ResponseData || ref($ResponseData) ne 'HASH' ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => '_GetIncidentNumberFromServiceNow: Failed to parse JSON response',
        );
        return;
    }

    # Extract incident number
    my $IncidentNumber = $ResponseData->{result}->{number};

    if ($IncidentNumber) {
        $LogObject->Log(
            Priority => 'info',
            Message  => "_GetIncidentNumberFromServiceNow: Found incident number: $IncidentNumber",
        );
        return $IncidentNumber;
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => "_GetIncidentNumberFromServiceNow: No incident number found yet (incident may still be processing)",
    );

    return;
}

=head2 PullFromServiceNow()

Pull incident updates from MSI CMSO ServiceNow system.

    my ($Success, $UpdateSummary, $ErrorMessage) = $EBondingObject->PullFromServiceNow(
        IncidentID => 123,
        UserID     => 1,
    );

Returns:
    $Success       - 1 on success, 0 on failure
    $UpdateSummary - Summary of updated fields
    $ErrorMessage  - Error details if failed

=cut

sub PullFromServiceNow {
    my ( $Self, %Param ) = @_;

    # Get required objects
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # Check required parameters
    for my $Needed (qw(IncidentID UserID)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "PullFromServiceNow: Need $Needed!",
            );
            return ( 0, undef, "Missing required parameter: $Needed" );
        }
    }

    # Check if eBonding integration is enabled
    my $Enabled = $ConfigObject->Get('EBondingIntegration::Enabled');
    if ( !$Enabled ) {
        my $ErrorMsg = 'eBonding integration is not enabled';
        $LogObject->Log(
            Priority => 'error',
            Message  => "PullFromServiceNow: $ErrorMsg",
        );
        return ( 0, undef, $ErrorMsg );
    }

    # Get current environment and credentials
    my $Environment = $ConfigObject->Get('EBondingIntegration::Environment') || 'reference';
    my $EnvCreds = $EnvironmentCredentials{$Environment} || $EnvironmentCredentials{reference};

    my $APIUser     = $EnvCreds->{APIUser} || '';
    my $APIPassword = $EnvCreds->{APIPassword} || '';

    if ( !$APIUser || !$APIPassword ) {
        my $ErrorMsg = "ServiceNow API credentials not configured for environment: $Environment";
        $LogObject->Log(
            Priority => 'error',
            Message  => "PullFromServiceNow: $ErrorMsg",
        );
        return ( 0, undef, $ErrorMsg );
    }

    $LogObject->Log(
        Priority => 'debug',
        Message  => "PullFromServiceNow: Using environment '$Environment'",
    );

    # Get incident details
    my %Incident = $TicketObject->TicketGet(
        TicketID      => $Param{IncidentID},
        DynamicFields => 1,
        UserID        => $Param{UserID},
    );

    if ( !%Incident ) {
        my $ErrorMsg = "Incident $Param{IncidentID} not found";
        $LogObject->Log(
            Priority => 'error',
            Message  => "PullFromServiceNow: $ErrorMsg",
        );
        return ( 0, undef, $ErrorMsg );
    }

    # Check if incident has stored MSI URL (new field) or fall back to constructing from sys_id (old field)
    my $QueryURL = $Incident{DynamicField_MSITicketURL} || '';
    my $MSITicketSysID = $Incident{DynamicField_MSITicketSysID} || '';

    # If no URL stored, try to construct it from APIURL + sys_id (fallback for old tickets)
    if ( !$QueryURL ) {
        if ( !$MSITicketSysID ) {
            my $ErrorMsg = 'Incident not linked to MSI ServiceNow (no URL or sys_id stored)';
            $LogObject->Log(
                Priority => 'notice',
                Message  => "PullFromServiceNow: $ErrorMsg for incident $Param{IncidentID}",
            );
            return ( 0, undef, $ErrorMsg );
        }

        # Construct URL from environment APIURL + sys_id (fallback)
        my $APIURL = $EnvCreds->{APIURL} || '';
        if ( !$APIURL ) {
            my $ErrorMsg = "ServiceNow API URL not configured for environment: $Environment";
            $LogObject->Log(
                Priority => 'error',
                Message  => "PullFromServiceNow: $ErrorMsg",
            );
            return ( 0, undef, $ErrorMsg );
        }
        $QueryURL = $APIURL . '/' . $MSITicketSysID;
    }

    # Add query parameter to get display values for human-readable fields
    my $QueryURLWithParams = $QueryURL;
    if ($QueryURL =~ /\?/) {
        $QueryURLWithParams .= '&sysparm_display_value=all';
    } else {
        $QueryURLWithParams .= '?sysparm_display_value=all';
    }

    $LogObject->Log(
        Priority => 'debug',
        Message  => "PullFromServiceNow: Querying $QueryURLWithParams",
    );

    # Create HTTP request - GET with sys_id in URL path (standard REST)
    my $ua = LWP::UserAgent->new(
        timeout  => 30,
        ssl_opts => { verify_hostname => 1 },
    );

    my $request = HTTP::Request->new( GET => $QueryURLWithParams );
    $request->header( 'Content-Type'  => 'application/json' );
    $request->header( 'Authorization' => 'Basic ' . encode_base64( "$APIUser:$APIPassword", '' ) );

    # Send request
    my $response = $ua->request($request);
    my $ResponseTime = $TimeObject->CurrentTimestamp();

    # Parse response
    my $Success        = 0;
    my $UpdateSummary  = '';
    my $ErrorMessage   = undef;
    my $ResponsePayload = $response->content();
    my $ResponseStatus  = $response->code();

    if ( $response->is_success ) {
        # Parse JSON response
        my $ResponseData = $JSONObject->Decode(
            Data => $ResponsePayload,
        );

        if ( $ResponseData && ref($ResponseData) eq 'HASH' ) {
            my $Result = $ResponseData->{result} || {};

            # Store old values for comparison
            my %OldValues = (
                MSITicketState           => $Incident{DynamicField_MSITicketState} || '',
                MSITicketPriority        => $Incident{DynamicField_MSITicketPriority} || '',
                MSITicketAssignee        => $Incident{DynamicField_MSITicketAssignee} || '',
                MSITicketShortDescription => $Incident{DynamicField_MSITicketShortDescription} || '',
                MSITicketLastUpdateTime  => $Incident{DynamicField_MSITicketLastUpdateTime} || '',
            );

            # Update MSI dynamic fields
            my $UpdateSuccess = $Self->_UpdateAllMSIFields(
                TicketID           => $Param{IncidentID},
                MSITicketNumber    => $Incident{DynamicField_MSITicketNumber} || '',
                MSITicketSysID     => $Incident{DynamicField_MSITicketSysID} || '',
                MSITicketURL       => $QueryURL,  # Pass URL for storage
                ServiceNowResponse => $Result,
                ResponsePayload    => $ResponsePayload,
                UserID             => $Param{UserID},
            );

            if ($UpdateSuccess) {
                $Success = 1;

                # Build update summary
                my @Changes;

                # Compare state
                # Handle both response formats: nested hash or direct value
                # Response format: "state": { "display_value": "Assigned", "value": "3" }
                my $NewState = '';
                if (ref($Result->{state}) eq 'HASH') {
                    $NewState = $Result->{state}->{display_value} || $Result->{state}->{value} || '';
                } elsif (exists $Result->{state}) {
                    $NewState = $Result->{state} || '';
                }
                # Note: We do NOT use u_state (numeric value only)
                if ($NewState && $NewState ne $OldValues{MSITicketState}) {
                    push @Changes, "State: $OldValues{MSITicketState} -> $NewState";
                }

                # Compare priority
                # Handle both response formats: nested hash or direct value
                # Response format: "priority": { "display_value": "P2", "value": "2" }
                my $NewPriority = '';
                if (ref($Result->{priority}) eq 'HASH') {
                    $NewPriority = $Result->{priority}->{display_value} || $Result->{priority}->{value} || '';
                } elsif (exists $Result->{priority}) {
                    $NewPriority = $Result->{priority} || '';
                }
                if ($NewPriority && $NewPriority ne $OldValues{MSITicketPriority}) {
                    push @Changes, "Priority: $OldValues{MSITicketPriority} -> $NewPriority";
                }

                # Compare assigned_to (individual assignee)
                # Handle both response formats: nested hash or direct value
                my $NewAssignee = '';
                if (ref($Result->{assigned_to}) eq 'HASH') {
                    $NewAssignee = $Result->{assigned_to}->{display_value} || '';
                } elsif (exists $Result->{assigned_to}) {
                    $NewAssignee = $Result->{assigned_to} || '';
                }
                if ($NewAssignee && $NewAssignee ne $OldValues{MSITicketAssignee}) {
                    push @Changes, "Assignee: $OldValues{MSITicketAssignee} -> $NewAssignee";
                }

                # Compare last update time
                # Handle both response formats: nested hash or direct value
                my $NewUpdateTime = '';
                if (ref($Result->{sys_updated_on}) eq 'HASH') {
                    $NewUpdateTime = $Result->{sys_updated_on}->{display_value} || '';
                } else {
                    $NewUpdateTime = $Result->{sys_updated_on} || '';
                }
                if ($NewUpdateTime && $NewUpdateTime ne $OldValues{MSITicketLastUpdateTime}) {
                    push @Changes, "Last Updated: $NewUpdateTime";
                }

                $UpdateSummary = @Changes ? join(', ', @Changes) : 'No changes detected';

                # Add article to ticket showing the update
                $Self->_AddEBondingUpdateArticle(
                    TicketID      => $Param{IncidentID},
                    Changes       => \@Changes,
                    UpdateTime    => $ResponseTime,
                    UserID        => $Param{UserID},
                );

                $LogObject->Log(
                    Priority => 'info',
                    Message  => "PullFromServiceNow: Successfully pulled updates for incident $Param{IncidentID}. Changes: $UpdateSummary",
                );

                # Pull work notes from ServiceNow sys_journal_field API
                if ($MSITicketSysID) {
                    my $WorkNotesSuccess = $Self->_PullWorkNotesFromServiceNow(
                        IncidentID  => $Param{IncidentID},
                        ElementID   => $MSITicketSysID,
                        APIUser     => $APIUser,
                        APIPassword => $APIPassword,
                        UserID      => $Param{UserID},
                    );

                    if (!$WorkNotesSuccess) {
                        $LogObject->Log(
                            Priority => 'notice',
                            Message  => "PullFromServiceNow: Failed to pull work notes for incident $Param{IncidentID}",
                        );
                    }
                }
            }
            else {
                $ErrorMessage = 'Failed to update MSI dynamic fields';
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "PullFromServiceNow: $ErrorMessage for incident $Param{IncidentID}",
                );
            }
        }
        else {
            $ErrorMessage = 'Failed to parse ServiceNow JSON response';
            $LogObject->Log(
                Priority => 'error',
                Message  => "PullFromServiceNow: $ErrorMessage for incident $Param{IncidentID}",
            );
        }
    }
    else {
        # Try to parse JSON error response
        my $ErrorData = $JSONObject->Decode(
            Data => $ResponsePayload,
        );

        if ( $ErrorData && ref($ErrorData) eq 'HASH' && $ErrorData->{error} ) {
            # ServiceNow returned JSON error
            $ErrorMessage = $ErrorData->{error}->{message} || $ErrorData->{error}->{detail} || $response->status_line;
        }
        else {
            # Non-JSON error or unparseable
            $ErrorMessage = 'ServiceNow API returned error: ' . $response->status_line;
        }

        $LogObject->Log(
            Priority => 'error',
            Message  => "PullFromServiceNow: $ErrorMessage for incident $Param{IncidentID}",
        );
    }

    # Log API request
    $Self->_LogAPIRequest(
        IncidentID         => $Param{IncidentID},
        IncidentNumber     => $Incident{TicketNumber},
        Action             => 'PullFromServiceNow',
        RequestURL         => $QueryURLWithParams,  # Use full query URL with params
        RequestPayload     => '',  # No payload for GET request
        ResponsePayload    => $ResponsePayload,
        ResponseStatusCode => $ResponseStatus,
        MSITicketNumber    => $Incident{DynamicField_MSITicketNumber} || '',
        Success            => $Success,
        ErrorMessage       => $ErrorMessage,
        UserID             => $Param{UserID},
    );

    return ( $Success, $UpdateSummary, $ErrorMessage );
}

=head2 _AddEBondingUpdateArticle()

Add an article to the ticket showing eBonding update from ServiceNow.

    my $Success = $EBondingObject->_AddEBondingUpdateArticle(
        TicketID   => 123,
        Changes    => \@Changes,
        UpdateTime => '2025-01-16 10:30:00',
        UserID     => 1,
    );

Returns 1 on success.

=cut

sub _AddEBondingUpdateArticle {
    my ( $Self, %Param ) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # Check required parameters
    for my $Needed (qw(TicketID Changes UpdateTime UserID)) {
        if ( !defined $Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "_AddEBondingUpdateArticle: Need $Needed!",
            );
            return;
        }
    }

    my $Changes = $Param{Changes};

    # Build article body
    my $Body = "MSI eBonding Update - Synchronized from ServiceNow\n";
    $Body .= "Update Time: $Param{UpdateTime}\n\n";

    if ( @{$Changes} ) {
        $Body .= "Changes Detected:\n";
        for my $Change ( @{$Changes} ) {
            $Body .= "  - $Change\n";
        }
    }
    else {
        $Body .= "No changes detected. Ticket is up-to-date with ServiceNow.\n";
    }

    # Create article
    my $ArticleObject        = $Kernel::OM->Get('Kernel::System::Ticket::Article');
    my $ArticleBackendObject = $ArticleObject->BackendForChannel( ChannelName => 'Internal' );

    my $ArticleID = $ArticleBackendObject->ArticleCreate(
        TicketID             => $Param{TicketID},
        SenderType           => 'system',
        IsVisibleForCustomer => 0,
        HistoryType          => 'AddNote',
        HistoryComment       => 'MSI eBonding Update',
        From                 => 'MSI eBonding Integration',
        Subject              => 'MSI Ebonding Update',
        Body                 => $Body,
        ContentType          => 'text/plain; charset=utf-8',
        UserID               => $Param{UserID},
    );

    if ($ArticleID) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "_AddEBondingUpdateArticle: Added article $ArticleID to ticket $Param{TicketID}",
        );
        return 1;
    }

    $LogObject->Log(
        Priority => 'error',
        Message  => "_AddEBondingUpdateArticle: Failed to add article to ticket $Param{TicketID}",
    );
    return;
}

=head2 _GetProductCategoryTier1()

Get Product Category Tier 1 for ServiceNow API.
For ASTRO/DIMETRA: Returns technology name (ASTRO or DIMETRA)
For WAVE: Returns ProductCat1 value

=cut

sub _GetProductCategoryTier1 {
    my ( $Self, $Incident, $Default ) = @_;

    my $ProductCat1 = $Incident->{'DynamicField_ProductCat1'} || $Default || '';

    # For ASTRO: Extract technology name as Tier 1
    if ( $ProductCat1 eq 'ASTRO Infrastructure' ) {
        return 'ASTRO';
    }

    # For DIMETRA, WAVE or other: Use as-is (direct 1-to-1 mapping)
    return $ProductCat1;
}

=head2 _GetProductCategoryTier2()

Get Product Category Tier 2 for ServiceNow API.
For ASTRO: Returns ProductCat1 (shifted down)
For DIMETRA/WAVE: Returns ProductCat2 (direct mapping)

=cut

sub _GetProductCategoryTier2 {
    my ( $Self, $Incident ) = @_;

    my $ProductCat1 = $Incident->{'DynamicField_ProductCat1'} || '';
    my $ProductCat2 = $Incident->{'DynamicField_ProductCat2'} || '';

    # For ASTRO: Shift ProductCat1 down to Tier 2
    if ( $ProductCat1 eq 'ASTRO Infrastructure' ) {
        return $ProductCat1;
    }

    # For DIMETRA, WAVE or other: Use ProductCat2 (direct mapping)
    return $ProductCat2;
}

=head2 _GetProductCategoryTier3()

Get Product Category Tier 3 for ServiceNow API.
For ASTRO: Returns ProductCat2 (shifted down)
For DIMETRA/WAVE: Returns ProductCat3 (direct mapping)

=cut

sub _GetProductCategoryTier3 {
    my ( $Self, $Incident ) = @_;

    my $ProductCat1 = $Incident->{'DynamicField_ProductCat1'} || '';
    my $ProductCat2 = $Incident->{'DynamicField_ProductCat2'} || '';
    my $ProductCat3 = $Incident->{'DynamicField_ProductCat3'} || '';

    # For ASTRO: Shift ProductCat2 down to Tier 3
    if ( $ProductCat1 eq 'ASTRO Infrastructure' ) {
        return $ProductCat2;
    }

    # For DIMETRA, WAVE or other: Use ProductCat3 (direct mapping)
    return $ProductCat3;
}

=head2 _GetProductCategoryTier4()

Get Product Category Tier 4 for ServiceNow API.
For ASTRO: Returns ProductCat3 (shifted down)
For DIMETRA/WAVE: Returns ProductCat4 (direct mapping)

=cut

sub _GetProductCategoryTier4 {
    my ( $Self, $Incident ) = @_;

    my $ProductCat1 = $Incident->{'DynamicField_ProductCat1'} || '';
    my $ProductCat3 = $Incident->{'DynamicField_ProductCat3'} || '';
    my $ProductCat4 = $Incident->{'DynamicField_ProductCat4'} || '';

    # For ASTRO: Shift ProductCat3 down to Tier 4
    if ( $ProductCat1 eq 'ASTRO Infrastructure' ) {
        return $ProductCat3;
    }

    # For DIMETRA, WAVE or other: Use ProductCat4 (direct mapping)
    return $ProductCat4;
}

=head2 _PullWorkNotesFromServiceNow()

Pull work notes from ServiceNow sys_journal_field API and store in msi_work_notes table.

    my $Success = $EBondingObject->_PullWorkNotesFromServiceNow(
        IncidentID  => 123,
        ElementID   => 'b922a40b2b3cfe1041f9f5366e91bf52',  # ServiceNow incident sys_id
        APIUser     => 'username',
        APIPassword => 'password',
        UserID      => 1,
    );

Returns 1 on success, 0 on failure.

=cut

sub _PullWorkNotesFromServiceNow {
    my ( $Self, %Param ) = @_;

    my $LogObject  = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject   = $Kernel::OM->Get('Kernel::System::DB');
    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # Check required parameters
    for my $Needed (qw(IncidentID ElementID APIUser APIPassword UserID)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "_PullWorkNotesFromServiceNow: Need $Needed!",
            );
            return 0;
        }
    }

    # Build ServiceNow sys_journal_field API endpoint
    # Get current environment and credentials
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $Environment = $ConfigObject->Get('EBondingIntegration::Environment') || 'reference';
    my $EnvCreds = $EnvironmentCredentials{$Environment} || $EnvironmentCredentials{reference};
    my $APIURL = $EnvCreds->{APIURL} || '';

    # Extract base URL (everything up to /api/now/table/)
    my $BaseURL = $APIURL;
    if ( $APIURL =~ m{^(https?://[^/]+/api/now/table)} ) {
        $BaseURL = $1;
    }

    # Build work notes query URL
    my $QueryURL = $BaseURL . '/sys_journal_field?sysparm_query=element_id%3D' . $Param{ElementID};

    $LogObject->Log(
        Priority => 'debug',
        Message  => "_PullWorkNotesFromServiceNow: Querying $QueryURL",
    );

    # Create HTTP request
    my $ua = LWP::UserAgent->new(
        timeout  => 30,
        ssl_opts => { verify_hostname => 1 },
    );

    my $request = HTTP::Request->new( GET => $QueryURL );
    $request->header( 'Accept'        => 'application/json' );
    $request->header( 'Authorization' => 'Basic ' . encode_base64( "$Param{APIUser}:$Param{APIPassword}", '' ) );

    # Send request
    my $response = $ua->request($request);

    if ( !$response->is_success ) {
        my $ErrorMessage = "API request failed: " . $response->status_line;
        $LogObject->Log(
            Priority => 'error',
            Message  => "_PullWorkNotesFromServiceNow: $ErrorMessage",
        );

        # Log API request failure
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
        my %Ticket = $TicketObject->TicketGet(
            TicketID => $Param{IncidentID},
            UserID   => $Param{UserID},
        );

        $Self->_LogAPIRequest(
            IncidentID         => $Param{IncidentID},
            IncidentNumber     => $Ticket{TicketNumber} || '',
            Action             => 'PullWorkNotesFromServiceNow',
            RequestURL         => $QueryURL,
            RequestPayload     => '',  # No payload for GET request
            ResponsePayload    => $response->content(),
            ResponseStatusCode => $response->code(),
            MSITicketNumber    => '',  # Not applicable for work notes
            Success            => 0,
            ErrorMessage       => $ErrorMessage,
            UserID             => $Param{UserID},
        );

        return 0;
    }

    # Parse response
    my $ResponseData = $JSONObject->Decode(
        Data => $response->content(),
    );

    if ( !$ResponseData || ref($ResponseData) ne 'HASH' || !$ResponseData->{result} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => '_PullWorkNotesFromServiceNow: Failed to parse JSON response or missing result',
        );
        return 0;
    }

    my $WorkNotesArray = $ResponseData->{result};
    my $InsertCount = 0;
    my $UpdateCount = 0;

    # Process each journal entry (comments and work_notes)
    for my $Note ( @{$WorkNotesArray} ) {
        # Skip entries without element type
        next if !$Note->{element};

        my $SysID = $Note->{sys_id} || '';
        next if !$SysID;

        # Check if note already exists
        return 0 if !$DBObject->Prepare(
            SQL   => 'SELECT id FROM msi_work_notes WHERE msi_sys_id = ?',
            Bind  => [ \$SysID ],
            Limit => 1,
        );

        my $Exists = 0;
        while ( my @Row = $DBObject->FetchrowArray() ) {
            $Exists = 1;
        }

        # Parse timestamps
        my $CreatedTime = $Note->{sys_created_on} || '';
        my $UpdatedTime = $Note->{u_updated_on} || $Note->{sys_created_on} || '';

        if ($Exists) {
            # Update existing record
            my $ElementType = $Note->{element} || '';
            return 0 if !$DBObject->Do(
                SQL => 'UPDATE msi_work_notes SET '
                    . 'note_text = ?, '
                    . 'updated_by = ?, '
                    . 'updated_time = ?, '
                    . 'element_type = ?, '
                    . 'synced_time = current_timestamp '
                    . 'WHERE msi_sys_id = ?',
                Bind => [
                    \$Note->{value},
                    \$Note->{u_updated_by},
                    \$UpdatedTime,
                    \$ElementType,
                    \$SysID,
                ],
            );
            $UpdateCount++;
        }
        else {
            # Insert new record
            my $ElementType = $Note->{element} || '';
            return 0 if !$DBObject->Do(
                SQL => 'INSERT INTO msi_work_notes '
                    . '(ticket_id, msi_sys_id, element_id, element_type, note_text, created_by, updated_by, created_time, updated_time, synced_time) '
                    . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp)',
                Bind => [
                    \$Param{IncidentID},
                    \$SysID,
                    \$Param{ElementID},
                    \$ElementType,
                    \$Note->{value},
                    \$Note->{sys_created_by},
                    \$Note->{u_updated_by},
                    \$CreatedTime,
                    \$UpdatedTime,
                ],
            );
            $InsertCount++;
        }
    }

    $LogObject->Log(
        Priority => 'info',
        Message  => "_PullWorkNotesFromServiceNow: Successfully processed work notes for incident $Param{IncidentID}. Inserted: $InsertCount, Updated: $UpdateCount",
    );

    # Log API request
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{IncidentID},
        UserID   => $Param{UserID},
    );

    $Self->_LogAPIRequest(
        IncidentID         => $Param{IncidentID},
        IncidentNumber     => $Ticket{TicketNumber} || '',
        Action             => 'PullWorkNotesFromServiceNow',
        RequestURL         => $QueryURL,
        RequestPayload     => '',  # No payload for GET request
        ResponsePayload    => $response->content(),
        ResponseStatusCode => $response->code(),
        MSITicketNumber    => '',  # Not applicable for work notes
        Success            => 1,
        ErrorMessage       => undef,
        UserID             => $Param{UserID},
    );

    return 1;
}

=head2 GetMSIWorkNotes()

Get MSI work notes for a ticket from the msi_work_notes table.

    my @WorkNotes = $EBondingObject->GetMSIWorkNotes(
        TicketID => 123,
    );

Returns array of work note hashes with:
    - ID
    - NoteText
    - CreatedBy
    - UpdatedBy
    - CreatedTime
    - UpdatedTime
    - SyncedTime

=cut

sub GetMSIWorkNotes {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');

    # Check required parameters
    if ( !$Param{TicketID} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'GetMSIWorkNotes: Need TicketID!',
        );
        return;
    }

    # Query only comments (filter out work_notes) ordered by creation time (newest first)
    # Include NULL element_type for backwards compatibility with existing data
    return if !$DBObject->Prepare(
        SQL => 'SELECT id, note_text, created_by, updated_by, created_time, updated_time, synced_time '
            . 'FROM msi_work_notes '
            . 'WHERE ticket_id = ? AND (element_type = \'comments\' OR element_type IS NULL) '
            . 'ORDER BY created_time DESC',
        Bind => [ \$Param{TicketID} ],
    );

    my @WorkNotes;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @WorkNotes, {
            ID          => $Row[0],
            NoteText    => $Row[1] || '',
            CreatedBy   => $Row[2] || '',
            UpdatedBy   => $Row[3] || '',
            CreatedTime => $Row[4] || '',
            UpdatedTime => $Row[5] || '',
            SyncedTime  => $Row[6] || '',
        };
    }

    return @WorkNotes;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST Lite project.

This software comes with ABSOLUTELY NO WARRANTY.

=cut
