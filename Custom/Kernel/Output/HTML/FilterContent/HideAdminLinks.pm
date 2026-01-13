package Kernel::Output::HTML::FilterContent::HideAdminLinks;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Web::Request',
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
    return 1 if !$ConfigObject->Get('HideAdminLinks::Enabled');

    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action      = $ParamObject->GetParam( Param => 'Action' ) || '';
    return 1 if $Action ne 'Admin';

    my $ContentRef = $Param{Data};

    # Remove the widget whose header is exactly "Links"
    my $WidgetExact = qr{
        <div\b[^>]*class="[^"]*\bWidgetSimple\b[^"]*"[^>]*>\s*
            <div\b[^>]*class="[^"]*\bHeader\b[^"]*"[^>]*>\s*
                <h[23][^>]*>\s*Links\s*<\/h[23]>\s*
            <\/div>\s*
            <div\b[^>]*class="[^"]*\bContent\b[^"]*"[^>]*>[\s\S]*?<\/div>
        \s*<\/div>
    }six;

    if (${$ContentRef} !~ s/$WidgetExact//g) {
        # Fallback: remove just the anchor with the admin manual
        ${$ContentRef} =~ s{<a[^>]*>\s*(?:<[^>]+>\s*)*View\s+the\s+admin\s+manual\s+on\s+Git(H|h)ub\s*(?:<[^>]+>\s*)*<\/a>}{}g;
    }

    return 1;
}

1;