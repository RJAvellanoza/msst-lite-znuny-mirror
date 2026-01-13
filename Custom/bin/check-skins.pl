#\!/usr/bin/perl
# Utility script to check registered skins in Znuny

use strict;
use warnings;

# Path to the auto-generated config file
my $config_file = '/opt/znuny-6.5.14/Kernel/Config/Files/ZZZAAuto.pm';

print "Checking registered skins in: $config_file\n";
print "=" x 60 . "\n";

if (!-f $config_file) {
    print "ERROR: Config file not found: $config_file\n";
    exit 1;
}

# Read the config file
open my $fh, '<', $config_file or die "Cannot read $config_file: $\!";
my @lines = <$fh>;
close $fh;

my $found_skins = 0;

for my $i (0 .. $#lines) {
    my $line = $lines[$i];
    
    # Look for skin registrations
    if ($line =~ /\$Self->\{\'Loader::Agent::Skin\'\}->\{\'([^\']+)\'\}\s*=\s*\{/) {
        my $skin_key = $1;
        print "Found skin: $skin_key\n";
        $found_skins++;
        
        # Try to extract more details from subsequent lines
        for (my $j = $i + 1; $j < $i + 15 && $j <= $#lines; $j++) {
            my $detail_line = $lines[$j];
            if ($detail_line =~ /\'InternalName\'\s*=>\s*\'([^\']+)\'/) {
                print "  Internal Name: $1\n";
            }
            if ($detail_line =~ /\'VisibleName\'\s*=>\s*\'([^\']+)\'/) {
                print "  Visible Name: $1\n";
            }
            if ($detail_line =~ /};/) {
                last;
            }
        }
        print "\n";
    }
    
    # Also check for default skin setting
    if ($line =~ /\$Self->\{\'Loader::Agent::DefaultSelectedSkin\'\}\s*=\s*\'([^\']+)\'/) {
        print "Default skin: $1\n\n";
    }
}

if ($found_skins == 0) {
    print "No skins found in config file.\n";
    print "Looking for any Loader::Agent entries...\n\n";
    
    foreach my $line (@lines) {
        if ($line =~ /Loader::Agent/) {
            print "Found: " . $line;
        }
    }
}

print "Total skins found: $found_skins\n";
