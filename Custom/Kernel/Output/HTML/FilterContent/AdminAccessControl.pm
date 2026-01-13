package Kernel::Output::HTML::FilterContent::AdminAccessControl;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::User',
    'Kernel::System::Web::Request',
    'Kernel::System::Group',
    'Kernel::System::Cache',
    'Kernel::System::Log',
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
    return 1 if ${ $Param{Data} } !~ m{<body}si;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    return 1 if !$ConfigObject->Get('AdminAccessControl::Enabled');

    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action      = $ParamObject->GetParam( Param => 'Action' ) || '';
    return 1 if $Action ne 'Admin';

    # User context
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $UserID       = $LayoutObject->{UserID} || 0;
    return 1 if !$UserID; # anonymous or missing context

    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my %UserData   = $UserObject->GetUserData( UserID => $UserID );
    my $UserLogin  = $UserData{UserLogin} || '';

    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    # Read configuration
    my $RestrictedGroups = $ConfigObject->Get('AdminAccessControl::RestrictedGroups') || [];
    my $RestrictedLogins = $ConfigObject->Get('AdminAccessControl::RestrictedLogins') || [];

    # Cache key per-user
    my $CacheKey   = 'AdminAccessControl_IsRestricted_UserID_' . $UserID;
    my $CacheType  = 'AdminAccessControl';
    my $IsRestricted = $CacheObject->Get( Type => $CacheType, Key => $CacheKey );

    if ( !defined $IsRestricted ) {
        # Group-based check
        my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
        my %GroupsRW    = $GroupObject->GroupMemberList( UserID => $UserID, Type => 'rw', Result => 'HASH' );
        my %GroupsRO    = $GroupObject->GroupMemberList( UserID => $UserID, Type => 'ro', Result => 'HASH' );
        my %AllGroups   = ( %GroupsRW, %GroupsRO );

        my %GroupNameLC;
        for my $GroupName ( values %AllGroups ) {
            $GroupNameLC{ lc($GroupName // '') } = 1;
        }

        $IsRestricted = 0;
        if ( ref $RestrictedGroups eq 'ARRAY' ) {
            for my $NeedGroup ( @{$RestrictedGroups} ) {
                next if !defined $NeedGroup || $NeedGroup eq '';
                if ( $GroupNameLC{ lc($NeedGroup) } ) { $IsRestricted = 1; last }
            }
        }

        # Login-based override from config (not hard-coded in code)
        if ( !$IsRestricted && ref $RestrictedLogins eq 'ARRAY' ) {
            for my $Login (@{$RestrictedLogins}) {
                next if !defined $Login || $Login eq '';
                if ( lc($UserLogin) eq lc($Login) ) { $IsRestricted = 1; last }
            }
        }

        # Cache result using configured TTL (default 900s)
        my $TTL = $ConfigObject->Get('AdminAccessControl::CacheTTL') || 900;
        $CacheObject->Set( Type => $CacheType, Key => $CacheKey, Value => $IsRestricted, TTL => $TTL );
    }

    return 1 if !$IsRestricted;

    $LogObject->Log( Priority => 'debug', Message => "AdminAccessControl: applying restrictions for login=$UserLogin (UserID=$UserID)" );

    my $ContentRef = $Param{Data};

    # Early bailouts to avoid regex work if the expected containers are absent
    return 1 if ${$ContentRef} !~ m{<div\b[^>]*class="[^"]*\bWidgetSimple\b}i;
    return 1 if ${$ContentRef} !~ m{<div\b[^>]*class="[^"]*\bHeader\b}i;

    # 1) Ticket Settings: keep only Queues (AdminQueue), then remove the section wrapper
    ${$ContentRef} =~ s{
        (               # $1: opening and header of the Ticket Settings widget
            <div\b[^>]*class="[^"]*\bWidgetSimple\b[^"]*"[^>]*>\s*
            <div\b[^>]*class="[^"]*\bHeader\b[^"]*"[^>]*>\s*
            <h[23][^>]*>\s*Ticket\s*Settings\s*<\/h[23]>\s*
            <\/div>\s*
        )
        (               # $2: the Content div including the list
            <div\b[^>]*class="[^"]*\bContent\b[^"]*"[^>]*>[\s\S]*?<\/div>
        )
        (\s*<\/div>)   # $3: closing of the WidgetSimple wrapper
    }{
        my $prefix  = $1;
        my $content = $2;
        my $suffix  = $3;
        $content =~ s{<li\b[^>]*>[\s\S]*?<\/li>}{
            my $li = $&;
            (
                $li =~ /\bdata-module=\"AdminQueue\"/ ||
                $li =~ /href=\"[^\"]*Action=AdminQueue\b/ ||
                $li =~ /<span[^>]*class=\"[^\"]*\bTitle\b[^\"]*\"[^>]*>\s*Queues\s*<\/span>/i
            ) ? $li : ''
        }eg;
        $prefix . $content . $suffix;
    }egx;

    # Remove Ticket Settings section entirely if it is now empty
    my $TicketSettingsWidget = qr{
        <div\b[^>]*class="[^"]*\bWidgetSimple\b[^"]*"[^>]*>\s*
            <div\b[^>]*class="[^"]*\bHeader\b[^"]*"[^>]*>\s*
                <h[23][^>]*>\s*Ticket\s*Settings\s*<\/h[23]>\s*
            <\/div>\s*
            <div\b[^>]*class="[^"]*\bContent\b[^"]*"[^>]*>\s*(?:<ul[^>]*>\s*)?(?:<li[^>]*>\s*<\/li>\s*)*(?:<\/ul>\s*)?<\/div>\s*
        <\/div>
    }six;
    ${$ContentRef} =~ s/$TicketSettingsWidget//g;

    # 2) Remove entire sections by header
    my $RemoveSection = sub {
        my ($HeaderPattern) = @_;
        my $Widget = qr{
            <div\b[^>]*class="[^"]*\bWidgetSimple\b[^"]*"[^>]*>\s*
                <div\b[^>]*class="[^"]*\bHeader\b[^"]*"[^>]*>\s*
                    <h[23][^>]*>\s*$HeaderPattern\s*<\/h[23]>\s*
                <\/div>\s*
                <div\b[^>]*class="[^"]*\bContent\b[^"]*"[^>]*>[\s\S]*?<\/div>\s*
            <\/div>
        }six;
        ${$ContentRef} =~ s/$Widget//g;
    };

    # Communication & Notifications; Users, Groups & Roles; Processes & Automation
    $RemoveSection->('Communication\s*(?:&|&amp;)\s*Notifications');
    $RemoveSection->('Users,\s*Groups\s*(?:&|&amp;)\s*Roles');
    $RemoveSection->('Processes\s*(?:&|&amp;)\s*Automation');

    # 3) Administration: keep only Session Management (AdminSession) and SQL Box (AdminSelectBox)
    ${$ContentRef} =~ s{
        (               # $1: opening and header of the Administration widget
            <div\b[^>]*class="[^"]*\bWidgetSimple\b[^"]*"[^>]*>\s*
            <div\b[^>]*class="[^"]*\bHeader\b[^"]*"[^>]*>\s*
            <h[23][^>]*>\s*Administration\s*<\/h[23]>\s*
            <\/div>\s*
        )
        (               # $2: the Content div including the list
            <div\b[^>]*class="[^"]*\bContent\b[^"]*"[^>]*>[\s\S]*?<\/div>
        )
        (\s*<\/div>)   # $3: closing of the WidgetSimple wrapper
    }{
        my $prefix  = $1;
        my $content = $2;
        my $suffix  = $3;
        $content =~ s{<li\b[^>]*>[\s\S]*?<\/li>}{
            my $li = $&;
            (
                $li =~ /\bdata-module=\"AdminSession\"/ ||
                $li =~ /\bdata-module=\"AdminSelectBox\"/ ||
                $li =~ /href=\"[^\"]*Action=AdminSession\b/ ||
                $li =~ /href=\"[^\"]*Action=AdminSelectBox\b/ ||
                $li =~ /<span[^>]*class=\"[^\"]*\bTitle\b[^\"]*\"[^>]*>\s*Session\s*Management\s*<\/span>/i ||
                $li =~ /<span[^>]*class=\"[^\"]*\bTitle\b[^\"]*\"[^>]*>\s*SQL\s*Box\s*<\/span>/i
            ) ? $li : ''
        }eg;
        $prefix . $content . $suffix;
    }egx;

    return 1;
}

1;