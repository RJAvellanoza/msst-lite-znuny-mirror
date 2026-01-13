# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::Preferences::UserDetails;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    for my $Needed (qw(UserID UserObject ConfigItem)) {
        die "Got no $Needed!" if !$Self->{$Needed};
    }

    return $Self;
}

sub Param {
    my ( $Self, %Param ) = @_;

    my @Params;
    push(
        @Params,
        {
            %Param,
            Key          => Translatable('Title or salutation'),
            Name         => 'UserTitle',
            Raw          => 1,
            Block        => 'Input',
            SelectedID   => $Param{UserData}->{UserTitle},
        },
        {
            %Param,
            Key          => Translatable('Firstname'),
            Name         => 'UserFirstname',
            Raw          => 1,
            Block        => 'Input',
            SelectedID   => $Param{UserData}->{UserFirstname},
            Class        => 'Modernize Validate_Required',
        },
        {
            %Param,
            Key          => Translatable('Lastname'),
            Name         => 'UserLastname',
            Raw          => 1,
            Block        => 'Input',
            SelectedID   => $Param{UserData}->{UserLastname},
        },
        {
            %Param,
            Key          => Translatable('Email'),
            Name         => 'UserEmail',
            Raw          => 1,
            Block        => 'Input',
            SelectedID => $Param{UserData}->{UserEmail},
        },
        {
            %Param,
            Key          => Translatable('Mobile'),
            Name         => 'UserMobile',
            Raw          => 1,
            Block        => 'Input',
            SelectedID => $Param{UserData}->{UserMobile},
        },
    );
    return @Params;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ConfigObject   = $Kernel::OM->Get('Kernel::Config');
    my $LanguageObject = $Kernel::OM->Get('Kernel::Language');

    for my $Needed (qw(UserFirstname UserLastname UserEmail)) {
        if ( !$Param{GetParam}->{$Needed}->[0] ) {
            $Self->{Error} = $LanguageObject->Translate("Can\'t update User Detais. $Needed Missing ");
            return;
        }
    }

    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my %Userdetails;

    for my $Key (qw(UserTitle UserFirstname UserLastname UserEmail UserMobile))
    {
        $Userdetails{$Key} = $Param{GetParam}->{$Key}->[0] || '';
    }
    $Userdetails{ChangeUserID} = $Self->{UserID};
    $Userdetails{UserID} = $Self->{UserID};
    $Userdetails{ValidID} = 1;
    $Userdetails{UserLogin} = $Self->{UserLogin};

    my $Success = $UserObject->UserUpdate(
        %Userdetails
    );

    return if !$Success;

    # Update session UserFullname to refresh toolbar display immediately
    if ($Self->{SessionID}) {
        my $UserFullname = "$Userdetails{UserFirstname} $Userdetails{UserLastname}";
        my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
        $SessionObject->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => 'UserFullname',
            Value     => $UserFullname,
        );
    }

    # Sync AssignedTo dynamic field with updated user name
    my $SyncObject = $Kernel::OM->Get('Kernel::System::DynamicFieldSync');
    $SyncObject->SyncAssignedToField(
        UserID => $Self->{UserID},
    );

    $Self->{Message} = $LanguageObject->Translate('Preferences updated successfully!');
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

