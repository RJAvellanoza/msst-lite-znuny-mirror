# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AgentDashboard;

use strict;
use warnings;

use parent qw( Kernel::Modules::AgentDashboardCommon );

sub Run {
    my ( $Self, %Param ) = @_;

    # Get objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # Check for incident notifications from URL parameters (NOT session!)
    # This ensures they only show ONCE when redirected from incident form
    my $CreatedNotification = $ParamObject->GetParam(Param => 'IncidentCreated') || '';
    my $UpdatedNotification = $ParamObject->GetParam(Param => 'IncidentUpdated') || '';

    # Only show if we have valid values from URL parameters
    my $ShowCreatedNotification = ($CreatedNotification && $CreatedNotification ne '') ? 1 : 0;
    my $ShowUpdatedNotification = ($UpdatedNotification && $UpdatedNotification ne '') ? 1 : 0;

    # ALL users now get the incident dashboard
    # Call the parent (original) AgentDashboard with incident widgets
    my $Output = $Self->SUPER::Run(%Param);

    # If we have notifications, inject them into the output
    if ($ShowCreatedNotification || $ShowUpdatedNotification) {
        my $NotificationHTML = '';

        if ($ShowCreatedNotification) {
            # Build the link to the incident - using the correct format from dashboard widget
            my $IncidentLink = $LayoutObject->{Baselink} . "Action=AgentIncidentForm&Subaction=Update&IncidentNumber=$CreatedNotification";

            $NotificationHTML .= qq{
<div class="MainBox">
    <div class="MessageBox Notice" id="IncidentNotificationBanner" style="margin: 10px 15px; background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; padding: 12px 20px; border-radius: 4px;">
        <p style="margin: 0; font-size: 14px;">
            <i class="fa fa-check-circle" style="margin-right: 8px;"></i>
            <strong>Ticket number <a href="$IncidentLink" style="color: #155724; text-decoration: underline;">$CreatedNotification</a> created</strong>
        </p>
    </div>
</div>
            };
        }
        elsif ($ShowUpdatedNotification) {
            # Build the link to the incident - using the correct format from dashboard widget
            my $IncidentLink = $LayoutObject->{Baselink} . "Action=AgentIncidentForm&Subaction=Update&IncidentNumber=$UpdatedNotification";

            $NotificationHTML .= qq{
<div class="MainBox">
    <div class="MessageBox Notice" id="IncidentNotificationBanner" style="margin: 10px 15px; background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; padding: 12px 20px; border-radius: 4px;">
        <p style="margin: 0; font-size: 14px;">
            <i class="fa fa-check-circle" style="margin-right: 8px;"></i>
            <strong>Ticket number <a href="$IncidentLink" style="color: #155724; text-decoration: underline;">$UpdatedNotification</a> updated</strong>
        </p>
    </div>
</div>
            };
        }

        # Add JavaScript to auto-hide the notification after 10 seconds
        $NotificationHTML .= qq{
<script type="text/javascript">
\$(document).ready(function() {
    // Auto-hide notification after 10 seconds
    setTimeout(function() {
        \$('#IncidentNotificationBanner').fadeOut('slow', function() {
            \$(this).parent('.MainBox').remove();
        });
    }, 10000);
});
</script>
        };

        # Find the proper injection point - after the h1 title and before the dashboard content
        if ($Output =~ m{(<h1[^>]*>.*?</h1>)}si) {
            my $h1 = $1;
            $Output =~ s{(\Q$h1\E)}{$1$NotificationHTML}si;
        } else {
            # Fallback: inject at the beginning of the main content area
            $Output =~ s{(<div[^>]*class="[^"]*MainBox[^"]*Dashboard[^"]*"[^>]*>)}{$1$NotificationHTML}i;
        }
    }

    return $Output;
}

1;
