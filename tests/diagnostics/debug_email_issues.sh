#!/bin/bash
# Debug email issues

# Set Znuny path - can be overridden by environment variable
ZNUNY_ROOT="${ZNUNY_ROOT:-/path/to/znuny}"

echo "=== Debugging Email Issues ==="
echo "Using Znuny at: $ZNUNY_ROOT"
echo ""

# 1. Check SMTP configuration
echo "1. Current SMTP Configuration:"
su - znuny -c "$ZNUNY_ROOT/bin/otrs.Console.pl Admin::Config::Read --setting-name SendmailModule"
su - znuny -c "$ZNUNY_ROOT/bin/otrs.Console.pl Admin::Config::Read --setting-name SendmailModule::Host"
su - znuny -c "$ZNUNY_ROOT/bin/otrs.Console.pl Admin::Config::Read --setting-name SendmailModule::Port"

# 2. Check if mail queue is enabled
echo ""
echo "2. Mail Queue Status:"
su - znuny -c "$ZNUNY_ROOT/bin/otrs.Console.pl Admin::Config::Read --setting-name SendmailModule::UseMailQueue"

# 3. Check for errors in communication log
echo ""
echo "3. Recent Communication Log Errors:"
su - znuny -c "$ZNUNY_ROOT/bin/otrs.Console.pl Maint::Log::CommunicationLog --list-communications --limit 5"

# 4. Test SMTP connection directly
echo ""
echo "4. Testing SMTP Connection:"
cat > /tmp/test_smtp.pl << 'EOF'
#!/usr/bin/perl
use strict;
use warnings;
use Net::SMTP;

my $smtp_host = 'smtp.gmail.com';
my $smtp_port = 587;
my $smtp_user = 'neovash23@gmail.com';
my $smtp_pass = 'pedlrojkktylpdhz';

print "Connecting to $smtp_host:$smtp_port...\n";

eval {
    my $smtp = Net::SMTP->new(
        $smtp_host,
        Port => $smtp_port,
        Timeout => 30,
        Debug => 1,
    );
    
    if ($smtp) {
        print "Connected!\n";
        
        # STARTTLS
        if ($smtp->can('starttls')) {
            print "Starting TLS...\n";
            $smtp->starttls() or die "STARTTLS failed: $!";
            print "TLS started\n";
        }
        
        # Auth
        print "Authenticating...\n";
        $smtp->auth($smtp_user, $smtp_pass) or die "Auth failed: $!";
        print "Authenticated!\n";
        
        $smtp->quit;
        print "Success!\n";
    } else {
        print "Connection failed: $!\n";
    }
};

if ($@) {
    print "Error: $@\n";
}
EOF

perl /tmp/test_smtp.pl

# 5. Check system mail settings
echo ""
echo "5. System Email Settings:"
echo "Sendmail command:"
which sendmail
echo ""
echo "Mail queue directory:"
ls -la $ZNUNY_ROOT/var/spool 2>/dev/null || echo "No spool directory"

# 6. Check for TLS/SSL libraries
echo ""
echo "6. Required Perl modules:"
perl -e 'use Net::SMTP; print "Net::SMTP: OK\n"' 2>&1
perl -e 'use Net::SSLeay; print "Net::SSLeay: OK\n"' 2>&1
perl -e 'use IO::Socket::SSL; print "IO::Socket::SSL: OK\n"' 2>&1

echo ""
echo "=== Common Issues ==="
echo "1. Gmail requires App Password (not regular password)"
echo "2. Gmail may block 'less secure apps'"
echo "3. Port 587 requires STARTTLS"
echo "4. Check firewall for outbound port 587"
echo "5. Check if Perl SSL modules are installed"