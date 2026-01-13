package Kernel::Output::HTML::FilterContent::HideCustomerVisibility;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Web::Request',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Check if we're in a ticket action that might show customer visibility
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action = $ParamObject->GetParam( Param => 'Action' ) || '';
    
    # Only process for relevant actions
    return 1 if $Action !~ /^Agent(Ticket|Incident)/;

    # Remove ArticleIsVisibleForCustomer checkbox and related elements
    ${$Param{Data}} =~ s{
        <label\s+for="ArticleIsVisibleForCustomer"[^>]*>.*?</label>\s*
        <div\s+class="Field"[^>]*>\s*
        <input[^>]*name="ArticleIsVisibleForCustomer"[^>]*>\s*
        .*?
        </div>\s*
        <div\s+class="Clear"></div>
    }{}gxms;
    
    # Also remove from any JavaScript that might reference it
    ${$Param{Data}} =~ s{ArticleIsVisibleForCustomer['"]\s*:\s*['"]?\d+['"]?,?}{}g;

    return 1;
}

1;