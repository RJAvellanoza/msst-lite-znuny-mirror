package Kernel::System::IncidentCategory;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::Config',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub ImportFromCSV {
    my ( $Self, %Param ) = @_;
    
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    # Get home directory
    my $Home = $ConfigObject->Get('Home');
    my $CategoryPath = "$Home/Custom/var/categories";
    
    # Create tables first
    $Self->_CreateTables();
    
    # Define file mappings
    my %CategoryFiles = (
        product => {
            file => 'LSMP New Categories (Subset of ServiceNow Global Categories) - All Prod Cats.csv',
            table => 'incident_product_category',
            columns => ['tier1', 'tier2', 'tier3', 'tier4'],
        },
        operational => {
            file => 'LSMP New Categories (Subset of ServiceNow Global Categories) - All Operational Cats.csv',
            table => 'incident_operational_category',
            columns => ['tier1', 'tier2', 'tier3'],
        },
        resolution => {
            file => 'LSMP New Categories (Subset of ServiceNow Global Categories) - All Resolution Cats.csv',
            table => 'incident_resolution_category',
            columns => ['tier1', 'tier2', 'tier3'],
        },
    );
    
    # Process each category file
    for my $CategoryType (sort keys %CategoryFiles) {
        my $Config = $CategoryFiles{$CategoryType};
        my $FilePath = "$CategoryPath/$Config->{file}";
        
        # Check if file exists
        if (!-e $FilePath) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Category file not found: $FilePath",
            );
            next;
        }
        
        # Clear existing data
        $DBObject->Do(
            SQL => "DELETE FROM $Config->{table}",
        );
        
        # Import CSV data
        my $Count = $Self->_ImportCSVFile(
            FilePath => $FilePath,
            Table    => $Config->{table},
            Columns  => $Config->{columns},
        );
        
        $LogObject->Log(
            Priority => 'notice',
            Message  => "Imported $Count $CategoryType categories",
        );
    }
    
    # Create indexes
    $Self->_CreateIndexes();
    
    return 1;
}

sub _CreateTables {
    my ( $Self, %Param ) = @_;
    
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    
    # Product Category Table
    $DBObject->Do(
        SQL => q{
            CREATE TABLE IF NOT EXISTS incident_product_category (
                id SERIAL PRIMARY KEY,
                tier1 VARCHAR(200),
                tier2 VARCHAR(200),
                tier3 VARCHAR(200),
                tier4 VARCHAR(200),
                full_path VARCHAR(800),
                valid_id SMALLINT NOT NULL DEFAULT 1,
                create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                create_by INTEGER NOT NULL DEFAULT 1,
                change_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                change_by INTEGER NOT NULL DEFAULT 1
            )
        },
    );
    
    # Operational Category Table
    $DBObject->Do(
        SQL => q{
            CREATE TABLE IF NOT EXISTS incident_operational_category (
                id SERIAL PRIMARY KEY,
                tier1 VARCHAR(200),
                tier2 VARCHAR(200),
                tier3 VARCHAR(200),
                full_path VARCHAR(600),
                valid_id SMALLINT NOT NULL DEFAULT 1,
                create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                create_by INTEGER NOT NULL DEFAULT 1,
                change_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                change_by INTEGER NOT NULL DEFAULT 1
            )
        },
    );
    
    # Resolution Category Table
    $DBObject->Do(
        SQL => q{
            CREATE TABLE IF NOT EXISTS incident_resolution_category (
                id SERIAL PRIMARY KEY,
                tier1 VARCHAR(200),
                tier2 VARCHAR(200),
                tier3 VARCHAR(200),
                full_path VARCHAR(600),
                valid_id SMALLINT NOT NULL DEFAULT 1,
                create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                create_by INTEGER NOT NULL DEFAULT 1,
                change_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                change_by INTEGER NOT NULL DEFAULT 1
            )
        },
    );
    
    return 1;
}

sub _ImportCSVFile {
    my ( $Self, %Param ) = @_;
    
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    
    # Require Text::CSV from Znuny's cpan-lib
    require Text::CSV;
    
    # Open CSV file
    my $csv = Text::CSV->new({
        binary => 1,
        auto_diag => 1,
        sep_char => ',',
    });
    
    open my $fh, "<:encoding(utf8)", $Param{FilePath} or return 0;
    
    # Read header
    my $header = $csv->getline($fh);
    
    my $count = 0;
    
    # Read data rows
    while (my $row = $csv->getline($fh)) {
        my %Data;
        my @PathParts;
        
        # Map CSV columns to database columns
        for (my $i = 0; $i < @{$Param{Columns}}; $i++) {
            my $value = $row->[$i] || '';
            $value =~ s/^\s+|\s+$//g; # Trim whitespace
            
            if ($value) {
                $Data{$Param{Columns}[$i]} = $value;
                push @PathParts, $value;
            }
        }
        
        # Skip empty rows
        next unless %Data;
        
        # Create full path
        $Data{full_path} = join(' > ', @PathParts);
        
        # Build column list and placeholders
        my @Columns = grep { defined $Data{$_} } keys %Data;
        my @Values = map { $Data{$_} } @Columns;
        my $Placeholders = join(', ', ('?') x @Columns);
        
        # Insert into database
        my $SQL = "INSERT INTO $Param{Table} (" . join(', ', @Columns) . ") VALUES ($Placeholders)";
        
        # Convert values to scalar refs for Znuny DB
        my @BindValues = map { \$_ } @Values;
        
        $DBObject->Do(
            SQL => $SQL,
            Bind => \@BindValues,
        );
        
        $count++;
    }
    
    close $fh;
    
    return $count;
}

sub _CreateIndexes {
    my ( $Self, %Param ) = @_;
    
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    
    # Product category indexes
    $DBObject->Do(SQL => "CREATE INDEX IF NOT EXISTS idx_incident_product_cat_tier1 ON incident_product_category(tier1)");
    $DBObject->Do(SQL => "CREATE INDEX IF NOT EXISTS idx_incident_product_cat_tier2 ON incident_product_category(tier2)");
    $DBObject->Do(SQL => "CREATE INDEX IF NOT EXISTS idx_incident_product_cat_valid ON incident_product_category(valid_id)");
    
    # Operational category indexes
    $DBObject->Do(SQL => "CREATE INDEX IF NOT EXISTS idx_incident_operational_cat_tier1 ON incident_operational_category(tier1)");
    $DBObject->Do(SQL => "CREATE INDEX IF NOT EXISTS idx_incident_operational_cat_tier2 ON incident_operational_category(tier2)");
    $DBObject->Do(SQL => "CREATE INDEX IF NOT EXISTS idx_incident_operational_cat_valid ON incident_operational_category(valid_id)");
    
    # Resolution category indexes
    $DBObject->Do(SQL => "CREATE INDEX IF NOT EXISTS idx_incident_resolution_cat_tier1 ON incident_resolution_category(tier1)");
    $DBObject->Do(SQL => "CREATE INDEX IF NOT EXISTS idx_incident_resolution_cat_tier2 ON incident_resolution_category(tier2)");
    $DBObject->Do(SQL => "CREATE INDEX IF NOT EXISTS idx_incident_resolution_cat_valid ON incident_resolution_category(valid_id)");
    
    return 1;
}

# Get categories by type and tier
sub CategoryGet {
    my ( $Self, %Param ) = @_;
    
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    
    # Check needed params
    for my $Needed (qw(Type Tier)) {
        if (!$Param{$Needed}) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return [];
        }
    }
    
    # Map type to table
    my %TypeToTable = (
        product     => 'incident_product_category',
        operational => 'incident_operational_category',
        resolution  => 'incident_resolution_category',
    );
    
    my $Table = $TypeToTable{lc($Param{Type})};
    return [] if !$Table;
    
    # Build WHERE clause
    my @Where = ('valid_id = 1');
    my @Bind;
    
    my $TierColumn = "tier$Param{Tier}";
    push @Where, "$TierColumn IS NOT NULL";
    
    # Add parent tier constraints
    if ($Param{Tier} > 1 && $Param{Tier1}) {
        push @Where, "tier1 = ?";
        push @Bind, \$Param{Tier1};
    }
    if ($Param{Tier} > 2 && $Param{Tier2}) {
        push @Where, "tier2 = ?";
        push @Bind, \$Param{Tier2};
    }
    if ($Param{Tier} > 3 && $Param{Tier3}) {
        push @Where, "tier3 = ?";
        push @Bind, \$Param{Tier3};
    }
    
    my $WhereString = @Where ? ' WHERE ' . join(' AND ', @Where) : '';
    
    # Execute query
    my $SQL = "SELECT DISTINCT $TierColumn as Name FROM $Table $WhereString ORDER BY $TierColumn";
    
    my $Result = $DBObject->SelectAll(
        SQL => $SQL,
        Bind => \@Bind,
    ) || [];
    
    # Convert array of arrays to array of hashes
    my @Categories;
    for my $Row (@{$Result}) {
        push @Categories, {
            Name => $Row->[0],
        };
    }
    
    return \@Categories;
}

# Get product categories
sub GetProductCategories {
    my ( $Self, %Param ) = @_;
    
    return $Self->CategoryGet(
        Type => 'product',
        %Param,
    );
}

# Get operational categories
sub GetOperationalCategories {
    my ( $Self, %Param ) = @_;
    
    return $Self->CategoryGet(
        Type => 'operational',
        %Param,
    );
}

# Get resolution categories
sub GetResolutionCategories {
    my ( $Self, %Param ) = @_;
    
    return $Self->CategoryGet(
        Type => 'resolution',
        %Param,
    );
}

1;