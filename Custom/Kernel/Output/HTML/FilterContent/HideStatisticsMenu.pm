# --
# Copyright (C) 2025 MSST, https://msst.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package Kernel::Output::HTML::FilterContent::HideStatisticsMenu;

use strict;
use warnings;

our @ObjectDependencies = ();

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Return if no Data parameter
    return 1 if !$Param{Data};
    return 1 if ref $Param{Data} ne 'SCALAR';

    # Get template content
    my $Content = ${ $Param{Data} };

    # Add JavaScript to hide Statistics menu item
    my $JavaScript = q{
<script type="text/javascript">
    $(document).ready(function() {
        // Hide Statistics menu item
        $('#nav-Reports-Statistics').remove();
    });
</script>
};

    # Inject before </body>
    $Content =~ s{(</body>)}{$JavaScript$1}i;

    # Update content
    ${ $Param{Data} } = $Content;

    return 1;
}

1;
