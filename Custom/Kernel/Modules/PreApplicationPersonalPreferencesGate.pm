package Kernel::Modules::PreApplicationPersonalPreferencesGate;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;
    my $Self = {%Param};
    bless( $Self, $Type );
    return $Self;
}

sub PreRun {
    my ( $Self, %Param ) = @_;

    # No user context -> nothing to do
    return if !$Self->{UserID};

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    my $Action    = $ParamObject->GetParam( Param => 'Action' )    || '';
    my $Subaction = $ParamObject->GetParam( Param => 'Subaction' ) || '';
    my $Group     = $ParamObject->GetParam( Param => 'Group' )     || '';
    return if $Action ne 'AgentPreferences';

    # (Removed runtime deletion of Miscellaneous preference keys; no longer altering PreferencesGroups here)

    # Load blocked groups from config
    my $BlockedGroups = $ConfigObject->Get('PersonalPreferences::BlockedGroups') || [ 'msicmso', 'msifield' ];
    return if ref $BlockedGroups ne 'ARRAY' || !@{$BlockedGroups};

    # Build user groups (rw + ro) and map to names
    my %GroupsRW  = $GroupObject->GroupMemberList( UserID => $Self->{UserID}, Type => 'rw', Result => 'HASH' );
    my %GroupsRO  = $GroupObject->GroupMemberList( UserID => $Self->{UserID}, Type => 'ro', Result => 'HASH' );
    my %AllGroups = ( %GroupsRW, %GroupsRO );

    my %UserGroupNamesLC;
    for my $GroupID ( keys %AllGroups ) {
        my $Name = $AllGroups{$GroupID};
        next if !defined $Name || $Name eq '';
        $UserGroupNamesLC{ lc $Name } = 1;
    }

    # Also capture group IDs for matching
    my %UserGroupIDs = map { $_ => 1 } keys %AllGroups;

    # Check membership
    for my $G (@{$BlockedGroups}) {
        next if !defined $G || $G eq '';
        # name match
        if ( $UserGroupNamesLC{ lc $G } ) {
            $LogObject->Log( Priority => 'notice', Message => "PP-Gate: Blocking user $Self->{UserID} (group: $G)" );
            return $LayoutObject->Redirect( OP => 'Action=AgentDashboard' );
        }
        # numeric ID match
        if ( $G =~ /^\d+$/ && $UserGroupIDs{$G} ) {
            $LogObject->Log( Priority => 'notice', Message => "PP-Gate: Blocking user $Self->{UserID} (group id: $G)" );
            return $LayoutObject->Redirect( OP => 'Action=AgentDashboard' );
        }
        # resolve provided as name->id
        my $MaybeID = $GroupObject->GroupLookup( Group => $G );
        if ( $MaybeID && $UserGroupIDs{$MaybeID} ) {
            $LogObject->Log( Priority => 'notice', Message => "PP-Gate: Blocking user $Self->{UserID} (group resolved id: $MaybeID)" );
            return $LayoutObject->Redirect( OP => 'Action=AgentDashboard' );
        }
        # resolve provided as id->name
        my $MaybeName = $GroupObject->GroupLookup( GroupID => $G );
        if ( $MaybeName && $UserGroupNamesLC{ lc $MaybeName } ) {
            $LogObject->Log( Priority => 'notice', Message => "PP-Gate: Blocking user $Self->{UserID} (group resolved name: $MaybeName)" );
            return $LayoutObject->Redirect( OP => 'Action=AgentDashboard' );
        }
    }

    return; # allow normal flow
}

1;

