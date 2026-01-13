# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::Preferences::LastViewsTypes;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::AuthSession',
    'Kernel::System::JSON',
    'Kernel::System::Web::Request',
    'Kernel::System::User',
    'Kernel::System::Group',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    for my $Needed (qw(UserID ConfigItem)) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }

    $Self->{Name} = 'LastViewTypes';

    return $Self;
}

sub Param {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
    
    # Check if this should only apply to specific groups
    my $UserLogin = $UserObject->UserLookup( UserID => $Self->{UserID} );
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my @RestrictedGroups = ('NOCAdmin');
    
    # Check if current user is in restricted groups
    my $IsRestricted = 0;
    for my $GroupName (@RestrictedGroups) {
        my $GroupID = $GroupObject->GroupLookup( Group => $GroupName );
        if ($GroupID) {
            my $UserInGroup = $GroupObject->GroupMemberList( GroupID => $GroupID, Type => 'ro', Result => 'HASH' );
            my $UserInGroupRW = $GroupObject->GroupMemberList( GroupID => $GroupID, Type => 'rw', Result => 'HASH' );
            if (($UserInGroup && ref($UserInGroup) eq 'HASH' && $UserInGroup->{ $Self->{UserID} }) ||
                ($UserInGroupRW && ref($UserInGroupRW) eq 'HASH' && $UserInGroupRW->{ $Self->{UserID} })) {
                $IsRestricted = 1;
                last;
            }
        }
    }
    
    # TEMPORARY: Also check specific user logins for debugging
    my @RestrictedUsers = ('nocadmin1', 'nocadmin2', 'nocuser1', 'nocuser2', 'nocuser3', 'nocuser4', 'nocuser5', 'nocuser6');
    if (!$IsRestricted && grep { $_ eq $UserLogin } @RestrictedUsers) {
        $IsRestricted = 1;
    }
    
    # Log the restriction status
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "LastViewsTypes.pm: User '$UserLogin' is " . ($IsRestricted ? "RESTRICTED" : "NOT RESTRICTED") . " for LastViewsTypes",
    );

    my $Config    = $ConfigObject->Get('LastViews');
    my $Interface = $LayoutObject->{SessionSource} || 'AgentInterface';

    my %LastViewTypes = %{ $Config->{Types}->{$Interface} };
    my @Params;
    my @LastViewTypes;

    if ( $ParamObject->GetArray( Param => $Self->{ConfigItem}->{PrefKey} ) ) {
        @LastViewTypes = $ParamObject->GetArray( Param => $Self->{ConfigItem}->{PrefKey} );
    }
    elsif ( $Param{UserData}->{ $Self->{ConfigItem}->{PrefKey} } ) {
        my $LastViewTypes = $JSONObject->Decode(
            Data => $Param{UserData}->{ $Self->{ConfigItem}->{PrefKey} },
        );
        @LastViewTypes = @{$LastViewTypes};
    }

    my $TypeOption = $LayoutObject->BuildSelection(
        Data           => \%LastViewTypes,
        Name           => $Self->{ConfigItem}->{PrefKey},
        Class          => 'Modernize',
        SelectedID     => \@LastViewTypes,
        Multiple       => 1,
        Translation    => 1,
        OnChangeSubmit => 0,
        OptionTitle    => 1,
        TreeView       => 1,
        Size           => 10,
        Sort           => 'AlphanumericValue',
        Disabled       => $IsRestricted,  # Make it read-only for restricted users
    );

    push(
        @Params,
        {
            %Param,
            Option => $TypeOption,
            Name   => $Self->{ConfigItem}->{PrefKey},
        },
    );
    return @Params;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
    my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');
    my $JSONObject    = $Kernel::OM->Get('Kernel::System::JSON');
    my $UserObject    = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject   = $Kernel::OM->Get('Kernel::System::Group');
    
    # Check if this should only apply to specific groups
    my $UserLogin = $UserObject->UserLookup( UserID => $Self->{UserID} );
    my @RestrictedGroups = ('NOCAdmin');
    
    # Check if current user is in restricted groups
    my $IsRestricted = 0;
    for my $GroupName (@RestrictedGroups) {
        my $GroupID = $GroupObject->GroupLookup( Group => $GroupName );
        if ($GroupID) {
            my $UserInGroup = $GroupObject->GroupMemberList( GroupID => $GroupID, Type => 'ro', Result => 'HASH' );
            my $UserInGroupRW = $GroupObject->GroupMemberList( GroupID => $GroupID, Type => 'rw', Result => 'HASH' );
            if (($UserInGroup && ref($UserInGroup) eq 'HASH' && $UserInGroup->{ $Self->{UserID} }) ||
                ($UserInGroupRW && ref($UserInGroupRW) eq 'HASH' && $UserInGroupRW->{ $Self->{UserID} })) {
                $IsRestricted = 1;
                last;
            }
        }
    }
    
    # TEMPORARY: Also check specific user logins for debugging
    my @RestrictedUsers = ('nocadmin1', 'nocadmin2', 'nocuser1', 'nocuser2', 'nocuser3', 'nocuser4', 'nocuser5', 'nocuser6');
    if (!$IsRestricted && grep { $_ eq $UserLogin } @RestrictedUsers) {
        $IsRestricted = 1;
    }
    
    # Log the restriction status
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "LastViewsTypes.pm Run: User '$UserLogin' is " . ($IsRestricted ? "RESTRICTED" : "NOT RESTRICTED") . " for LastViewsTypes",
    );

    if ($IsRestricted) {
        # Since the field is read-only, we don't actually update anything
        $Self->{Message} = Translatable('This preference is read-only and managed by system administrators.');
        return 1;
    }

    my @LastViewTypes = @{ $Param{GetParam}->{ $Self->{ConfigItem}->{PrefKey} } };

    my $LastViewTypes = $JSONObject->Encode( Data => \@LastViewTypes );

    if ( !$ConfigObject->Get('DemoSystem') ) {
        $Self->{UserObject}->SetPreferences(
            UserID => $Param{UserData}->{UserID},
            Key    => $Self->{ConfigItem}->{PrefKey},
            Value  => $LastViewTypes,
        );
    }

    # Update session data when the preference is updated by the user himself.
    if ( $Param{UpdateSessionData} ) {
        $SessionObject->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => $Self->{ConfigItem}->{PrefKey},
            Value     => $LastViewTypes,
        );
    }
    else {

        # Delete the session when the preference is updated by an admin user
        # to force a login with fresh session data for the affected user.
        $SessionObject->RemoveSessionByUser(
            UserLogin => $Param{UserData}->{UserLogin},
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
