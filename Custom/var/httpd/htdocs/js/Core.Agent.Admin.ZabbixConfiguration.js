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
 * @namespace Core.Agent.Admin.ZabbixConfiguration
 * @memberof Core.Agent.Admin
 * @author MSST
 * @description
 *      This namespace contains the special functions for the Zabbix Integration configuration.
 */
Core.Agent.Admin.ZabbixConfiguration = (function (TargetNS) {

    /**
     * @name Init
     * @memberof Core.Agent.Admin.ZabbixConfiguration
     * @function
     * @description
     *      This function initializes the special module functions.
     */
    TargetNS.Init = function () {
        $('#TestConnection').off('click.ZabbixTest').on('click.ZabbixTest', function(Event) {
            Event.preventDefault();
            TargetNS.TestConnection();
            return false;
        });
    };

    /**
     * @name TestConnection
     * @memberof Core.Agent.Admin.ZabbixConfiguration
     * @function
     * @description
     *      Tests the Zabbix API connection with proper CSRF protection.
     */
    TargetNS.TestConnection = function () {
        var URL = $('#APIURL').val(),
            User = $('#APIUser').val(),
            Password = $('#APIPassword').val(),
            Data = {};

        // Validate required fields
        if (!URL || !User || !Password) {
            alert(Core.Language.Translate('Please fill in all required fields (URL, Username, Password)'));
            return;
        }

        // Show testing message
        $('#ConnectionTestResult').show();
        $('#TestResultMessage').html('<p class="Notice"><i class="fa fa-spinner fa-spin"></i> ' + 
            Core.Language.Translate('Testing connection...') + '</p>');

        // Prepare data with CSRF protection
        Data = {
            Action: 'AdminZabbixConfiguration',
            Subaction: 'TestConnection',
            APIURL: URL,
            APIUser: User,
            APIPassword: Password
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
                    $('#TestResultMessage').html('<p class="Success"><i class="fa fa-check"></i> ' + 
                        (Response.Message || Core.Language.Translate('Connection successful!')) + '</p>');
                } else {
                    $('#TestResultMessage').html('<p class="Error"><i class="fa fa-times"></i> ' + 
                        (Response.Message || Response.ErrorMessage || Core.Language.Translate('Connection failed')) + '</p>');
                }
            },
            error: function (xhr, status, error) {
                var ErrorMsg = Core.Language.Translate('Connection test failed');
                try {
                    var Response = JSON.parse(xhr.responseText);
                    if (Response && Response.Message) {
                        ErrorMsg = Response.Message;
                    }
                } catch (e) {
                    // Use default error message
                }
                $('#TestResultMessage').html('<p class="Error"><i class="fa fa-exclamation-triangle"></i> ' + ErrorMsg + '</p>');
            }
        });
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;

}(Core.Agent.Admin.ZabbixConfiguration || {}));