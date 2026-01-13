#!/usr/bin/perl
# Create a license file for msst-lite-znuny-clone server
# Updated to match Python aes_encrypt3.py encryption method

use strict;
use warnings;
use JSON;
use Crypt::CBC;
use MIME::Base64;
use Time::Piece;

# Encryption key (matches Python script)
my $key_base64 = '/Px3bgjiiLk8yy4UPqxIO3/B6NTiZYcwymkWDhIrCdA=';
my $key = MIME::Base64::decode($key_base64);

# Generate random IV (16 bytes) like Python script
my $iv = '';
for (my $i = 0; $i < 16; $i++) {
    $iv .= chr(int(rand(256)));
}

# Get current date
my $now = Time::Piece->new();
my $start_date = $now->strftime('%Y/%m/%d');
my $end_date = ($now + (4*365 * 24 * 60 * 60))->strftime('%Y/%m/%d'); # 1 year from now

print "Creating license for msst-lite-znuny-clone server...\n";
print "Server MAC Address: bc:24:11:cc:a9:c0\n";
print "Valid from: $start_date to $end_date\n\n";

# Create license data with the clone server's MAC address
my $license_data = {
    msstLiteLicense => {
        UID             => "TEST-" . time(),
        contractCompany => "MSST Solutions",
        endCustomer     => "LSMP Clone Server",
        mcn             => "1111111111",
        systemTechnology => "NA_SWE_Flex_FrontOffice",
        lsmpSiteID      => "CLONE-SITE-001",
        macAddress      => "bc:24:11:cc:a9:c0",  # Clone server's MAC address
        startDate       => $start_date,
        endDate         => $end_date,
    }
};

# Convert to JSON (compact format like Python)
my $json = JSON->new->canonical->encode($license_data);

# Create cipher with random IV
my $cipher = Crypt::CBC->new(
    -cipher      => 'Crypt::Rijndael',
    -key         => $key,
    -iv          => $iv,
    -literal_key => 1,
    -header      => 'none',
    -keysize     => 32,
    -padding     => 'standard',  # PKCS7 padding like Python
);

# Encrypt the JSON directly (no prefix, matching Python)
my $ciphertext = $cipher->encrypt($json);

# Generate filename like Python script
my $clean_customer = $license_data->{msstLiteLicense}->{endCustomer};
$clean_customer =~ s/\s//g;
$clean_customer =~ s/,//g;
my $clean_mac = $license_data->{msstLiteLicense}->{macAddress};
$clean_mac =~ s/[:-]//g;
my $clean_date = $license_data->{msstLiteLicense}->{endDate};
$clean_date =~ s/\///g;

my $filename = sprintf("license/%s-%s-%s-%s.lic",
    $clean_customer,
    $license_data->{msstLiteLicense}->{UID},
    $clean_mac,
    $clean_date
);

# Create license directory if it doesn't exist
mkdir 'license' unless -d 'license';

# Write IV + ciphertext to file (binary format like Python)
open(my $fh, '>', $filename) or die "Cannot write $filename: $!";
binmode($fh);
print $fh $iv . $ciphertext;
close($fh);

print "Created: $filename\n";
print "License Details:\n";
print "  Company: " . $license_data->{msstLiteLicense}->{contractCompany} . "\n";
print "  Customer: " . $license_data->{msstLiteLicense}->{endCustomer} . "\n";
print "  MCN: " . $license_data->{msstLiteLicense}->{mcn} . "\n";
print "  System Technology: " . $license_data->{msstLiteLicense}->{systemTechnology} . "\n";
print "  LSMP Site ID: " . $license_data->{msstLiteLicense}->{lsmpSiteID} . "\n";
print "  MAC Address: " . $license_data->{msstLiteLicense}->{macAddress} . "\n";
print "  Valid from: $start_date to $end_date\n\n";
print "This license is valid ONLY for the msst-lite-znuny-clone server.\n";