# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --
# ===============================================================================
# CENTRALIZED ADMIN MODULE PERMISSION MANAGEMENT
# ===============================================================================
# This file is the SINGLE SOURCE OF TRUTH for all admin module permissions.
# 
# DO NOT define Group/GroupRo permissions in:
# - XML configuration files (Custom/Kernel/Config/Files/XML/*.xml)
# - Other Perl configuration files (ZZZ*.pm)
# 
# This file loads last (ZZZZZ prefix) and overrides all other permission settings.
#
# User Groups:
# - admin: Full system access
# - MSIAdmin: MSI Administrator with specific baseline access
# - NOCAdmin: NOC Administrator with extended operational access  
# - NOCUser: NOC User with limited admin access
#
# MSIAdmin Baseline Access:
# - License Management (AdminAddLicense)
# - NOC Users (AdminUserNOC)
# - SMS Notification (AdminSMSNotification)
# - SMTP Notification (AdminSMTPNotification)
# - Easy MSI Escalation Configuration (AdminEBondingConfiguration)
# - Ticket Number Prefix (AdminTicketPrefix)
# - Zabbix Integration (AdminZabbixConfiguration)
# - Session Management (AdminSession)
# - MSI Support Remote Access (AdminMSISupportRemoteAccessConfiguration)
# - Export/Import Config (AdminExportImportConfig) - Full access
#
# NOCAdmin Access:
# - NOC Users (AdminUserNOC)
# - SMS Notification (AdminSMSNotification)
# - SMTP Notification (AdminSMTPNotification)
# - Easy MSI Escalation Configuration (AdminEBondingConfiguration)
# - Export/Import Config (AdminExportImportConfig) - NOT AVAILABLE
# - MSI Support Remote Access (AdminMSISupportRemoteAccessConfiguration)
# - Session Management (AdminSession)
# ===============================================================================

package Kernel::Config::Files::ZZZZZNOCAdminNavigation;

use strict;
use warnings;
use utf8;

sub Load {
    my ($File, $Self) = @_;

    # Override Frontend::Navigation for Admin to include NOC groups
    $Self->{'Frontend::Navigation'}->{'Admin'}->{'001-Framework'} = [
        {
            'AccessKey' => 'a',
            'Block' => 'ItemArea',
            'Description' => 'Admin modules overview.',
            'Group' => [
                'admin',
                'MSIAdmin',
                'NOCAdmin',
                'NOCUser'
            ],
            'GroupRo' => [],
            'Link' => 'Action=Admin',
            'LinkOption' => '',
            'Name' => 'Admin',
            'NavBar' => 'Admin',
            'Prio' => '10000',
            'Type' => 'Menu'
        }
    ];

    # Create AdminUserNOC module for NOCAdmin users with restrictions
    $Self->{'Frontend::Module'}->{'AdminUserNOC'} = {
        Description => 'Manage NOC users only (restricted access for NOCAdmin).',
        Title => 'NOC Users',
        NavBarName => 'Admin',
        NavBarModule => {
            Block => 'MSSTLite',
            Description => 'Manage NOC users.',
            Module => 'Kernel::Output::HTML::NavBar::ModuleAdmin',
            Name => 'NOC Users',
            Prio => '100',
        },
        Module => 'Kernel::Modules::AdminUserNOC',
        Group => ['NOCAdmin', 'MSIAdmin'],
        GroupRo => [],
    };
    
    # Add navigation module for AdminUserNOC
    $Self->{'Frontend::NavigationModule'}->{'AdminUserNOC'} = {
        Group => ['NOCAdmin', 'MSIAdmin'],
        GroupRo => [],
        Module => 'Kernel::Output::HTML::NavBar::ModuleAdmin',
        Name => 'NOC Users',
        Block => 'MSSTLite',
        Description => 'Manage NOC users with restrictions.',
        Prio => '100',
    };
    
    # Keep original AdminUser for admin users only
    if ($Self->{'Frontend::Module'}->{'AdminUser'}) {
        $Self->{'Frontend::Module'}->{'AdminUser'}->{Group} = ['admin'];
        $Self->{'Frontend::Module'}->{'AdminUser'}->{GroupRo} = [];
    }
    if ($Self->{'Frontend::NavigationModule'}->{'AdminUser'}) {
        $Self->{'Frontend::NavigationModule'}->{'AdminUser'}->{Group} = ['admin'];
        $Self->{'Frontend::NavigationModule'}->{'AdminUser'}->{GroupRo} = [];
    }
    
    # Restrict all OTHER user management modules - only admin group
    my @restrictedManagementModules = qw(
        AdminCustomerUser
        AdminCustomerCompany
        AdminCustomerGroup
        AdminGroup
        AdminRole
        AdminCustomerUserGroup
        AdminRoleUser
        AdminRoleGroup
        AdminUserGroup
        AdminSession
    );

    foreach my $module (@restrictedManagementModules) {
        if ($Self->{'Frontend::Module'}->{$module}) {
            $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::Module'}->{$module}->{GroupRo} = [];
        }
        if ($Self->{'Frontend::NavigationModule'}->{$module}) {
            $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::NavigationModule'}->{$module}->{GroupRo} = [];
        }
        # Also check Frontend::Navigation
        if ($Self->{'Frontend::Navigation'}->{$module}) {
            foreach my $key (keys %{$Self->{'Frontend::Navigation'}->{$module}}) {
                if (ref $Self->{'Frontend::Navigation'}->{$module}->{$key} eq 'ARRAY') {
                    foreach my $item (@{$Self->{'Frontend::Navigation'}->{$module}->{$key}}) {
                        $item->{Group} = ['admin'];
                        $item->{GroupRo} = [];
                    }
                }
            }
        }
    }

    # Allow MSIAdmin and admin access to critical MSST Lite modules
    my @msstLiteCriticalModules = qw(
        AdminAddLicense
        AdminTicketPrefix
        AdminZabbixConfiguration
    );

    foreach my $module (@msstLiteCriticalModules) {
        if ($Self->{'Frontend::Module'}->{$module}) {
            $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin','MSIAdmin'];
            $Self->{'Frontend::Module'}->{$module}->{GroupRo} = [];
        }
        if ($Self->{'Frontend::NavigationModule'}->{$module}) {
            $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin','MSIAdmin'];
            $Self->{'Frontend::NavigationModule'}->{$module}->{GroupRo} = [];
        }
        # Also check Frontend::Navigation
        if ($Self->{'Frontend::Navigation'}->{$module}) {
            foreach my $key (keys %{$Self->{'Frontend::Navigation'}->{$module}}) {
                if (ref $Self->{'Frontend::Navigation'}->{$module}->{$key} eq 'ARRAY') {
                    foreach my $item (@{$Self->{'Frontend::Navigation'}->{$module}->{$key}}) {
                        $item->{Group} = ['admin','MSIAdmin'];
                        $item->{GroupRo} = [];
                    }
                }
            }
        }
    }
    
    # Allow NOCAdmin and MSIAdmin access to notification modules
    my @msstLiteNotificationModules = qw(
        AdminSMTPNotification
        AdminSMSNotification
        AdminEBondingConfiguration
    );

    foreach my $module (@msstLiteNotificationModules) {
        if ($Self->{'Frontend::Module'}->{$module}) {
            $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin','NOCAdmin','MSIAdmin'];
            $Self->{'Frontend::Module'}->{$module}->{GroupRo} = [];
        }
        if ($Self->{'Frontend::NavigationModule'}->{$module}) {
            $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin','NOCAdmin','MSIAdmin'];
            $Self->{'Frontend::NavigationModule'}->{$module}->{GroupRo} = [];
        }
        # Also check Frontend::Navigation
        if ($Self->{'Frontend::Navigation'}->{$module}) {
            foreach my $key (keys %{$Self->{'Frontend::Navigation'}->{$module}}) {
                if (ref $Self->{'Frontend::Navigation'}->{$module}->{$key} eq 'ARRAY') {
                    foreach my $item (@{$Self->{'Frontend::Navigation'}->{$module}->{$key}}) {
                        $item->{Group} = ['admin','NOCAdmin','MSIAdmin'];
                        $item->{GroupRo} = [];
                    }
                }
            }
        }
    }
    
    # AdminExportImportConfig - MSIAdmin and admin can access (NOCAdmin excluded)
    if ($Self->{'Frontend::Module'}->{'AdminExportImportConfig'}) {
        $Self->{'Frontend::Module'}->{'AdminExportImportConfig'}->{Group} = ['admin','MSIAdmin'];
        $Self->{'Frontend::Module'}->{'AdminExportImportConfig'}->{GroupRo} = [];
    }
    if ($Self->{'Frontend::NavigationModule'}->{'AdminExportImportConfig'}) {
        $Self->{'Frontend::NavigationModule'}->{'AdminExportImportConfig'}->{Group} = ['admin','MSIAdmin'];
        $Self->{'Frontend::NavigationModule'}->{'AdminExportImportConfig'}->{GroupRo} = [];
    }
    
    # AdminMSISupportRemoteAccessConfiguration - Full access for MSIAdmin
    if ($Self->{'Frontend::Module'}->{'AdminMSISupportRemoteAccessConfiguration'}) {
        $Self->{'Frontend::Module'}->{'AdminMSISupportRemoteAccessConfiguration'}->{Group} = ['admin','MSIAdmin','NOCAdmin'];
        $Self->{'Frontend::Module'}->{'AdminMSISupportRemoteAccessConfiguration'}->{GroupRo} = [];
    }
    if ($Self->{'Frontend::NavigationModule'}->{'AdminMSISupportRemoteAccessConfiguration'}) {
        $Self->{'Frontend::NavigationModule'}->{'AdminMSISupportRemoteAccessConfiguration'}->{Group} = ['admin','MSIAdmin','NOCAdmin'];
        $Self->{'Frontend::NavigationModule'}->{'AdminMSISupportRemoteAccessConfiguration'}->{GroupRo} = [];
    }

    # === BEGIN: Apply MSIAdmin/admin gating for required modules ===
    # Allow only these for MSIAdmin in their sections
    my @allowForMSIAdmin = (
        # Ticket Settings
        'AdminQueue',
        # Administration
        'AdminSession',
        'AdminSelectBox',
    );

    foreach my $module (@allowForMSIAdmin) {
        if ($Self->{'Frontend::Module'}->{$module}) {
            # AdminQueue and AdminSelectBox restricted to admin only
            if ($module eq 'AdminQueue' || $module eq 'AdminSelectBox') {
                $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin'];
            }
            else {
                # AdminSession available to admin, MSIAdmin, and NOCAdmin
                $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin','MSIAdmin','NOCAdmin'];
            }
            $Self->{'Frontend::Module'}->{$module}->{GroupRo} = [];
        }
        if ($Self->{'Frontend::NavigationModule'}->{$module}) {
            if ($module eq 'AdminQueue' || $module eq 'AdminSelectBox') {
                $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin'];
            }
            else {
                $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin','MSIAdmin','NOCAdmin'];
            }
            $Self->{'Frontend::NavigationModule'}->{$module}->{GroupRo} = [];
            # Ensure proper block placement
            if ($module eq 'AdminQueue') {
                $Self->{'Frontend::NavigationModule'}->{$module}->{Block} = 'Ticket';
            }
            if ($module eq 'AdminSession' || $module eq 'AdminSelectBox') {
                $Self->{'Frontend::NavigationModule'}->{$module}->{Block} = 'Administration';
            }
        }
    }

    # Restrict all other Ticket Settings modules to admin only (keep only AdminQueue for MSIAdmin)
    my @ticketSettingsAdminOnly = qw(
        AdminAttachment AdminAutoResponse AdminPriority AdminQueueAutoResponse
        AdminSalutation AdminSLA AdminService AdminSignature AdminState
        AdminTemplate AdminTemplateAttachment AdminQueueTemplates AdminType
    );
    foreach my $module (@ticketSettingsAdminOnly) {
        if ($Self->{'Frontend::Module'}->{$module}) {
            $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::Module'}->{$module}->{GroupRo} = [];
        }
        if ($Self->{'Frontend::NavigationModule'}->{$module}) {
            $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::NavigationModule'}->{$module}->{GroupRo} = [];
        }
    }

    # Restrict entire Communication & Notifications to admin only
    my @commAndNotifAdminOnly = qw(
        AdminEmail AdminAppointmentNotificationEvent AdminCommunicationLog
        AdminSystemAddress AdminOAuth2TokenManagement AdminPGP
        AdminPostMasterFilter AdminMailAccount AdminSMIME AdminNotificationEvent
    );
    foreach my $module (@commAndNotifAdminOnly) {
        if ($Self->{'Frontend::Module'}->{$module}) {
            $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::Module'}->{$module}->{GroupRo} = [];
        }
        if ($Self->{'Frontend::NavigationModule'}->{$module}) {
            $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::NavigationModule'}->{$module}->{GroupRo} = [];
        }
    }

    # Restrict entire Users, Groups & Roles to admin only (AdminUserNOC already handled above)
    my @usersGroupsRolesAdminOnly = qw(
        AdminUser AdminUserGroup AdminRoleUser AdminCustomerCompany AdminCustomerGroup
        AdminCustomerUser AdminCustomerUserCustomer AdminCustomerUserGroup
        AdminCustomerUserService AdminGroup AdminRole AdminRoleGroup
    );
    foreach my $module (@usersGroupsRolesAdminOnly) {
        if ($Self->{'Frontend::Module'}->{$module}) {
            $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::Module'}->{$module}->{GroupRo} = [];
        }
        if ($Self->{'Frontend::NavigationModule'}->{$module}) {
            $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::NavigationModule'}->{$module}->{GroupRo} = [];
        }
    }

    # Restrict entire Processes & Automation to admin only
    my @processesAutomationAdminOnly = qw(
        AdminACL AdminDynamicField AdminDynamicFieldScreenConfiguration
        AdminGenericAgent AdminProcessManagement AdminTicketAttributeRelations
        AdminGenericInterfaceWebservice
    );
    foreach my $module (@processesAutomationAdminOnly) {
        if ($Self->{'Frontend::Module'}->{$module}) {
            $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::Module'}->{$module}->{GroupRo} = [];
        }
        if ($Self->{'Frontend::NavigationModule'}->{$module}) {
            $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::NavigationModule'}->{$module}->{GroupRo} = [];
        }
    }

    # Restrict other Administration items to admin only (leave AdminSession, AdminSelectBox allowed above)
    my @administrationAdminOnly = qw(
        AdminAppointmentCalendarManage AdminPackageManager AdminPerformanceLog
        AdminSupportDataCollector AdminSystemConfiguration AdminSystemFiles
        AdminLog AdminSystemMaintenance
    );
    foreach my $module (@administrationAdminOnly) {
        if ($Self->{'Frontend::Module'}->{$module}) {
            $Self->{'Frontend::Module'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::Module'}->{$module}->{GroupRo} = [];
        }
        if ($Self->{'Frontend::NavigationModule'}->{$module}) {
            $Self->{'Frontend::NavigationModule'}->{$module}->{Group} = ['admin'];
            $Self->{'Frontend::NavigationModule'}->{$module}->{GroupRo} = [];
        }
    }
    # === END: Apply MSIAdmin/admin gating ===

    # Ensure NavigationModule entries exist with correct blocks
    $Self->{'Frontend::NavigationModule'}->{'AdminQueue'} //= {};
    $Self->{'Frontend::NavigationModule'}->{'AdminQueue'}->{Group}   = ['admin'];
    $Self->{'Frontend::NavigationModule'}->{'AdminQueue'}->{GroupRo} = [];
    $Self->{'Frontend::NavigationModule'}->{'AdminQueue'}->{Module}  = 'Kernel::Output::HTML::NavBar::ModuleAdmin';
    $Self->{'Frontend::NavigationModule'}->{'AdminQueue'}->{Name}  //= 'Queues';
    $Self->{'Frontend::NavigationModule'}->{'AdminQueue'}->{Block}   = 'Ticket';
    $Self->{'Frontend::NavigationModule'}->{'AdminQueue'}->{Prio}  //= '300';

    $Self->{'Frontend::NavigationModule'}->{'AdminSession'} //= {};
    $Self->{'Frontend::NavigationModule'}->{'AdminSession'}->{Group}   = ['admin','MSIAdmin','NOCAdmin'];
    $Self->{'Frontend::NavigationModule'}->{'AdminSession'}->{GroupRo} = [];
    $Self->{'Frontend::NavigationModule'}->{'AdminSession'}->{Module}  = 'Kernel::Output::HTML::NavBar::ModuleAdmin';
    $Self->{'Frontend::NavigationModule'}->{'AdminSession'}->{Name}  //= 'Session Management';
    $Self->{'Frontend::NavigationModule'}->{'AdminSession'}->{Block}   = 'Administration';
    $Self->{'Frontend::NavigationModule'}->{'AdminSession'}->{Prio}  //= '300';

    $Self->{'Frontend::NavigationModule'}->{'AdminSelectBox'} //= {};
    $Self->{'Frontend::NavigationModule'}->{'AdminSelectBox'}->{Group}   = ['admin'];
    $Self->{'Frontend::NavigationModule'}->{'AdminSelectBox'}->{GroupRo} = [];
    $Self->{'Frontend::NavigationModule'}->{'AdminSelectBox'}->{Module}  = 'Kernel::Output::HTML::NavBar::ModuleAdmin';
    $Self->{'Frontend::NavigationModule'}->{'AdminSelectBox'}->{Name}  //= 'SQL Box';
    $Self->{'Frontend::NavigationModule'}->{'AdminSelectBox'}->{Block}   = 'Administration';
    $Self->{'Frontend::NavigationModule'}->{'AdminSelectBox'}->{Prio}  //= '300';

    return 1;
}

1;