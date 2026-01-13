# --
# Kernel/Modules/PreApplicationLicenseCheck.pm - Enforce license validity with redirects
# Copyright (C) 2025 MSST
# --
# This version enforces license checking with server-side redirects
# --

package Kernel::Modules::PreApplicationLicenseCheck;

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
    
    # Get needed objects
    my $ConfigObject   = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject   = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $LogObject      = $Kernel::OM->Get('Kernel::System::Log');
    my $ParamObject    = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $DBObject       = $Kernel::OM->Get('Kernel::System::DB');
    
    # Check if license checking is enabled
    my $LicenseCheckEnabled = $ConfigObject->Get('LicenseCheck::Enabled');
    return if !$LicenseCheckEnabled;
    
    # Skip if no user is logged in
    return if !$Self->{UserID};
    
    # Skip for certain actions (login/logout already handled by framework)
    my $Action = $ParamObject->GetParam( Param => 'Action' ) || '';
    return if $Action =~ /^(Login|Logout|CustomerLogin|CustomerLogout)$/;
    
    # Check if current action is already the license page to avoid redirect loops
    return if $Action eq 'AdminAddLicense' || $Action eq 'CustomerLicenseView';
    
    # Get fresh license status directly from database
    # Check database type
    my $DatabaseType = $DBObject->GetDatabaseFunction('Type');
    
    my $SQL;
    if ($DatabaseType eq 'mysql') {
        # MySQL version
        $SQL = "SELECT 
            CASE        
                WHEN CURDATE() > DATE(endDate) THEN 'Expired'
                WHEN DATE(startDate) <= CURDATE() AND CURDATE() <= DATE(endDate) THEN 'Valid'
                ELSE 'Invalid'
            END AS license_status
            FROM license
            LIMIT 1";
    }
    else {
        # PostgreSQL version (default)
        $SQL = "SELECT 
            CASE        
                WHEN NOW()::date > endDate::date THEN 'Expired'
                WHEN startDate::date <= NOW()::date AND NOW()::date <= endDate::date THEN 'Valid'
                ELSE 'Invalid'
            END AS license_status
            FROM license
            LIMIT 1";
    }
    
    # Execute query
    return if !$DBObject->Prepare(
        SQL => $SQL,
    );
    
    # Fetch the result
    my $LicenseStatus = 'NotFound';  # Default if no license exists
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $LicenseStatus = $Row[0] || 'Invalid';
    }
    
    $LogObject->Log(
        Priority => 'debug',
        Message  => "License check for user $Self->{UserID}: Status = $LicenseStatus",
    );
    
    # Implement redirect logic if license is not valid
    if ($LicenseStatus ne 'Valid') {
        # Get GroupObject to check user's groups
        my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
        
        # Get user's groups
        my @UserGroups = $GroupObject->GroupMemberList(
            UserID => $Self->{UserID},
            Type   => 'ro',
            Result => 'Name',
        );
        
        # Determine redirect target based on user's groups
        my $RedirectAction = 'AdminAddLicense';  # Default for admin users
        
        # Check if user is in NOCAdmin or NOCUser groups
        my $IsNOCUser = 0;
        for my $Group (@UserGroups) {
            if ( $Group eq 'NOCAdmin' || $Group eq 'NOCUser' ) {
                $IsNOCUser = 1;
                last;
            }
        }
        
        # If user is NOCAdmin or NOCUser, redirect to CustomerLicenseView
        if ($IsNOCUser) {
            $RedirectAction = 'CustomerLicenseView';
        }
        
        # Log the redirect
        $LogObject->Log(
            Priority => 'notice',
            Message  => "Redirecting user $Self->{UserID} to $RedirectAction. License status: $LicenseStatus",
        );
        
        # Set license status in LayoutObject for CSS/UI purposes
        $LayoutObject->{LicenseInvalid} = 1;
        $LayoutObject->{LicenseStatus} = $LicenseStatus;
        
        # Perform redirect to appropriate page
        return $LayoutObject->Redirect(
            OP => "Action=$RedirectAction",
        );
    }
    
    # License is valid, allow normal operation
    return;
}

1;