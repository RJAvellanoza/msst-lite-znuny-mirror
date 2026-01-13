# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::Preferences::Skin;

use strict;
use warnings;
use utf8;

use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::AuthSession',
    'Kernel::System::Web::Request',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    for my $Needed (qw(UserID UserObject ConfigItem)) {
        $Self->{$Needed} = $Param{$Needed} || die "Got no $Needed!";
    }

    return $Self;
}

sub Param {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
    
    # Check if current user should have read-only skin preference
    my $UserLogin = $UserObject->UserLookup( UserID => $Self->{UserID} );
    my @RestrictedUsers = ('nocadmin1', 'nocadmin2', 'nocuser1', 'nocuser2', 'nocuser3', 'nocuser4', 'nocuser5', 'nocuser6');
    my $IsReadOnly = grep { $_ eq $UserLogin } @RestrictedUsers;
    
    # Debug: Log the current user
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "Skin.pm: Current user is '$UserLogin', UserID: $Self->{UserID}, IsReadOnly: $IsReadOnly",
    );

    my $PossibleSkins = $ConfigObject->Get('Loader::Agent::Skin') || {};
    my $Home          = $ConfigObject->Get('Home');
    my %ActiveSkins;

    # prepare the list of active skins
    for my $PossibleSkin ( values %{$PossibleSkins} ) {
        if (
            $LayoutObject->SkinValidate(
                Skin     => $PossibleSkin->{InternalName},
                SkinType => 'Agent'
            )
            )
        {
            $ActiveSkins{ $PossibleSkin->{InternalName} } = $PossibleSkin->{VisibleName};
        }
    }

    my @Params;
    push(
        @Params,
        {
            %Param,
            Name       => $Self->{ConfigItem}->{PrefKey},
            Data       => \%ActiveSkins,
            HTMLQuote  => 0,
            SelectedID => $ParamObject->GetParam( Param => 'UserSkin' )
                || $Param{UserData}->{UserSkin}
                || $ConfigObject->Get('Loader::Agent::DefaultSelectedSkin'),
            Block => 'Option',
            Max   => 100,
            # Make the field read-only only for NOC users
            Disabled => $IsReadOnly,
        },
    );
    return @Params;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Check if current user should have read-only skin preference
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $UserLogin = $UserObject->UserLookup( UserID => $Self->{UserID} );
    my @RestrictedUsers = ('nocadmin1', 'nocadmin2', 'nocuser1', 'nocuser2', 'nocuser3', 'nocuser4', 'nocuser5', 'nocuser6');
    my $IsReadOnly = grep { $_ eq $UserLogin } @RestrictedUsers;
    
    # Debug: Log the current user
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "Skin.pm Run: Current user is '$UserLogin', UserID: $Self->{UserID}, IsReadOnly: $IsReadOnly",
    );

    if ($IsReadOnly) {
        # Since the field is read-only for NOC users, we don't actually update anything
        $Self->{Message} = Translatable('Skin preference is read-only and managed by system administrators.');
        return 1;
    }
    
    # For non-restricted users, use the original saving logic
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');

    # get parameters from web browser
    my $GetParam = $ParamObject->GetParam( Param => $Self->{ConfigItem}->{PrefKey} );

    # set new value
    if ( defined $GetParam ) {
        $SessionObject->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => $Self->{ConfigItem}->{PrefKey},
            Value     => $GetParam,
        );
    }

    $Self->{Message} = Translatable('Preferences updated successfully!');
    return 1;
}

sub Error {
    my ( $Self, %Param ) = @_;

    return $Self->{Error} || '';
}

sub Message {
    my ( $Self, %Param ) = @_;

    return $Self->{Message} || '';
}

1;
