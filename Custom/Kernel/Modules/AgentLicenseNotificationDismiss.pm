# --
# Kernel/Modules/AgentLicenseNotificationDismiss.pm - AJAX handler for dismissing license notification
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AgentLicenseNotificationDismiss;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
    my $LayoutObject  = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    
    # Update session to mark notification as dismissed
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LicenseNotificationDismissed',
        Value     => 1,
    );
    
    # Return JSON response
    my $JSON = $LayoutObject->JSONEncode(
        Data => {
            Success => 1,
        },
    );
    
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
        Content     => $JSON,
        Type        => 'inline',
        NoCache     => 1,
    );
}

1;