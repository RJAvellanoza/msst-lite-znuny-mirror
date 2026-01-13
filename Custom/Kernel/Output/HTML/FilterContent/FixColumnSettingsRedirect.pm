# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::FilterContent::FixColumnSettingsRedirect;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Web::Request',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action = $ParamObject->GetParam( Param => 'Action' ) || '';

    # Only run on ticket overview pages that have column settings
    return 1 if $Action !~ /^Agent(Ticket|Dashboard)/;

    # Inject JavaScript to fix column settings redirect
    my $JS = q{
<script type="text/javascript">
// Fix column settings redirect to return to current page
Core.App.Ready(function() {
    // Listen for settings dialog being shown
    $(document).on('click', '#ShowContextSettingsDialog', function() {
        setTimeout(function() {
            // Get current URL query string (everything after index.pl?)
            var CurrentURL = window.location.search.substring(1); // Remove leading '?'

            console.log('FixColumnSettingsRedirect: Current URL =', CurrentURL);

            // Find the form - ID pattern is ContextSettingsDialogOverview + View (Small/Medium/Preview)
            var $Forms = $('[id^="ContextSettingsDialogOverview"]');

            if ($Forms.length) {
                $Forms.each(function() {
                    var $Form = $(this);
                    var $RedirectField = $Form.find('input[name="RedirectURL"]');

                    if ($RedirectField.length) {
                        console.log('FixColumnSettingsRedirect: Found form', $Form.attr('id'), 'with RedirectURL =', $RedirectField.val());
                        console.log('FixColumnSettingsRedirect: Updating RedirectURL to:', CurrentURL);
                        $RedirectField.val(CurrentURL);
                    } else {
                        console.log('FixColumnSettingsRedirect: RedirectURL field not found in form', $Form.attr('id'));
                    }
                });
            } else {
                console.log('FixColumnSettingsRedirect: No ContextSettingsDialogOverview forms found');
            }
        }, 500); // Wait for dialog to render
    });
});
</script>
};

    # Inject before closing body tag
    ${ $Param{Data} } =~ s{</body>}{$JS</body>}xmsi;

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the MSST Lite project.

This software comes with ABSOLUTELY NO WARRANTY.

=cut
