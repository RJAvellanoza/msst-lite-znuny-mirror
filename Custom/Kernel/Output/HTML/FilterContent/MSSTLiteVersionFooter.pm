# --
# Kernel/Output/HTML/FilterContent/MSSTLiteVersionFooter.pm
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::FilterContent::MSSTLiteVersionFooter;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return 1 if !defined $Param{Data};
    return 1 if ref $Param{Data} ne 'SCALAR';
    return 1 if !${ $Param{Data} };
    
    # Don't run on non-HTML responses
    return 1 if ${ $Param{Data} } !~ m{<body}si;
    
    # Get configuration
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    # Get LSMP version
    my $Version = $ConfigObject->Get('MSSTLite::Version') || 'Unknown';
    
    # Check license status directly if we're on AdminAddLicense page
    my $LicenseCSS = '';
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action = $ParamObject->GetParam( Param => 'Action' ) || '';
    
    if ($Action eq 'AdminAddLicense') {
        # We're on the license page - check if it's because of invalid license
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        
        # Check license status
        my $SQL = "SELECT CASE 
            WHEN NOW() > endDate THEN 'Expired'
            WHEN startDate <= NOW() AND NOW() <= endDate THEN 'Valid'
            ELSE 'Invalid'
        END FROM license LIMIT 1";
        
        my $LicenseStatus = 'NotFound';
        if ($DBObject->Prepare(SQL => $SQL)) {
            while (my @Row = $DBObject->FetchrowArray()) {
                $LicenseStatus = $Row[0] || 'Invalid';
            }
        }
        
        # If license is not valid, add CSS to hide menus
        if ($LicenseStatus ne 'Valid') {
        $LicenseCSS = qq~
<style>
/* Hide main navigation when license is invalid */
body.LicenseInvalid #Navigation,
body.LicenseInvalid #NavigationContainer,
body.LicenseInvalid .MainBox > .Header {
    display: none !important;
}

/* Keep AdminAddLicense navigation visible */
body.LicenseInvalid #Nav-Admin-AdminAddLicense {
    display: block !important;
}

/* IMPORTANT: Keep the license page fully functional */
body.LicenseInvalid.AdminAddLicense .SidebarColumn,
body.LicenseInvalid.AdminAddLicense .WidgetSimple,
body.LicenseInvalid.AdminAddLicense .MainBox {
    display: block !important;
}
</style>
~;
        
        # Add class to body tag
        if (${ $Param{Data} } =~ m{<body([^>]*)>}si) {
            my $BodyAttrs = $1;
            if ($BodyAttrs =~ m{class="([^"]*)"}) {
                my $Classes = $1;
                ${ $Param{Data} } =~ s{<body[^>]*class="[^"]*"}{<body class="$Classes LicenseInvalid"}si;
            } else {
                ${ $Param{Data} } =~ s{<body([^>]*)>}{<body$1 class="LicenseInvalid">}si;
            }
        }
        }
    }
    
    # Create version display HTML
    my $VersionHTML = qq~
<div class="msst-lite-version" style="text-align: center; padding: 10px 0; color: #666; font-size: 11px;">
    Version: $Version
</div>
~;
    
    # Insert CSS in head if license is invalid
    if ($LicenseCSS) {
        if (${ $Param{Data} } =~ m{</head>}si) {
            ${ $Param{Data} } =~ s{</head>}{$LicenseCSS</head>}si;
        }
    }
    
    # Find the footer div and insert version before it
    # Look for the standard OTRS/Znuny footer
    if (${ $Param{Data} } =~ m{(<div[^>]*class="[^"]*Footer[^"]*"[^>]*>)}si) {
        my $FooterDiv = $1;
        ${ $Param{Data} } =~ s{\Q$FooterDiv\E}{$VersionHTML$FooterDiv}si;
    }
    # If no footer found, try to insert before closing body tag
    elsif (${ $Param{Data} } =~ m{</body>}si) {
        ${ $Param{Data} } =~ s{</body>}{$VersionHTML</body>}si;
    }
    
    return 1;
}

1;