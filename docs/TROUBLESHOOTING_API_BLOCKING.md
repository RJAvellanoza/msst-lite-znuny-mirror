# Troubleshooting API Blocking Not Working

## Things to Check on Your Test Server

### 1. Verify Provider.pm is Deployed
```bash
ls -la /path/to/znuny/Custom/Kernel/GenericInterface/Provider.pm
```
If the file doesn't exist, the package installation didn't deploy it correctly.

### 2. Check if License Check Code is Present
```bash
grep -n "MSST License Check" /path/to/znuny/Custom/Kernel/GenericInterface/Provider.pm
```
Should show line ~70 with the license check code.

### 3. Verify Configuration Settings
```bash
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Admin::Config::Read --setting-name LicenseCheck::Enabled"
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Admin::Config::Read --setting-name LicenseCheck::BlockAPI"
```
Both should return 1 (enabled).

### 4. Check if Configuration Was Deployed
After installing the package, configuration needs to be deployed:
```bash
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Maint::Config::Rebuild"
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Maint::Cache::Delete"
```

### 5. Check Apache/mod_perl is Loading Custom Modules
```bash
# Restart Apache to ensure Custom modules are loaded
systemctl restart apache2
# or
service httpd restart
```

### 6. Check License Status in Database
```bash
su - znuny -c "psql -c 'SELECT COUNT(*) as license_count FROM license;'"
```
If this returns 0, there's no license and API should be blocked.

### 7. Check Apache Error Logs
```bash
tail -f /path/to/apache/error.log
# or
tail -f /var/log/httpd/error_log
```
Look for "MSST API License Check" messages when making API calls.

### 8. Test API with curl
```bash
# This should return 403 if no license exists
curl -v http://localhost/otrs/nph-genericinterface.pl/Webservice/Test
```

## Common Issues

### Issue 1: Custom Directory Not in @INC
The Custom directory must be in Perl's @INC before the core modules.

Check with:
```bash
perl -e 'use lib "/path/to/znuny/"; use lib "/path/to/znuny/Kernel/cpan-lib"; use lib "/path/to/znuny/Custom"; print join("\n", @INC);' | grep znuny
```
Output should show:
```
/path/to/znuny/Custom
/path/to/znuny/Kernel/cpan-lib
/path/to/znuny
```

### Issue 2: Configuration Not Deployed
The package installation should auto-deploy configuration, but sometimes it needs manual deployment:
```bash
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Admin::Config::Update --setting-name LicenseCheck::Enabled --value 1"
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Admin::Config::Update --setting-name LicenseCheck::BlockAPI --value 1"
su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Maint::Config::Rebuild --cleanup"
```

### Issue 3: mod_perl Caching
If using mod_perl, the old Provider.pm might be cached:
```bash
# Force Apache to reload Perl modules
systemctl restart apache2
```

### Issue 4: Wrong Provider.pm Being Loaded
Check which Provider.pm is actually being loaded:
```bash
find /path/to/znuny -name "Provider.pm" -path "*/GenericInterface/*" -exec ls -la {} \;
```
Should show:
- `/path/to/znuny/Custom/Kernel/GenericInterface/Provider.pm` (our version)
- `/path/to/znuny/Kernel/GenericInterface/Provider.pm` (original)

Our Custom version should be loaded first.

## Quick Debug Script
Create this test script:
```perl
#!/usr/bin/perl
use lib "/path/to/znuny/";
use lib "/path/to/znuny/Kernel/cpan-lib";
use lib "/path/to/znuny/Custom";

# Check which Provider.pm is loaded
my $provider_path = $INC{'Kernel/GenericInterface/Provider.pm'};
print "Provider.pm loaded from: $provider_path\n";

# Check if it's our version
if ($provider_path =~ /Custom/) {
    print "✓ Custom Provider.pm is being used\n";
    system("grep -q 'MSST License Check' '$provider_path' && echo '✓ License check code found' || echo '✗ License check code NOT found'");
} else {
    print "✗ Original Provider.pm is being used - Custom not loaded!\n";
}
```

## If All Else Fails
1. Check the package installation log for errors
2. Manually copy Provider.pm:
   ```bash
   cp /path/to/extracted/Custom/Kernel/GenericInterface/Provider.pm /path/to/znuny/Custom/Kernel/GenericInterface/
   chown znuny:www-data /path/to/znuny/Custom/Kernel/GenericInterface/Provider.pm
   chmod 644 /path/to/znuny/Custom/Kernel/GenericInterface/Provider.pm
   ```
3. Restart all services:
   ```bash
   systemctl restart apache2
   su - znuny -c "/path/to/znuny/bin/otrs.Console.pl Maint::Cache::Delete"
   ```