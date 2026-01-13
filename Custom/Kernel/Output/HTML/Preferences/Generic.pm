# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::Preferences::Generic;

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

    # Get the preference key to determine if it should be read-only
    my $PrefKey = $Self->{ConfigItem}->{PrefKey};
    
    # Get user object to check current user
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $UserLogin = $UserObject->UserLookup( UserID => $Self->{UserID} );
    
    # Debug: Log the current user
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "Generic.pm: Current user is '$UserLogin', UserID: $Self->{UserID}, PrefKey: $PrefKey",
    );
    
    # Define which preferences should be read-only for NOC users
    my %ReadOnlyPreferences = (
        'UserLanguage' => 1,
        'UserRefreshTime' => 1,
        'UserCreateNextMask' => 1,
        'UserLastViewsLimit' => 1,
        'UserLastViewsPosition' => 1,
        'UserLastViewsTypes' => 1,
    );

    # Check if this preference should be read-only for the current user
    my $IsReadOnly = 0;
    if ($ReadOnlyPreferences{$PrefKey}) {
        # Check if current user is a NOC user
        my @RestrictedUsers = ('nocadmin1', 'nocadmin2', 'nocuser1', 'nocuser2', 'nocuser3', 'nocuser4', 'nocuser5', 'nocuser6');
        if (grep { $_ eq $UserLogin } @RestrictedUsers) {
            $IsReadOnly = 1;
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Generic.pm: User '$UserLogin' is restricted, making $PrefKey read-only",
            );
        } else {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Generic.pm: User '$UserLogin' is NOT restricted, making $PrefKey editable",
            );
        }
    } else {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Generic.pm: $PrefKey is not in restricted list, making it editable",
        );
    }
    
    # Special handling: Force English US for Language preference (only for NOC users)
    if ($PrefKey eq 'UserLanguage' && $IsReadOnly) {
        $Self->{ConfigItem}->{DataSelected} = 'en';
    }

    # Get the data from the config item
    my $Data = $Self->{ConfigItem}->{Data} || {};
    
    # Special handling for Language preference
    if ($PrefKey eq 'UserLanguage') {
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
            my $TextTranslated = $LayoutObject->{LanguageObject}->Translate($TextEnglish);
            
            # use native language name if available, otherwise use English name
            $Languages{$LanguageID} = $Text || $TextTranslated || $TextEnglish;
        }
        $Data = \%Languages;
        
        # Force the default value for Language preference
        $Self->{ConfigItem}->{DataSelected} = 'en_US';
    }

    my @Params;
    push(
        @Params,
        {
            %Param,
            Name       => $Self->{ConfigItem}->{PrefKey},
            Data       => $Data,
            HTMLQuote  => 0,
            SelectedID => $IsReadOnly 
                ? ( $PrefKey eq 'UserLanguage' ? 'en_US' : ( $Self->{ConfigItem}->{DataSelected} || 'en_US' ) )
                : ( $ParamObject->GetParam( Param => $Self->{ConfigItem}->{PrefKey} )
                    || $Param{UserData}->{ $Self->{ConfigItem}->{PrefKey} }
                    || $Self->{ConfigItem}->{DataSelected} ),
            Block => 'Option',
            Max   => 100,
            # Make the field read-only if it's in our list
            Disabled => $IsReadOnly,
        },
    );
    return @Params;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Get the preference key to determine if it should be read-only
    my $PrefKey = $Self->{ConfigItem}->{PrefKey};
    
    # Get user object to check current user
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $UserLogin = $UserObject->UserLookup( UserID => $Self->{UserID} );
    
    # Debug: Log the current user
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "Generic.pm: Current user is '$UserLogin', UserID: $Self->{UserID}, PrefKey: $PrefKey",
    );
    
    # Define which preferences should be read-only for NOC users
    my %ReadOnlyPreferences = (
        'UserLanguage' => 1,
        'UserRefreshTime' => 1,
        'UserCreateNextMask' => 1,
        'UserLastViewsLimit' => 1,
        'UserLastViewsPosition' => 1,
        'UserLastViewsTypes' => 1,
    );

    # Check if this preference should be read-only for the current user
    my $IsReadOnly = 0;
    if ($ReadOnlyPreferences{$PrefKey}) {
        # Check if current user is a NOC user
        my @RestrictedUsers = ('nocadmin1', 'nocadmin2', 'nocuser1', 'nocuser2', 'nocuser3', 'nocuser4', 'nocuser5', 'nocuser6');
        if (grep { $_ eq $UserLogin } @RestrictedUsers) {
            $IsReadOnly = 1;
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Generic.pm: User '$UserLogin' is restricted, making $PrefKey read-only",
            );
        } else {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Generic.pm: User '$UserLogin' is NOT restricted, making $PrefKey editable",
            );
        }
    } else {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Generic.pm: $PrefKey is not in restricted list, making it editable",
        );
    }

    if ($IsReadOnly) {
        # Since the field is read-only, we don't actually update anything
        $Self->{Message} = Translatable('This preference is read-only and managed by system administrators.');
        return 1;
    }

    # For non-read-only preferences, use the original logic
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

sub Error {
    my ( $Self, %Param ) = @_;

    return $Self->{Error} || '';
}

sub Message {
    my ( $Self, %Param ) = @_;

    return $Self->{Message} || '';
}

1;
