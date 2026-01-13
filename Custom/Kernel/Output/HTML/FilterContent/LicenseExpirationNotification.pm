# --
# Kernel/Output/HTML/FilterContent/LicenseExpirationNotification.pm
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::FilterContent::LicenseExpirationNotification;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::AdminAddLicense',
    'Kernel::System::DB',
    'Kernel::System::DateTime',
    'Kernel::System::Web::Request',
    'Kernel::System::AuthSession',
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
    
    # Check if we're on an allowed page by looking at the Action parameter
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action = $ParamObject->GetParam( Param => 'Action' ) || '';
    
    # Don't show on login/logout pages
    return 1 if $Action =~ /^(Login|Logout|CustomerLogin|CustomerLogout)$/;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    # Check if notification is enabled
    return 1 if !$ConfigObject->Get('License::ExpirationNotification::Enabled');
    
    # Get the LayoutObject to access session
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $SessionID = $LayoutObject->{SessionID} || '';
    
    # Check if user dismissed notification in this session
    if ($SessionID) {
        my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
        my %SessionData = $SessionObject->GetSessionIDData(
            SessionID => $SessionID,
        );
        
        return 1 if $SessionData{LicenseNotificationDismissed};
    }
    
    # Get license information
    my $AdminAddLicenseObject = $Kernel::OM->Get('Kernel::System::AdminAddLicense');
    my %LicenseList = $AdminAddLicenseObject->AdminAddLicenseList(
        UserID => 1,
        Valid  => 0,
    );
    
    return 1 if !%LicenseList;
    
    # Get configuration values
    my $DaysBeforeExpiry = $ConfigObject->Get('License::ExpirationNotification::DaysBeforeExpiry') || 60;
    my $MessageTemplate = $ConfigObject->Get('License::ExpirationNotification::MessageTemplate') 
        || 'Your license will be expiring in %s days. Please contact Motorola Solutions for service contract renewal.';
    my $ExpiredMessageTemplate = $ConfigObject->Get('License::ExpirationNotification::ExpiredMessageTemplate')
        || 'Your license has expired. Please contact Motorola Solutions for license renewal. Contact number: %s';
    my $ContactNumber = $ConfigObject->Get('License::ExpirationNotification::ContactNumber') || '';
    
    # Check license expiration
    my $ShowNotification = 0;
    my $Message = '';
    my $IsExpired = 0;
    
    if ($LicenseList{endDate}) {
        my $DateTimeObject = $Kernel::OM->Create('Kernel::System::DateTime');
        my $EndDateTimeObject = $Kernel::OM->Create(
            'Kernel::System::DateTime',
            ObjectParams => {
                String => $LicenseList{endDate},
            }
        );
        
        if ($EndDateTimeObject) {
            # Compare dates to determine if expired
            my $Comparison = $EndDateTimeObject->Compare(
                DateTimeObject => $DateTimeObject,
            );
            
            # Get delta for days calculation
            my $Delta = $EndDateTimeObject->Delta(
                DateTimeObject => $DateTimeObject,
            );
            
            if ($Delta && defined $Comparison) {
                # Calculate days remaining (negative if expired)
                my $DaysRemaining = int($Delta->{AbsoluteSeconds} / 86400);
                
                # If end date is in the past, make days negative
                if ($Comparison < 0) {
                    $DaysRemaining = -$DaysRemaining;
                }
                
                # Check if license has expired
                if ($DaysRemaining < 0) {
                    $ShowNotification = 1;
                    $IsExpired = 1;
                    $Message = sprintf($ExpiredMessageTemplate, $ContactNumber);
                }
                # Check if within notification period
                elsif ($DaysRemaining <= $DaysBeforeExpiry) {
                    $ShowNotification = 1;
                    $Message = sprintf($MessageTemplate, $DaysRemaining);
                }
                
                # Debug logging
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'debug',
                    Message  => "LicenseExpirationNotification - EndDate: $LicenseList{endDate}, " .
                                "Comparison: $Comparison, DaysRemaining: $DaysRemaining, " .
                                "IsExpired: $IsExpired, ShowNotification: $ShowNotification",
                );
            }
        }
    }
    
    return 1 if !$ShowNotification;
    
    my $NotificationHTML = $LayoutObject->Output(
        TemplateFile => 'LicenseExpirationNotification',
        Data => {
            Message       => $Message,
            ContactNumber => $ContactNumber,
            IsExpired     => $IsExpired,
        },
    );
    
    # Add JavaScript for handling the dismiss action
    my $JavaScript = qq~
<script type="text/javascript">
//<![CDATA[
(function() {
    function showLicenseNotification() {
        if (typeof jQuery === 'undefined' || typeof Core === 'undefined') {
            setTimeout(showLicenseNotification, 100);
            return;
        }
        
        var notification = document.getElementById('LicenseExpirationNotification');
        var overlay = document.getElementById('LicenseExpirationOverlay');
        
        if (notification && overlay) {
            notification.style.display = 'block';
            overlay.style.display = 'block';
            
            if ($IsExpired) {
                notification.style.borderColor = '#ff0000';
            }
            
            jQuery('#RemindMeLater').on('click', function() {
                notification.style.display = 'none';
                overlay.style.display = 'none';
                
                var sessionID = '$SessionID';
                if (sessionID) {
                    jQuery.ajax({
                        url: Core.Config.Get('Baselink'),
                        type: 'POST',
                        data: {
                            Action: 'AgentLicenseNotificationDismiss',
                            SessionID: sessionID
                        },
                        dataType: 'json'
                    });
                }
            });
        }
    }
    
    showLicenseNotification();
})();
//]]>
</script>
~;
    
    # Insert notification before closing body tag
    ${ $Param{Data} } =~ s{</body>}{$NotificationHTML$JavaScript</body>}si;
    
    return 1;
}

1;