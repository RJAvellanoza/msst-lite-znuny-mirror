#!/usr/bin/perl
# --
# ImportIncidentCategories.pl - Import incident categories from CSV files
# --
# This script imports category data from CSV files into the incident module tables
# Usage: perl /path/to/ImportIncidentCategories.pl
# --

use strict;
use warnings;
use utf8;

use FindBin qw($RealBin);

BEGIN {
    # Find Znuny installation
    my $Home;
    if (-d "$RealBin/../../Kernel") {
        # Running from within package structure
        $Home = "$RealBin/../..";
    } else {
        # Try to find Znuny installation
        for my $path ('/opt/znuny', glob('/opt/znuny-*')) {
            if (-d "$path/Kernel") {
                $Home = $path;
                last;
            }
        }
    }
    
    die "Could not find Znuny installation!\n" unless $Home && -d "$Home/Kernel";
    
    # Add Znuny libraries to path
    unshift @INC, $Home;
    unshift @INC, "$Home/Kernel/cpan-lib";
    unshift @INC, "$Home/Custom";
}

use Kernel::System::ObjectManager;

# Get Home directory again for use in script
my $Home;
if (-d "$RealBin/../../Kernel") {
    $Home = "$RealBin/../..";
} else {
    for my $path ('/opt/znuny', glob('/opt/znuny-*')) {
        if (-d "$path/Kernel") {
            $Home = $path;
            last;
        }
    }
}

# Create object manager
local $Kernel::OM = Kernel::System::ObjectManager->new();

my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

# Category path - look in multiple locations
my $CategoryPath;
if (-d "$RealBin/../var/categories") {
    # Running from package location
    $CategoryPath = "$RealBin/../var/categories";
} elsif (-d "$Home/Custom/var/categories") {
    # Installed in Znuny
    $CategoryPath = "$Home/Custom/var/categories";
} else {
    die "Could not find category files directory!\n";
}

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

# Create tables first
print "Creating category tables...\n";

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

print "Tables created.\n";

# Process each category file
for my $CategoryType (sort keys %CategoryFiles) {
    my $Config = $CategoryFiles{$CategoryType};
    my $FilePath = "$CategoryPath/$Config->{file}";
    
    print "\nProcessing $CategoryType categories from $Config->{file}...\n";
    
    # Check if file exists
    if (!-e $FilePath) {
        print "  WARNING: File not found: $FilePath\n";
        next;
    }
    
    # Clear existing data
    $DBObject->Do(
        SQL => "DELETE FROM $Config->{table}",
    );
    
    # Require Text::CSV from Znuny's cpan-lib
    require Text::CSV;
    
    # Open CSV file
    my $csv = Text::CSV->new({
        binary => 1,
        auto_diag => 1,
        sep_char => ',',
    });
    
    open my $fh, "<:encoding(utf8)", $FilePath or die "Can't open $FilePath: $!";
    
    # Read header
    my $header = $csv->getline($fh);
    
    my $count = 0;
    
    # Read data rows
    while (my $row = $csv->getline($fh)) {
        my %Data;
        my @PathParts;
        
        # Map CSV columns to database columns
        for (my $i = 0; $i < @{$Config->{columns}}; $i++) {
            my $value = $row->[$i] || '';
            $value =~ s/^\s+|\s+$//g; # Trim whitespace
            
            if ($value) {
                $Data{$Config->{columns}[$i]} = $value;
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
        my $SQL = "INSERT INTO $Config->{table} (" . join(', ', @Columns) . ") VALUES ($Placeholders)";
        
        # Convert values to scalar refs for Znuny DB
        my @BindValues = map { \$_ } @Values;
        
        $DBObject->Do(
            SQL => $SQL,
            Bind => \@BindValues,
        );
        
        $count++;
    }
    
    close $fh;
    
    print "  Imported $count $CategoryType categories.\n";
}

# Create indexes for better performance
print "\nCreating indexes...\n";

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

print "Indexes created.\n";

# Show summary
print "\n=== Import Summary ===\n";
for my $CategoryType (sort keys %CategoryFiles) {
    my $Config = $CategoryFiles{$CategoryType};
    
    my $Count = $DBObject->SelectAll(
        SQL => "SELECT COUNT(*) FROM $Config->{table}",
        Limit => 1,
    );
    
    print "$CategoryType categories: " . ($Count->[0]->[0] || 0) . " records\n";
}

print "\nCategory import completed successfully!\n";

1;