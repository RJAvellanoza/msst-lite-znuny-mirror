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
 * @namespace Core.Agent.Admin.EBondingConfiguration
 * @memberof Core.Agent.Admin
 * @author MSST
 * @description
 *      This namespace contains the special functions for the Easy MSI Escalation ServiceNow integration configuration.
 */
Core.Agent.Admin.EBondingConfiguration = (function (TargetNS) {

    /**
     * @name Init
     * @memberof Core.Agent.Admin.EBondingConfiguration
     * @function
     * @description
     *      This function initializes the special module functions.
     */
    TargetNS.Init = function () {
        $('#TestConnection').off('click.EBondingTest').on('click.EBondingTest', function(Event) {
            Event.preventDefault();
            TargetNS.TestConnection();
            return false;
        });

        // Initialize API logs loading
        TargetNS.LoadAPILogs();

        // Refresh logs button
        $('#RefreshLogs').off('click.RefreshLogs').on('click.RefreshLogs', function(Event) {
            Event.preventDefault();
            TargetNS.LoadAPILogs();
            return false;
        });

        // Filter change
        $('#LogFilter').off('change.LogFilter').on('change.LogFilter', function() {
            TargetNS.LoadAPILogs();
        });
    };

    /**
     * @name TestConnection
     * @memberof Core.Agent.Admin.EBondingConfiguration
     * @function
     * @description
     *      Tests the ServiceNow API connection with proper CSRF protection.
     */
    TargetNS.TestConnection = function () {
        var Data = {};

        // Show testing message
        $('#ConnectionTestResult').show();
        $('#TestResultMessage').html('<p class="Notice"><i class="fa fa-spinner fa-spin"></i> ' +
            Core.Language.Translate('Testing connection...') + '</p>');

        // Prepare data with CSRF protection
        Data = {
            Action: 'AdminEBondingConfiguration',
            Subaction: 'TestConnection'
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

    /**
     * @name LoadAPILogs
     * @memberof Core.Agent.Admin.EBondingConfiguration
     * @function
     * @description
     *      Loads Easy MSI Escalation API logs from the database.
     */
    TargetNS.LoadAPILogs = function () {
        var Filter = $('#LogFilter').val() || '7d';
        var Data = {
            Action: 'AdminEBondingConfiguration',
            Subaction: 'LoadAPILogs',
            Filter: Filter
        };

        // Add session security token
        Data[Core.Config.Get('SessionName')] = Core.Config.Get('SessionID');

        // Show loading message
        $('#APILogsTableContainer').html('<p class="Center"><i class="fa fa-spinner fa-spin"></i> ' +
            Core.Language.Translate('Loading API logs...') + '</p>');

        // Make AJAX request
        $.ajax({
            url: Core.Config.Get('CGIHandle'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                if (Response && Response.Success) {
                    TargetNS.RenderAPILogsTable(Response.Logs);
                } else {
                    $('#APILogsTableContainer').html('<p class="Error"><i class="fa fa-exclamation-triangle"></i> ' +
                        (Response.Message || Core.Language.Translate('Failed to load API logs')) + '</p>');
                }
            },
            error: function () {
                $('#APILogsTableContainer').html('<p class="Error"><i class="fa fa-exclamation-triangle"></i> ' +
                    Core.Language.Translate('Failed to load API logs') + '</p>');
            }
        });
    };

    /**
     * @name RenderAPILogsTable
     * @memberof Core.Agent.Admin.EBondingConfiguration
     * @function
     * @param {Array} Logs - Array of log entries
     * @description
     *      Renders the API logs table.
     */
    TargetNS.RenderAPILogsTable = function (Logs) {
        if (!Logs || Logs.length === 0) {
            $('#APILogsTableContainer').html('<p class="Center">' +
                Core.Language.Translate('No API logs found for the selected time period.') + '</p>');
            return;
        }

        var HTML = '<table class="DataTable">' +
            '<thead>' +
            '<tr>' +
            '<th>' + Core.Language.Translate('Time') + '</th>' +
            '<th>' + Core.Language.Translate('Incident') + '</th>' +
            '<th>' + Core.Language.Translate('Status') + '</th>' +
            '<th>' + Core.Language.Translate('MSI Ticket') + '</th>' +
            '<th>' + Core.Language.Translate('Error') + '</th>' +
            '<th>' + Core.Language.Translate('Actions') + '</th>' +
            '</tr>' +
            '</thead>' +
            '<tbody>';

        $.each(Logs, function(index, log) {
            var StatusIcon = log.Success ?
                '<i class="fa fa-check-circle" style="color: green;" title="Success"></i>' :
                '<i class="fa fa-times-circle" style="color: red;" title="Failed"></i>';

            var MSITicket = log.MSITicketNumber || '-';
            var ErrorMsg = log.ErrorMessage || '-';
            if (ErrorMsg.length > 50) {
                ErrorMsg = ErrorMsg.substring(0, 50) + '...';
            }

            HTML += '<tr>' +
                '<td>' + log.CreateTime + '</td>' +
                '<td>' + log.IncidentNumber + '</td>' +
                '<td class="Center">' + StatusIcon + '</td>' +
                '<td>' + MSITicket + '</td>' +
                '<td>' + ErrorMsg + '</td>' +
                '<td class="Center">' +
                '<button type="button" class="CallForAction Small" data-log-id="' + log.ID + '" ' +
                'onclick="Core.Agent.Admin.EBondingConfiguration.ViewLogDetails(' + log.ID + '); return false;">' +
                '<span><i class="fa fa-eye"></i> ' + Core.Language.Translate('Details') + '</span>' +
                '</button>' +
                '</td>' +
                '</tr>';
        });

        HTML += '</tbody></table>';

        $('#APILogsTableContainer').html(HTML);
    };

    /**
     * @name ViewLogDetails
     * @memberof Core.Agent.Admin.EBondingConfiguration
     * @function
     * @param {Number} LogID - The log entry ID
     * @description
     *      Shows detailed request/response for a log entry.
     */
    TargetNS.ViewLogDetails = function (LogID) {
        if (!LogID) {
            alert('Error: No log ID provided');
            return;
        }

        // Show modal with loading state
        $('#LogDetailRequest').html('<i class="fa fa-spinner fa-spin"></i> Loading...');
        $('#LogDetailResponse').html('<i class="fa fa-spinner fa-spin"></i> Loading...');
        $('#LogDetailBackdrop').show();
        $('#LogDetailModal').show();

        // Fetch details via AJAX
        var Data = {
            Action: 'AdminEBondingConfiguration',
            Subaction: 'GetLogDetails',
            LogID: LogID
        };

        // Add session security token
        Data[Core.Config.Get('SessionName')] = Core.Config.Get('SessionID');

        $.ajax({
            url: Core.Config.Get('CGIHandle'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                if (Response && Response.Success) {
                    // Format JSON
                    try {
                        var RequestJSON = JSON.parse(Response.RequestPayload);
                        $('#LogDetailRequest').text(JSON.stringify(RequestJSON, null, 2));
                    } catch (e) {
                        $('#LogDetailRequest').text(Response.RequestPayload || 'No request data');
                    }

                    try {
                        var ResponseJSON = JSON.parse(Response.ResponsePayload);
                        $('#LogDetailResponse').text(JSON.stringify(ResponseJSON, null, 2));
                    } catch (e) {
                        $('#LogDetailResponse').text(Response.ResponsePayload || 'No response data');
                    }
                } else {
                    $('#LogDetailRequest').html('<p class="Error">Failed to load details</p>');
                    $('#LogDetailResponse').html('<p class="Error">Failed to load details</p>');
                }
            },
            error: function (xhr, status, error) {
                $('#LogDetailRequest').html('<p class="Error">Error loading details</p>');
                $('#LogDetailResponse').html('<p class="Error">Error loading details</p>');
            }
        });
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;

}(Core.Agent.Admin.EBondingConfiguration || {}));
