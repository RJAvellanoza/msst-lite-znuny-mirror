# Quick Setup Guide - SMTP Notifications

## 1. Configure in UI
Go to: Admin → MSSTLite → SMTP Notification Configuration

## 2. Run these commands
```bash
cd /opt/znuny/msst-lite-znuny
perl sync_smtp_settings.pl
perl fix_smtp_module.pl
```

## 3. Restart daemon
```bash
su - znuny -c "/opt/znuny-6.5.15/bin/otrs.Daemon.pl stop && sleep 2 && /opt/znuny-6.5.15/bin/otrs.Daemon.pl start"
```

## That's it!

Test by creating a ticket. Check email queue:
```bash
su - znuny -c "/opt/znuny-6.5.15/bin/otrs.Console.pl Maint::Email::MailQueue --list"
```

## Common Issues

**Gmail**: Use port 587 with STARTTLS  
**Amazon SES**: Verify sender email first  
**No emails**: Make sure customer has email address