package Kernel::Modules::NOCDashboard;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;
    my $Self = {%Param};
    bless( $Self, $Type );
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    
    # Check if user is in NOCUser or NOCAdmin group
    my $IsNOCUser = 0;
    my @UserGroups = $GroupObject->GroupMemberList(
        UserID => $Self->{UserID},
        Type   => 'ro',
        Result => 'Name',
    );
    
    # Check if user is in NOC groups
    for my $Group (@UserGroups) {
        if ($Group eq 'NOCUser' || $Group eq 'NOCAdmin') {
            $IsNOCUser = 1;
            last;
        }
    }
    
    # If not a NOC user, redirect to regular dashboard
    if (!$IsNOCUser) {
        return $LayoutObject->Redirect(OP => 'Action=AgentDashboard');
    }
    
    # For NOC users, redirect to regular dashboard
    return $LayoutObject->Redirect(OP => 'Action=AgentDashboard');
}

1; 