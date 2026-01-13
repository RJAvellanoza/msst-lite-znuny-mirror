# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::CustomerLicenseView;

use strict;
use warnings;

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

    my $LayoutObject        = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $AdminAddLicenseObject = $Kernel::OM->Get('Kernel::System::AdminAddLicense');

    # Get the license list to determine current status
    my %List = $AdminAddLicenseObject->AdminAddLicenseList(
        UserID => 1,
        Valid  => 0,  # Get all licenses, not just valid ones
    );
    
    my $LicenseStatus = 'Unknown';
    my $LicenseData = {};
    
    if (%List) {
        $LicenseStatus = $List{license_status} || 'Unknown';
        
        # The List already contains all the license data
        $LicenseData = {
            UID => $List{UID} || '',
            contractCompany => $List{contractCompany} || '',
            endCustomer => $List{endCustomer} || '',
            contractNumber => $List{contractNumber} || '',
            mcn => $List{mcn} || $List{contractNumber} || '',
            systemTechnology => $List{systemTechnology} || '',
            lsmpSiteID => $List{lsmpSiteID} || '',
            macAddress => $List{macAddress} || '',
            startDate => $List{startDate} || '',
            endDate => $List{endDate} || '',
            remaining_duration => $List{remaining_duration} || '',
        };
    }
    else {
        # No license found
        $LicenseStatus = 'NotFound';
    }

    # Build output
    my $Output = $LayoutObject->Header();
    
    # Only show navigation bar if license is valid
    if ($LicenseStatus eq 'Valid') {
        $Output .= $LayoutObject->NavigationBar();
    }
    
    $LayoutObject->Block(
        Name => 'Overview',
        Data => {
            LicenseStatus => $LicenseStatus,
            %{$LicenseData},
        },
    );
    
    # Show license information block
    if ($LicenseStatus ne 'NotFound') {
        $LayoutObject->Block(
            Name => 'LicenseInfo',
            Data => {
                LicenseStatus => $LicenseStatus,
                %{$LicenseData},
            },
        );
    }
    else {
        $LayoutObject->Block(
            Name => 'NoLicenseFound',
        );
    }
    
    $Output .= $LayoutObject->Output(
        TemplateFile => 'CustomerLicenseView',
        Data         => \%Param,
    );
    $Output .= $LayoutObject->Footer();
    
    return $Output;
}

1;