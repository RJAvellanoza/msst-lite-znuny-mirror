# --
# Kernel/Config/Files/ZZZZOutputFilters.pm
# Output filter template configurations to improve performance
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Config::Files::ZZZZOutputFilters;

use strict;
use warnings;

use utf8;

sub Load {
    my ($File, $Self) = @_;

    # ---------------------------------------------------------------------
    # License Expiration Notification Filter
    # ---------------------------------------------------------------------
    # This filter displays license expiration warnings across agent interface
    # It should run on all Agent pages where the banner needs to appear
    # Running on Footer ensures it appears on all pages that use the standard footer
    # ---------------------------------------------------------------------
    $Self->{'Frontend::Output::FilterContent'}->{LicenseExpirationNotification} = {
        Module => 'Kernel::Output::HTML::FilterContent::LicenseExpirationNotification',
        Templates => {
            'Footer' => 1,
        },
    };

    # ---------------------------------------------------------------------
    # MSST Lite Version Footer Filter
    # ---------------------------------------------------------------------
    # This filter displays the MSST Lite version number in the footer
    # It should run on all Agent and Admin pages
    # Running on Footer ensures it appears consistently across the entire interface
    # ---------------------------------------------------------------------
    $Self->{'Frontend::Output::FilterContent'}->{MSSTLiteVersionFooter} = {
        Module => 'Kernel::Output::HTML::FilterContent::MSSTLiteVersionFooter',
        Templates => {
            'Footer' => 1,
        },
    };

    # ---------------------------------------------------------------------
    # Admin Access Control Filter
    # ---------------------------------------------------------------------
    # This filter controls access to admin functions based on group membership
    # It should run on all admin pages via the Header template
    # ---------------------------------------------------------------------
    $Self->{'Frontend::Output::FilterContent'}->{AdminAccessControl} = {
        Module => 'Kernel::Output::HTML::FilterContent::AdminAccessControl',
        Templates => {
            'Header' => 1,
        },
    };

    # ---------------------------------------------------------------------
    # Hide Admin Links Filter
    # ---------------------------------------------------------------------
    # This filter hides the Links widget on the Admin dashboard
    # It should run on the AdminDashboard template only
    # ---------------------------------------------------------------------
    $Self->{'Frontend::Output::FilterContent'}->{HideAdminLinks} = {
        Module => 'Kernel::Output::HTML::FilterContent::HideAdminLinks',
        Templates => {
            'AdminDashboard' => 1,
        },
    };

    # ---------------------------------------------------------------------
    # Hide Escalation View Settings Icon - DISABLED
    # ---------------------------------------------------------------------
    # This filter hides the column settings icon on escalation view to lock columns
    # Commented out to restore settings icon functionality
    # ---------------------------------------------------------------------
    # $Self->{'Frontend::Output::FilterContent'}->{HideEscalationViewSettings} = {
    #     Module => 'Kernel::Output::HTML::FilterContent::HideEscalationViewSettings',
    #     Templates => {
    #         'AgentTicketOverviewNavBar' => 1,
    #     },
    # };

    # ---------------------------------------------------------------------
    # Escalation View Bulk Update Checkboxes (MSSTLITE-345)
    # ---------------------------------------------------------------------
    # This filter injects checkboxes into the escalation view ticket table
    # for bulk update functionality
    # ---------------------------------------------------------------------
    $Self->{'Frontend::Output::FilterContent'}->{EscalationViewBulkUpdate} = {
        Module => 'Kernel::Output::HTML::FilterContent::EscalationViewBulkUpdate',
        Templates => {
            'AgentTicketOverviewSmall' => 1,
            'AgentTicketOverviewMedium' => 1,
            'AgentTicketOverviewPreview' => 1,
        },
    };

    # ---------------------------------------------------------------------
    # Hide Statistics Menu Item
    # ---------------------------------------------------------------------
    # This filter hides the Statistics menu item from the Reports menu
    # ---------------------------------------------------------------------
    $Self->{'Frontend::Output::FilterContent'}->{HideStatisticsMenu} = {
        Module => 'Kernel::Output::HTML::FilterContent::HideStatisticsMenu',
        Templates => {
            'Header' => 1,
        },
    };

    # ---------------------------------------------------------------------
    # Fix Column Settings Redirect - Fixes redirect to dashboard issue
    # ---------------------------------------------------------------------
    # This filter fixes column settings redirect for ALL ticket overview views.
    # Without this, saving column settings redirects to dashboard instead of current view.
    # The filter updates the RedirectURL field to use the FULL current URL including all query parameters.
    # ---------------------------------------------------------------------
    $Self->{'Frontend::Output::FilterContent'}->{FixColumnSettingsRedirect} = {
        Module => 'Kernel::Output::HTML::FilterContent::FixColumnSettingsRedirect',
        Templates => {
            'AgentTicketOverviewNavBar' => 1,
        },
    };

    return 1;
}

1;
