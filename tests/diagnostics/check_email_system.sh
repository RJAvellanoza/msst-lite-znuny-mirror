#!/bin/bash
# Comprehensive email system check

# Set Znuny path - can be overridden by environment variable
ZNUNY_ROOT="${ZNUNY_ROOT:-/path/to/znuny}"

echo "=== Email System Diagnostics ==="
echo "Using Znuny at: $ZNUNY_ROOT"
echo ""

# 1. Check mail queue
echo "1. Checking mail queue..."
su - znuny -c "$ZNUNY_ROOT/bin/otrs.Console.pl Maint::Email::MailQueue --list"

# 2. Check if mail queue is enabled
echo ""
echo "2. Checking if mail queue is enabled..."
su - znuny -c "$ZNUNY_ROOT/bin/otrs.Console.pl Admin::Config::Read --setting-name SendmailModule::CMD" 2>/dev/null || echo "Not using sendmail"

# 3. Check communication log for recent attempts
echo ""
echo "3. Checking communication log..."
su - znuny -c "$ZNUNY_ROOT/bin/otrs.Console.pl Maint::Log::CommunicationLog --purge --verbose" 2>&1 | grep -i "email\|smtp" | tail -10

# 4. Check Apache error log
echo ""
echo "4. Recent Apache errors..."
tail -20 ${APACHE_LOG:-/path/to/apache/error.log} | grep -i "email\|smtp\|notification"

# 5. Test direct SMTP connection with better error handling
echo ""
echo "5. Testing SMTP connection with detailed output..."
cat > /tmp/test_smtp_detailed.pl << 'EOF'
#!/usr/bin/perl
use strict;
use warnings;
use Net::SMTP;
use IO::Socket::SSL;

$IO::Socket::SSL::DEBUG = 3;  # Enable SSL debugging

my $smtp_host = 'smtp.gmail.com';
my $smtp_port = 587;
my $smtp_user = 'neovash23@gmail.com';
my $smtp_pass = 'pedlrojkktylpdhz';

print "Testing SMTP connection to $smtp_host:$smtp_port\n\n";

eval {
    # Create SMTP connection
    my $smtp = Net::SMTP->new(
        $smtp_host,
        Port => $smtp_port,
        Timeout => 30,
        Debug => 1,
    ) or die "Cannot connect to server: $!";
    
    print "\nConnected. Starting TLS...\n";
    
    # Start TLS
    $smtp->starttls(
        SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
    ) or die "STARTTLS failed: " . $smtp->message;
    
    print "\nTLS established. Authenticating...\n";
    
    # Authenticate
    $smtp->auth($smtp_user, $smtp_pass) or die "Authentication failed: " . $smtp->message;
    
    print "\nAuthenticated. Sending test email...\n";
    
    # Send test email
    $smtp->mail($smtp_user);
    $smtp->to('markryan.orosa@motorolasolutions.com');
    $smtp->data();
    $smtp->datasend("From: $smtp_user\n");
    $smtp->datasend("To: markryan.orosa@motorolasolutions.com\n");
    $smtp->datasend("Subject: Znuny SMTP Direct Test\n");
    $smtp->datasend("\n");
    $smtp->datasend("This is a direct SMTP test from Znuny.\n");
    $smtp->datasend("If you receive this, SMTP is working but Znuny notifications might have issues.\n");
    $smtp->datasend("\nTime: " . localtime() . "\n");
    $smtp->dataend();
    
    my $response = $smtp->message;
    print "\nServer response: $response\n";
    
    $smtp->quit;
    
    print "\nTest email sent successfully!\n";
};

if ($@) {
    print "\nError: $@\n";
}
EOF

perl /tmp/test_smtp_detailed.pl 2>&1

# 6. Check Znuny's email configuration
echo ""
echo "6. Email Backend Configuration..."
su - znuny -c "cd $ZNUNY_ROOT && perl -e 'use lib \".\"; use Kernel::System::ObjectManager; local \$Kernel::OM = Kernel::System::ObjectManager->new(); my \$ConfigObject = \$Kernel::OM->Get(\"Kernel::Config\"); print \"SendmailModule: \" . (\$ConfigObject->Get(\"SendmailModule\") || \"not set\") . \"\n\"; print \"SMTP Host: \" . (\$ConfigObject->Get(\"SendmailModule::Host\") || \"not set\") . \"\n\"; print \"SMTP Port: \" . (\$ConfigObject->Get(\"SendmailModule::Port\") || \"not set\") . \"\n\";'"

echo ""
echo "=== Troubleshooting Tips ==="
echo "1. Check spam folder"
echo "2. Gmail might be blocking - check https://myaccount.google.com/security"
echo "3. Try enabling 'Less secure app access' (if available)"
echo "4. Check if 2-factor auth requires app-specific password"
echo "5. Gmail might need OAuth2 instead of password auth"