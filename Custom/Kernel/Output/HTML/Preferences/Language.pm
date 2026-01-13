# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::Preferences::Language;

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

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
    
    # Check if this should only apply to specific groups
    my $UserLogin = $UserObject->UserLookup( UserID => $Self->{UserID} );
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my @RestrictedGroups = ('NOCAdmin');
    
    
    # TEMPORARY: Also check specific user logins for debugging
    my @RestrictedUsers = ('nocadmin1', 'nocadmin2', 'nocuser1', 'nocuser2', 'nocuser3', 'nocuser4', 'nocuser5', 'nocuser6');
    if (grep { $_ eq $UserLogin } @RestrictedUsers) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Language.pm: User '$UserLogin' is in restricted user list, forcing read-only",
        );
        # Force read-only behavior for these specific users
        my %DefaultUsedLanguages = %{ $ConfigObject->Get('DefaultUsedLanguages') || {} };
        my %DefaultUsedLanguagesNative = %{ $ConfigObject->Get('DefaultUsedLanguagesNative') || {} };

        my %Languages;
        LANGUAGEID:
        for my $LanguageID ( sort keys %DefaultUsedLanguages ) {
            if ( !$DefaultUsedLanguages{$LanguageID} && !$DefaultUsedLanguagesNative{$LanguageID} ) {
                next LANGUAGEID;
            }
            my $Text        = $DefaultUsedLanguagesNative{$LanguageID} || '';
            my $TextEnglish = $DefaultUsedLanguages{$LanguageID}       || '';
            my $TextTranslated = $LayoutObject->{LanguageObject}->Translate($TextEnglish);
            $Languages{$LanguageID} = $Text || $TextTranslated || $TextEnglish;
        }

        my @Params;
        push(
            @Params,
            {
                %Param,
                Name       => $Self->{ConfigItem}->{PrefKey},
                Data       => \%Languages,
                HTMLQuote  => 0,
                SelectedID => 'en',  # Force English (United States)
                Block      => 'Option',
                Max        => 100,
                Disabled   => 1,        # Make it read-only
            },
        );
        return @Params;
    }
    
    # Check if user belongs to any restricted group
    my $IsRestricted = 0;
    for my $GroupName (@RestrictedGroups) {
        my $GroupID = $GroupObject->GroupLookup( Group => $GroupName );
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Language.pm: Checking group '$GroupName', GroupID: " . ($GroupID || 'NOT_FOUND'),
        );
        
        if ($GroupID) {
            # Try different ways to check group membership
            my $UserInGroup = $GroupObject->GroupMemberList(
                GroupID => $GroupID,
                Type    => 'ro',  # Check read-only membership
                Result  => 'HASH',
            );
            
            # Also try with 'rw' (read-write) membership
            my $UserInGroupRW = $GroupObject->GroupMemberList(
                GroupID => $GroupID,
                Type    => 'rw',  # Check read-write membership
                Result  => 'HASH',
            );
            
            my $MemberList = '';
            if (ref($UserInGroup) eq 'HASH') {
                $MemberList = join(', ', keys %{$UserInGroup});
            } else {
                $MemberList = ref($UserInGroup) || 'not_a_hash';
            }
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Language.pm: Group '$GroupName' RO members: $MemberList",
            );
            
            my $MemberListRW = '';
            if (ref($UserInGroupRW) eq 'HASH') {
                $MemberListRW = join(', ', keys %{$UserInGroupRW});
            } else {
                $MemberListRW = ref($UserInGroupRW) || 'not_a_hash';
            }
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Language.pm: Group '$GroupName' RW members: $MemberListRW",
            );
            
            # Check if user is in either RO or RW membership
            if (($UserInGroup && ref($UserInGroup) eq 'HASH' && $UserInGroup->{ $Self->{UserID} }) ||
                ($UserInGroupRW && ref($UserInGroupRW) eq 'HASH' && $UserInGroupRW->{ $Self->{UserID} })) {
                $IsRestricted = 1;
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'notice',
                    Message  => "Language.pm: User $Self->{UserID} found in group '$GroupName' (RO or RW)",
                );
                last;
            }
        } else {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Language.pm: Group '$GroupName' not found, skipping",
            );
        }
    }
    
    # Debug: Log the current user and group status
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "Language.pm: Current user is '$UserLogin', UserID: $Self->{UserID}, IsRestricted: $IsRestricted",
    );
    
    # If user is not in restricted group, use original behavior
    if (!$IsRestricted) {
        # Use original Language module logic for non-restricted users
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Language.pm: User '$UserLogin' is NOT in restricted group, using original behavior",
        );
        return $Self->_OriginalLanguageParam(%Param);
    }
    
    
    # Debug: Log that user is restricted
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "Language.pm: User '$UserLogin' IS in restricted group, using read-only behavior",
    );

    # get names of languages in English
    my %DefaultUsedLanguages = %{ $ConfigObject->Get('DefaultUsedLanguages') || {} };

    # get native names of languages
    my %DefaultUsedLanguagesNative = %{ $ConfigObject->Get('DefaultUsedLanguagesNative') || {} };

    my %Languages;
    LANGUAGEID:
    for my $LanguageID ( sort keys %DefaultUsedLanguages ) {

        # next language if there is not set any name for current language
        if ( !$DefaultUsedLanguages{$LanguageID} && !$DefaultUsedLanguagesNative{$LanguageID} ) {
            next LANGUAGEID;
        }

        # get texts in native and default language
        my $Text        = $DefaultUsedLanguagesNative{$LanguageID} || '';
        my $TextEnglish = $DefaultUsedLanguages{$LanguageID}       || '';

        # translate to current user's language
        my $TextTranslated =
            $LayoutObject->{LanguageObject}->Translate($TextEnglish);

        # use native language name if available, otherwise use English name
        $Languages{$LanguageID} = $Text || $TextTranslated || $TextEnglish;
    }

    my @Params;
    push(
        @Params,
        {
            %Param,
            Name       => $Self->{ConfigItem}->{PrefKey},
            Data       => \%Languages,
            HTMLQuote  => 0,
            SelectedID => 'en',  # Force English (United States)
            Block      => 'Option',
            Max        => 100,
            Disabled   => 1,        # Make it read-only
        },
    );
    return @Params;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get user and group objects
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    
    # Check if this should only apply to specific groups
    my $UserLogin = $UserObject->UserLookup( UserID => $Self->{UserID} );
    my @RestrictedGroups = ('NOCAdmin');
    
    # Check if user belongs to any restricted group
    my $IsRestricted = 0;
    for my $GroupName (@RestrictedGroups) {
        my $GroupID = $GroupObject->GroupLookup( Group => $GroupName );
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Language.pm Run: Checking group '$GroupName', GroupID: " . ($GroupID || 'NOT_FOUND'),
        );
        
        if ($GroupID) {
            # Try different ways to check group membership
            my $UserInGroup = $GroupObject->GroupMemberList(
                GroupID => $GroupID,
                Type    => 'ro',  # Check read-only membership
                Result  => 'HASH',
            );
            
            # Also try with 'rw' (read-write) membership
            my $UserInGroupRW = $GroupObject->GroupMemberList(
                GroupID => $GroupID,
                Type    => 'rw',  # Check read-write membership
                Result  => 'HASH',
            );
            
            my $MemberList = '';
            if (ref($UserInGroup) eq 'HASH') {
                $MemberList = join(', ', keys %{$UserInGroup});
            } else {
                $MemberList = ref($UserInGroup) || 'not_a_hash';
            }
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Language.pm Run: Group '$GroupName' RO members: $MemberList",
            );
            
            my $MemberListRW = '';
            if (ref($UserInGroupRW) eq 'HASH') {
                $MemberListRW = join(', ', keys %{$UserInGroupRW});
            } else {
                $MemberListRW = ref($UserInGroupRW) || 'not_a_hash';
            }
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Language.pm Run: Group '$GroupName' RW members: $MemberListRW",
            );
            
            # Check if user is in either RO or RW membership
            if (($UserInGroup && ref($UserInGroup) eq 'HASH' && $UserInGroup->{ $Self->{UserID} }) ||
                ($UserInGroupRW && ref($UserInGroupRW) eq 'HASH' && $UserInGroupRW->{ $Self->{UserID} })) {
                $IsRestricted = 1;
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'notice',
                    Message  => "Language.pm Run: User $Self->{UserID} found in group '$GroupName' (RO or RW)",
                );
                last;
            }
        } else {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Language.pm Run: Group '$GroupName' not found, skipping",
            );
        }
    }
    
    # Debug: Log the current user and group status in Run method
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "Language.pm Run: Current user is '$UserLogin', UserID: $Self->{UserID}, IsRestricted: $IsRestricted",
    );
    
    # If user is not in restricted group, use original behavior
    if (!$IsRestricted) {
        # Use original Language module logic for non-restricted users
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Language.pm Run: User '$UserLogin' is NOT in restricted group, using original behavior",
        );
        return $Self->_OriginalLanguageRun(%Param);
    }
    
    # Debug: Log that user is restricted in Run method
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "Language.pm Run: User '$UserLogin' IS in restricted group, blocking save",
    );

    # Since the field is read-only for restricted users, we don't actually update anything
    $Self->{Message} = Translatable('Language preference is read-only and managed by system administrators.');
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

sub _OriginalLanguageParam {
    my ( $Self, %Param ) = @_;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get names of languages in English
    my %DefaultUsedLanguages = %{ $ConfigObject->Get('DefaultUsedLanguages') || {} };

    # get native names of languages
    my %DefaultUsedLanguagesNative = %{ $ConfigObject->Get('DefaultUsedLanguagesNative') || {} };

    my %Languages;
    LANGUAGEID:
    for my $LanguageID ( sort keys %DefaultUsedLanguages ) {

        # next language if there is not set any name for current language
        if ( !$DefaultUsedLanguages{$LanguageID} && !$DefaultUsedLanguagesNative{$LanguageID} ) {
            next LANGUAGEID;
        }

        # get texts in native and default language
        my $Text        = $DefaultUsedLanguagesNative{$LanguageID} || '';
        my $TextEnglish = $DefaultUsedLanguages{$LanguageID}       || '';

        # translate to current user's language
        my $TextTranslated =
            $LayoutObject->{LanguageObject}->Translate($TextEnglish);

        # use native language name if available, otherwise use English name
        $Languages{$LanguageID} = $Text || $TextTranslated || $TextEnglish;
    }

    my @Params;
    push(
        @Params,
        {
            %Param,
            Name       => $Self->{ConfigItem}->{PrefKey},
            Data       => \%Languages,
            HTMLQuote  => 0,
            SelectedID => $ParamObject->GetParam( Param => $Self->{ConfigItem}->{PrefKey} )
                || $Param{UserData}->{ $Self->{ConfigItem}->{PrefKey} }
                || $ConfigObject->Get('DefaultLanguage')
                || 'en',
            Block => 'Option',
            Max   => 100,
        },
    );
    return @Params;
}

sub _OriginalLanguageRun {
    my ( $Self, %Param ) = @_;

    my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');
    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
    my $ParamObject   = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get params
    my $GetParam = $ParamObject->GetParam( Param => $Self->{ConfigItem}->{PrefKey} );

    if ( !defined $GetParam ) {
        $Self->{Error} = Translatable('No data found.');
        return;
    }

    # update session data
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => $Self->{ConfigItem}->{PrefKey},
        Value     => $GetParam,
    );

    # update preferences
    if ( !$Self->{UserObject}->SetPreferences( UserID => $Self->{UserID}, Key => $Self->{ConfigItem}->{PrefKey}, Value => $GetParam ) ) {
        $Self->{Error} = Translatable('Can\'t update preferences, please contact your administrator.');
        return;
    }

    $Self->{Message} = Translatable('Preferences updated successfully!');
    return 1;
}

1;
