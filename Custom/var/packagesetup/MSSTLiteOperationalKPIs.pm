package var::packagesetup::MSSTLiteOperationalKPIs;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
);

sub new {
    my ( $Type, %Param ) = @_;
    my $Self = {};
    bless( $Self, $Type );
    return $Self;
}

sub CodeInstall {
    my ( $Self, %Param ) = @_;

    # Note: operational_kpis_cache table is created via SOPM DatabaseInstall section
    # This method only creates additional performance indexes
    $Self->_CreateDatabaseIndexes();

    return 1;
}

sub CodeUpgrade {
    my ( $Self, %Param ) = @_;

    # Handle upgrades if needed
    # Re-create indexes on upgrade to ensure they exist
    $Self->_CreateDatabaseIndexes();

    return 1;
}

sub _CreateDatabaseIndexes {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    my @IndexSQLs = (
        q{CREATE INDEX IF NOT EXISTS idx_kpis_cache_lookup ON operational_kpis_cache(report_type, aggregation_level, period_start, period_end)},
        q{CREATE INDEX IF NOT EXISTS idx_kpis_cache_period ON operational_kpis_cache(period_start, period_end)},
        q{CREATE INDEX IF NOT EXISTS idx_ticket_incident_kpis ON ticket(type_id, create_time, ticket_state_id, user_id) WHERE type_id = 2},
        q{CREATE INDEX IF NOT EXISTS idx_ticket_change_time_owner ON ticket(change_time, user_id) WHERE type_id = 2},
        q{CREATE INDEX IF NOT EXISTS idx_df_value_incident_fields ON dynamic_field_value(field_id, object_id) WHERE field_id IN (SELECT id FROM dynamic_field WHERE name IN ('Opened', 'Response', 'Resolved', 'IncidentSource', 'MSITicketNumber'))},
    );

    for my $SQL (@IndexSQLs) {
        my $Success = $DBObject->Do( SQL => $SQL );

        if ( !$Success ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "MSSTLiteOperationalKPIs: Failed to create index: $SQL",
            );
            return;
        }
    }

    $LogObject->Log(
        Priority => 'notice',
        Message  => 'MSSTLiteOperationalKPIs: Created database indexes successfully.',
    );

    return 1;
}

1;