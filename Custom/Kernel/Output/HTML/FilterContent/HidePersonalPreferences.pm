package Kernel::Output::HTML::FilterContent::HidePersonalPreferences;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Web::Request',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Group',
);

sub new {
    my ( $Type, %Param ) = @_;
    my $Self = { %Param };
    bless( $Self, $Type );
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;


    return 1 if !defined $Param{Data};
    return 1 if ref $Param{Data} ne 'SCALAR';
    return 1 if !${ $Param{Data} };

    my $LayoutObject  = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $UserID        = $LayoutObject->{UserID} || 0;
    return 1 if !$UserID;

    my $RequestObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action        = $RequestObject->GetParam( Param => 'Action' )    || '';
    my $Subaction     = $RequestObject->GetParam( Param => 'Subaction' ) || '';

    # Modify AgentPreferences overview and selected admin templates via SysConfig

    my $ContentRef = $Param{Data};

    
    # On AgentPreferences overview: hide widgets using CSS for non-root users
    if ( $Action eq 'AgentPreferences' && $Subaction eq '' ) {
        
        # Try regex approach to hide translation message
        ${$ContentRef} =~ s{<div[^>]*class="SettingDescription"[^>]*>[\s\S]*?translations\.znuny\.org[\s\S]*?</div>}{}gsi;
        ${$ContentRef} =~ s{<a[^>]*href="[^"]*translations\.znuny\.org[^"]*"[^>]*>[\s\S]*?</a>}{}gsi;
        
        # Add CSS to hide translation message for all users and widgets for non-root users
        my $HideCSS = qq{
<style type="text/css">
/* Hide translation message for all users - multiple approaches */
div.SettingDescription:has(a[href*="translations.znuny.org"]) { display: none !important; }
div:has(a[href*="translations.znuny.org"]) { display: none !important; }
a[href*="translations.znuny.org"] { display: none !important; }
        };
        
        # Only hide specific widgets if user is NOT root@localhost (UserID 1)
        if ( $UserID != 1 ) {
            $HideCSS .= qq{
li:has(a[href*="Group=NotificationSettings"]) { display: none !important; }
li:has(a[href*="Group=Miscellaneous"]) { display: none !important; }
            };
        }
        
        $HideCSS .= qq{
</style>
        };
        
        # Insert CSS before closing head tag
        ${$ContentRef} =~ s{(</head>)}{$HideCSS$1}i;
    }

    # Removed Miscellaneous field HTML filtering; handled via PreferencesGroups override

    # On Admin user templates: remove Personal Preferences links ONLY for blocked groups
    if ( $Action eq 'AdminUser' || $Action eq 'AdminUserNOC' || $Action eq 'Admin' ) {
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
        my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');
        my $Blocked      = 0;
        my $BlockedGroups = $ConfigObject->Get('PersonalPreferences::BlockedGroups') || [];
        if ( ref $BlockedGroups eq 'ARRAY' ) {
            my %RW = $GroupObject->GroupMemberList( UserID => $UserID, Type => 'rw', Result => 'HASH' );
            my %RO = $GroupObject->GroupMemberList( UserID => $UserID, Type => 'ro', Result => 'HASH' );
            my %ALL = ( %RW, %RO );
            my %NamesLC; for my $id (keys %ALL) { my $n = $ALL{$id}; next if !defined $n || $n eq ''; $NamesLC{lc $n}=1; }
            for my $g (@{$BlockedGroups}) { next if !defined $g || $g eq ''; if ($NamesLC{lc $g}) { $Blocked = 1; last } }
        }
        
        # Only remove Personal Preferences links if user is in blocked groups
        if ($Blocked) {
            ${$ContentRef} =~ s{<a\b[^>]*href="[^"]*Action=AgentPreferences\b[^"]*"[^>]*>[\s\S]*?<\/a>}{}gsi;
            ${$ContentRef} =~ s{<li\b[^>]*>\s*<a\b[^>]*href="[^"]*Action=AgentPreferences\b[^"]*"[^>]*>[\s\S]*?<\/a>\s*<\/li>}{}gsi;
        }
    }

    # In global header/user menu (when not already on AgentPreferences): remove Personal Preferences link entries for blocked groups only
    if ( $Action ne 'AgentPreferences' ) {
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
        my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');
        my $Blocked      = 0;
        my $BlockedGroups = $ConfigObject->Get('PersonalPreferences::BlockedGroups') || [];
        if ( ref $BlockedGroups eq 'ARRAY' ) {
            my %RW = $GroupObject->GroupMemberList( UserID => $UserID, Type => 'rw', Result => 'HASH' );
            my %RO = $GroupObject->GroupMemberList( UserID => $UserID, Type => 'ro', Result => 'HASH' );
            my %ALL = ( %RW, %RO );
            my %NamesLC; for my $id (keys %ALL) { my $n = $ALL{$id}; next if !defined $n || $n eq ''; $NamesLC{lc $n}=1; }
            for my $g (@{$BlockedGroups}) { next if !defined $g || $g eq ''; if ($NamesLC{lc $g}) { $Blocked = 1; last } }
        }
        if ($Blocked) {
            # Remove menu entry by URL and by label; cover nested spans/icons
            ${$ContentRef} =~ s{<li\b[^>]*>\s*<a\b[^>]*href="[^"]*Action=AgentPreferences\b[^"]*"[^>]*>[\s\S]*?<\/a>\s*<\/li>}{}gsi;
            ${$ContentRef} =~ s{<a\b[^>]*>\s*(?:<[^>]+>\s*)*Personal\s*preferences\s*(?:<[^>]+>\s*)*<\/a>}{}gsi;
            ${$ContentRef} =~ s{<li\b[^>]*class="[^"]*\bUserPreferences\b[^"]*"[^>]*>[\s\S]*?<\/li>}{}gsi;
        }
    }

    return 1;
}

1;

