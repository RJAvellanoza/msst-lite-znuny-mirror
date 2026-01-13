#!/bin/bash
# Deploy SMTP configuration

# Get Znuny path from environment or try to detect it
if [ -z "$ZNUNY_ROOT" ]; then
    if [ -d "/opt/znuny-6.5.15" ]; then
        ZNUNY_ROOT="/opt/znuny-6.5.15"
    elif [ -d "/opt/znuny" ]; then
        ZNUNY_ROOT="/opt/znuny"
    else
        echo "Cannot find Znuny installation. Please set ZNUNY_ROOT environment variable."
        exit 1
    fi
fi

echo "Deploying SMTP Notification configuration..."
echo "Using Znuny at: $ZNUNY_ROOT"

# Export for use in subshell
export ZNUNY_ROOT

# Run as znuny user
su - znuny << 'EOF'
cd $ZNUNY_ROOT

# First, rebuild config to import XML
echo "Rebuilding configuration..."
bin/otrs.Console.pl Maint::Config::Rebuild

# Deploy all settings
echo "Deploying settings..."
perl << 'PERL_SCRIPT'
BEGIN {
    my $znuny_root = $ENV{ZNUNY_ROOT} || '/opt/znuny-6.5.15';
    unshift @INC, "$znuny_root";
    unshift @INC, "$znuny_root/Kernel/cpan-lib";
    unshift @INC, "$znuny_root/Custom";
}

use Kernel::System::ObjectManager;
local $Kernel::OM = Kernel::System::ObjectManager->new();

my $SysConfigObject = $Kernel::OM->Get("Kernel::System::SysConfig");

# Import configuration
$SysConfigObject->ConfigurationXML2DB(
    UserID => 1,
    Force  => 1,
);

# Lock and deploy
my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
    LockAll => 1,
    Force   => 1,
    UserID  => 1,
);

$SysConfigObject->ConfigurationDeploy(
    Comments      => "SMTP Notification deployment",
    AllSettings   => 1,
    Force         => 1,
    NoValidation  => 1,
    UserID        => 1,
    ExclusiveLockGUID => $ExclusiveLockGUID,
);

print "Configuration deployed.\n";
PERL_SCRIPT

# Clear cache
echo "Clearing cache..."
bin/otrs.Console.pl Maint::Cache::Delete

echo "Done!"
EOF

# Detect which web server is running
if systemctl is-active --quiet apache2; then
    echo "Restarting Apache..."
    systemctl restart apache2
elif systemctl is-active --quiet httpd; then
    echo "Restarting Apache..."
    systemctl restart httpd
else
    echo "WARNING: Could not detect Apache service. Please restart your web server manually."
fi

echo "SMTP Notification configuration deployed successfully!"
echo "You can now access: http://YOUR_ZNUNY_SERVER/otrs/index.pl?Action=AdminSMTPNotification"