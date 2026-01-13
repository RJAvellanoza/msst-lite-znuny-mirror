# --
# Copyright (C) 2025 MSST Lite
# --
# This software comes with ABSOLUTELY NO WARRANTY.
# --

package var::packagesetup::MSSTLiteIncidentReporting;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::SysConfig',
    'Kernel::System::Cache',
);

=head1 NAME

var::packagesetup::MSSTLiteIncidentReporting - Package setup for Incident Reporting

=head1 DESCRIPTION

This module provides setup and upgrade functions for the Incident Reporting feature.

=head1 PUBLIC INTERFACE

=head2 new()

Create an object.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 CodeInstall()

Run code installation tasks.

=cut

sub CodeInstall {
    my ( $Self, %Param ) = @_;

    # Create database indexes for performance
    $Self->_CreateDatabaseIndexes();

    return 1;
}

=head2 CodeUpgrade()

Run code upgrade tasks.

=cut

sub CodeUpgrade {
    my ( $Self, %Param ) = @_;

    # Run the same operations as install
    $Self->CodeInstall();

    return 1;
}

=head2 CodeUninstall()

Run code uninstallation tasks.

=cut

sub CodeUninstall {
    my ( $Self, %Param ) = @_;

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    # Clear incident reporting cache
    $CacheObject->CleanUp(
        Type => 'IncidentReporting',
    );

    return 1;
}

=begin Internal:

=head2 _CreateDatabaseIndexes()

Create database indexes for optimal query performance.

=cut

sub _CreateDatabaseIndexes {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # List of indexes to create
    my @Indexes = (
        {
            Table => 'incident_product_category',
            Name  => 'idx_incident_product_category_ticket',
            SQL   => 'CREATE INDEX IF NOT EXISTS idx_incident_product_category_ticket ON incident_product_category(ticket_id)',
        },
        {
            Table => 'incident_operational_category',
            Name  => 'idx_incident_operational_category_ticket',
            SQL   => 'CREATE INDEX IF NOT EXISTS idx_incident_operational_category_ticket ON incident_operational_category(ticket_id)',
        },
        {
            Table => 'incident_resolution_category',
            Name  => 'idx_incident_resolution_category_ticket',
            SQL   => 'CREATE INDEX IF NOT EXISTS idx_incident_resolution_category_ticket ON incident_resolution_category(ticket_id)',
        },
        {
            Table => 'ebonding_api_log',
            Name  => 'idx_ebonding_api_log_ticket_operation',
            SQL   => 'CREATE INDEX IF NOT EXISTS idx_ebonding_api_log_ticket_operation ON ebonding_api_log(ticket_id, operation)',
        },
    );

    # Attempt to create each index
    for my $Index (@Indexes) {
        # Check if table exists first
        if ( !$Self->_TableExists( $Index->{Table} ) ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Table $Index->{Table} does not exist, skipping index creation for $Index->{Name}",
            );
            next;
        }

        # Try to create the index
        my $Success = $DBObject->Do(
            SQL => $Index->{SQL},
        );

        if ($Success) {
            $LogObject->Log(
                Priority => 'info',
                Message  => "Successfully created index: $Index->{Name}",
            );
        }
        else {
            # Index might already exist, which is fine
            $LogObject->Log(
                Priority => 'notice',
                Message  => "Index $Index->{Name} may already exist or table structure doesn't support it",
            );
        }
    }

    return 1;
}

=head2 _TableExists()

Check if a database table exists.

=cut

sub _TableExists {
    my ( $Self, $TableName ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # PostgreSQL query to check if table exists
    my $SQL = "
        SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_schema = 'public'
            AND table_name = ?
        )
    ";

    return 0 if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [ \$TableName ],
    );

    my $Exists = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Exists = $Row[0];
    }

    return $Exists;
}

=end Internal:

=cut

1;
