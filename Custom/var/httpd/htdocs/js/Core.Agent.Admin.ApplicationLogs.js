// --
// Copyright (C) 2025 MSST, https://msst.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (GPL). If you
// did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};
Core.Agent.Admin = Core.Agent.Admin || {};

/**
 * @namespace Core.Agent.Admin.ApplicationLogs
 * @memberof Core.Agent.Admin
 * @author MSST
 * @description
 *      This namespace contains the special functions for the Application Logs configuration.
 */
Core.Agent.Admin.ApplicationLogs = (function (TargetNS) {

    /**
     * @name Init
     * @memberof Core.Agent.Admin.ApplicationLogs
     * @function
     * @description
     *      This function initializes the special module functions.
     */
    TargetNS.Init = function () {
        // Bind Syslog test connection
        $('#TestSyslogConnection').off('click.SyslogTest').on('click.SyslogTest', function(Event) {
            Event.preventDefault();
            TargetNS.TestSyslogConnection();
            return false;
        });

        // Bind export logs
        $('#ExportLogs').off('click.ExportLogs').on('click.ExportLogs', function(Event) {
            Event.preventDefault();
            TargetNS.ExportLogs();
            return false;
        });

        // Sync form fields when typing
        TargetNS.SyncFormFields();
    };

    /**
     * @name SyncFormFields
     * @memberof Core.Agent.Admin.ApplicationLogs
     * @function
     * @description
     *      Syncs form field values between different forms and hidden fields.
     */
    TargetNS.SyncFormFields = function () {
        // Sync Syslog fields
        $('#SyslogSSHHost').on('input', function() {
            $('input[name="SyslogSSHHost"]').val($(this).val());
        });
        $('#SyslogSSHPort').on('input', function() {
            $('input[name="SyslogSSHPort"]').val($(this).val());
        });
        $('#SyslogSSHUser').on('input', function() {
            $('input[name="SyslogSSHUser"]').val($(this).val());
        });
        $('#SyslogSSHKeyPath').on('input', function() {
            $('input[name="SyslogSSHKeyPath"]').val($(this).val());
        });
        $('#SyslogLogPaths').on('input', function() {
            $('input[name="SyslogLogPaths"]').val($(this).val());
        });
        $('#StartDate').on('input', function() {
            $('input[name="StartDate"]').val($(this).val());
        });
        $('#EndDate').on('input', function() {
            $('input[name="EndDate"]').val($(this).val());
        });
    };

    /**
     * @name TestZabbixConnection
     * @memberof Core.Agent.Admin.ApplicationLogs
     * @function
     * @description
     *      Tests the Zabbix SSH connection with proper CSRF protection.
     */
    TargetNS.TestZabbixConnection = function () {
        var Host = $('#ZabbixSSHHost').val(),
            Port = $('#ZabbixSSHPort').val(),
            User = $('#ZabbixSSHUser').val(),
            Pass = $('#ZabbixSSHPass').val(),
            Data = {};

        // Validate required fields
        if (!Host || !User || !Pass) {
            alert(Core.Language.Translate('Please fill in all required Zabbix fields (Host, User, Password)'));
            return;
        }

        // Show testing message
        $('#ZabbixConnectionTestResult').show();
        $('#ZabbixTestResultMessage').html('<p class="Notice"><i class="fa fa-spinner fa-spin"></i> ' + 
            Core.Language.Translate('Testing Zabbix SSH connection...') + '</p>');

        // Prepare data with CSRF protection
        Data = {
            Action: 'AdminApplicationLogs',
            Subaction: 'TestZabbixConnection',
            ZabbixSSHHost: Host,
            ZabbixSSHPort: Port,
            ZabbixSSHUser: User,
            ZabbixSSHPass: Pass
        };

        // Add session security token
        Data[Core.Config.Get('SessionName')] = Core.Config.Get('SessionID');

        // Add challenge token if available
        if (Core.Config.Get('ChallengeToken')) {
            Data.ChallengeToken = Core.Config.Get('ChallengeToken');
        }

        // Make secure AJAX request using jQuery AJAX directly (Znuny-compatible pattern)
        $.ajax({
            url: Core.Config.Get('CGIHandle'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                if (Response && Response.Success) {
                    $('#ZabbixTestResultMessage').html('<p class="Success"><i class="fa fa-check"></i> ' + 
                        (Response.Message || Core.Language.Translate('Zabbix SSH connection successful!')) + '</p>');
                } else {
                    $('#ZabbixTestResultMessage').html('<p class="Error"><i class="fa fa-times"></i> ' + 
                        (Response.Message || Response.ErrorMessage || Core.Language.Translate('Zabbix SSH connection failed')) + '</p>');
                }
            },
            error: function (xhr, status, error) {
                var ErrorMsg = Core.Language.Translate('Zabbix connection test failed');
                try {
                    var Response = JSON.parse(xhr.responseText);
                    if (Response && Response.Message) {
                        ErrorMsg = Response.Message;
                    }
                } catch (e) {
                    // Use default error message
                }
                $('#ZabbixTestResultMessage').html('<p class="Error"><i class="fa fa-exclamation-triangle"></i> ' + ErrorMsg + '</p>');
            }
        });
    };

    /**
     * @name TestProxmoxConnection
     * @memberof Core.Agent.Admin.ApplicationLogs
     * @function
     * @description
     *      Tests the Proxmox SSH connection with proper CSRF protection.
     */
    TargetNS.TestProxmoxConnection = function () {
        var Host = $('#ProxmoxSSHHost').val(),
            Port = $('#ProxmoxSSHPort').val(),
            User = $('#ProxmoxSSHUser').val(),
            Pass = $('#ProxmoxSSHPass').val(),
            Data = {};

        // Validate required fields
        if (!Host || !User || !Pass) {
            alert(Core.Language.Translate('Please fill in all required Proxmox fields (Host, User, Password)'));
            return;
        }

        // Show testing message
        $('#ProxmoxConnectionTestResult').show();
        $('#ProxmoxTestResultMessage').html('<p class="Notice"><i class="fa fa-spinner fa-spin"></i> ' + 
            Core.Language.Translate('Testing Proxmox SSH connection...') + '</p>');

        // Prepare data with CSRF protection
        Data = {
            Action: 'AdminApplicationLogs',
            Subaction: 'TestProxmoxConnection',
            ProxmoxSSHHost: Host,
            ProxmoxSSHPort: Port,
            ProxmoxSSHUser: User,
            ProxmoxSSHPass: Pass
        };

        // Add session security token
        Data[Core.Config.Get('SessionName')] = Core.Config.Get('SessionID');

        // Add challenge token if available
        if (Core.Config.Get('ChallengeToken')) {
            Data.ChallengeToken = Core.Config.Get('ChallengeToken');
        }

        // Make secure AJAX request using jQuery AJAX directly (Znuny-compatible pattern)
        $.ajax({
            url: Core.Config.Get('CGIHandle'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                if (Response && Response.Success) {
                    $('#ProxmoxTestResultMessage').html('<p class="Success"><i class="fa fa-check"></i> ' + 
                        (Response.Message || Core.Language.Translate('Proxmox SSH connection successful!')) + '</p>');
                } else {
                    $('#ProxmoxTestResultMessage').html('<p class="Error"><i class="fa fa-times"></i> ' + 
                        (Response.Message || Response.ErrorMessage || Core.Language.Translate('Proxmox SSH connection failed')) + '</p>');
                }
            },
            error: function (xhr, status, error) {
                var ErrorMsg = Core.Language.Translate('Proxmox connection test failed');
                try {
                    var Response = JSON.parse(xhr.responseText);
                    if (Response && Response.Message) {
                        ErrorMsg = Response.Message;
                    }
                } catch (e) {
                    // Use default error message
                }
                $('#ProxmoxTestResultMessage').html('<p class="Error"><i class="fa fa-exclamation-triangle"></i> ' + ErrorMsg + '</p>');
            }
        });
    };

    /**
     * @name ExportLogs
     * @memberof Core.Agent.Admin.ApplicationLogs
     * @function
     * @description
     *      Downloads the syslog file from the configured server.
     */
    TargetNS.ExportLogs = function () {
        // Confirm download action
        if (!confirm(Core.Language.Translate('This will download the syslog file from the configured server. Continue?'))) {
            return;
        }

        // Create a temporary form for POST submission with CSRF protection
        var Form = $('<form></form>');
        Form.attr('method', 'post');
        Form.attr('action', Core.Config.Get('CGIHandle'));
        Form.hide();

        // Add required fields
        Form.append($('<input>').attr('type', 'hidden').attr('name', 'Action').val('AdminApplicationLogs'));
        Form.append($('<input>').attr('type', 'hidden').attr('name', 'Subaction').val('ExportLogs'));
        Form.append($('<input>').attr('type', 'hidden').attr('name', Core.Config.Get('SessionName')).val(Core.Config.Get('SessionID')));

        // Add date range fields from the form
        Form.append($('<input>').attr('type', 'hidden').attr('name', 'StartDate').val($('#StartDate').val()));
        Form.append($('<input>').attr('type', 'hidden').attr('name', 'EndDate').val($('#EndDate').val()));

        // Add challenge token if available
        if (Core.Config.Get('ChallengeToken')) {
            Form.append($('<input>').attr('type', 'hidden').attr('name', 'ChallengeToken').val(Core.Config.Get('ChallengeToken')));
        }

        // Append form to body and submit
        $('body').append(Form);
        Form.submit();

        // Clean up
        Form.remove();

        // Show informational message
        alert(Core.Language.Translate('Syslog download started. The download will begin shortly if successful.'));
    };

    /**
     * @name TestSyslogConnection
     * @memberof Core.Agent.Admin.ApplicationLogs
     * @function
     * @description
     *      Tests the Syslog SSH connection with proper CSRF protection.
     */
    TargetNS.TestSyslogConnection = function () {
        var Data = {};

        // Show testing message
        $('#SyslogConnectionTestResult').show();
        $('#SyslogTestResultMessage').html('<p class="Notice"><i class="fa fa-spinner fa-spin"></i> ' +
            Core.Language.Translate('Testing Syslog SSH connection...') + '</p>');

        // Prepare data with CSRF protection
        Data = {
            Action: 'AdminApplicationLogs',
            Subaction: 'TestSyslogConnection'
        };

        // Add session security token
        Data[Core.Config.Get('SessionName')] = Core.Config.Get('SessionID');

        // Add challenge token if available
        if (Core.Config.Get('ChallengeToken')) {
            Data.ChallengeToken = Core.Config.Get('ChallengeToken');
        }

        // Make secure AJAX request using jQuery AJAX directly (Znuny-compatible pattern)
        $.ajax({
            url: Core.Config.Get('CGIHandle'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                if (Response && Response.Success) {
                    $('#SyslogTestResultMessage').html('<p class="Success"><i class="fa fa-check"></i> ' +
                        (Response.Message || Core.Language.Translate('Syslog SSH connection successful!')) + '</p>');
                } else {
                    $('#SyslogTestResultMessage').html('<p class="Error"><i class="fa fa-times"></i> ' +
                        (Response.Message || Response.ErrorMessage || Core.Language.Translate('Syslog SSH connection failed')) + '</p>');
                }
            },
            error: function (xhr, status, error) {
                var ErrorMsg = Core.Language.Translate('Syslog connection test failed');
                try {
                    var Response = JSON.parse(xhr.responseText);
                    if (Response && Response.Message) {
                        ErrorMsg = Response.Message;
                    }
                } catch (e) {
                    // Use default error message
                }
                $('#SyslogTestResultMessage').html('<p class="Error"><i class="fa fa-exclamation-triangle"></i> ' + ErrorMsg + '</p>');
            }
        });
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;

}(Core.Agent.Admin.ApplicationLogs || {}));