# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::ZabbixConfig;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::Config',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->{CacheType} = 'ZabbixConfig';
    $Self->{CacheTTL}  = 60 * 60 * 24;  # 24 hours

    return $Self;
}

sub Get {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    if ( !$Param{Key} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need Key!',
        );
        return;
    }

    # Check cache
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    my $CacheKey    = 'ZabbixConfig::' . $Param{Key};
    
    my $Cache = $CacheObject->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );

    return $Cache if defined $Cache;

    # Get from database
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL => 'SELECT config_value FROM zabbix_config WHERE config_key = ?',
        Bind => [ \$Param{Key} ],
    );

    my $Value;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Value = $Row[0];
    }

    # Set cache
    if ( defined $Value ) {
        $CacheObject->Set(
            Type  => $Self->{CacheType},
            Key   => $CacheKey,
            Value => $Value,
            TTL   => $Self->{CacheTTL},
        );
    }

    return $Value;
}

sub GetAll {
    my ( $Self, %Param ) = @_;

    # Check cache
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    my $CacheKey    = 'ZabbixConfig::All';
    
    my $Cache = $CacheObject->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );

    return $Cache if $Cache;

    # Get from database
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL => 'SELECT config_key, config_value FROM zabbix_config',
    );

    my %Config;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Config{ $Row[0] } = $Row[1] || '';
    }

    # Set cache
    if (%Config) {
        $CacheObject->Set(
            Type  => $Self->{CacheType},
            Key   => $CacheKey,
            Value => \%Config,
            TTL   => $Self->{CacheTTL},
        );
    }

    return \%Config;
}

sub Set {
    my ( $Self, %Param ) = @_;

    # Check needed stuff
    for my $Needed (qw(Key Value UserID)) {
        if ( !defined $Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Check if key exists
    return if !$DBObject->Prepare(
        SQL => 'SELECT id FROM zabbix_config WHERE config_key = ?',
        Bind => [ \$Param{Key} ],
    );

    my $Exists;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Exists = 1;
    }

    my $Success;
    if ($Exists) {
        # Update existing
        $Success = $DBObject->Do(
            SQL => 'UPDATE zabbix_config SET config_value = ?, change_time = current_timestamp, 
                    change_by = ? WHERE config_key = ?',
            Bind => [ \$Param{Value}, \$Param{UserID}, \$Param{Key} ],
        );
    }
    else {
        # Insert new
        $Success = $DBObject->Do(
            SQL => 'INSERT INTO zabbix_config (config_key, config_value, encrypted, 
                    create_time, create_by, change_time, change_by) 
                    VALUES (?, ?, 0, current_timestamp, ?, current_timestamp, ?)',
            Bind => [ \$Param{Key}, \$Param{Value}, \$Param{UserID}, \$Param{UserID} ],
        );
    }

    # Clear cache
    if ($Success) {
        my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
        $CacheObject->CleanUp(
            Type => $Self->{CacheType},
        );
    }

    return $Success;
}

sub IsEnabled {
    # Zabbix integration is always enabled
    return 1;
}

sub GetAPIURL {
    my ( $Self, %Param ) = @_;

    # Get from Config.pm only
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    return $ConfigObject->Get('ZabbixIntegration::APIURL') || '';
}

sub GetAPIUser {
    my ( $Self, %Param ) = @_;

    # Get from Config.pm only
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    return $ConfigObject->Get('ZabbixIntegration::APIUser') || '';
}

sub GetAPIPassword {
    my ( $Self, %Param ) = @_;

    # Get from Config.pm only
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    return $ConfigObject->Get('ZabbixIntegration::APIPassword') || '';
}

sub GetTriggerStates {
    my ( $Self, %Param ) = @_;

    my $States = $Self->Get( Key => 'TriggerStates' ) || 'resolved,closed,cancelled';
    
    # Return as array
    my @StateList = split( /\s*,\s*/, $States );
    
    return @StateList if wantarray;
    return \@StateList;
}

1;