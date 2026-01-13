// --
// Copyright (C) 2025 MSST Lite
// --
// This software comes with ABSOLUTELY NO WARRANTY.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace Core.Agent.IncidentReport
 * @memberof Core.Agent
 * @description
 *      This namespace contains the functionality for the Incident Report page.
 */
Core.Agent.IncidentReport = (function (TargetNS) {

    var CurrentPage = 1;

    TargetNS.Init = function () {
        // Load initial data
        TargetNS.LoadAllData();

        // Bind event handlers
        $('#TimeRange').on('change', function() {
            CurrentPage = 1;
            TargetNS.LoadAllData();
        });

        $('#ExportCSV').on('click', function() {
            TargetNS.ExportCSV();
        });

        $('#PrevPage').on('click', function() {
            if (CurrentPage > 1) {
                CurrentPage--;
                TargetNS.LoadTabularData();
            }
        });

        $('#NextPage').on('click', function() {
            CurrentPage++;
            TargetNS.LoadTabularData();
        });
    };

    TargetNS.LoadAllData = function () {
        TargetNS.LoadTrendingData();
        TargetNS.LoadTabularData();
        TargetNS.LoadMSIHandoverData();
    };

    TargetNS.LoadTrendingData = function () {
        var timeRange = $('#TimeRange').val();

        $.ajax({
            url: Core.Config.Get('Baselink'),
            type: 'POST',
            data: {
                Action: 'AgentIncidentReport',
                Subaction: 'GetTrendingData',
                TimeRange: timeRange
            },
            dataType: 'json',
            success: function (response) {
                if (response.Success && response.Data) {
                    TargetNS.RenderTrendingData(response.Data);
                } else {
                    alert('Failed to load trending data');
                }
            },
            error: function () {
                alert('Error loading trending data');
            }
        });
    };

    TargetNS.RenderTrendingData = function (data) {
        // Update summary stats
        $('#TotalIncidents').text(data.Total || 0);
        $('#LSMPCount').text(data.BySource.LSMP || data.BySource['Event Monitoring'] || 0);
        $('#ManualCount').text(data.BySource.Manual || 0);

        // Update severity breakdown table
        var severityHTML = '';
        var severities = ['P1', 'P2', 'P3', 'P4'];
        for (var i = 0; i < severities.length; i++) {
            var priority = severities[i];
            var count = data.BySeverity[priority] || 0;
            severityHTML += '<tr><td>' + priority + '</td><td>' + count + '</td></tr>';
        }
        $('#SeverityBreakdownTable').html(severityHTML);

        // Render breakdown table
        var breakdownHTML = '';
        for (var i = 0; i < data.Breakdown.length; i++) {
            var item = data.Breakdown[i];
            breakdownHTML += '<tr>';
            breakdownHTML += '<td>' + item.Label + '</td>';
            breakdownHTML += '<td>' + item.Count + '</td>';
            breakdownHTML += '<td>' + item.Percentage + '%</td>';
            breakdownHTML += '</tr>';
        }
        $('#TrendingBreakdownTable').html(breakdownHTML);
    };

    TargetNS.LoadTabularData = function () {
        var timeRange = $('#TimeRange').val();

        $.ajax({
            url: Core.Config.Get('Baselink'),
            type: 'POST',
            data: {
                Action: 'AgentIncidentReport',
                Subaction: 'GetTabularData',
                TimeRange: timeRange,
                Page: CurrentPage,
                PageSize: 100
            },
            dataType: 'json',
            success: function (response) {
                if (response.Success && response.Data) {
                    TargetNS.RenderTabularData(response.Data);
                } else {
                    alert('Failed to load tabular data');
                }
            },
            error: function () {
                alert('Error loading tabular data');
            }
        });
    };

    TargetNS.RenderTabularData = function (data) {
        var tableHTML = '';

        if (data.Tickets.length === 0) {
            tableHTML = '<tr><td colspan="10" class="Center">No incidents found</td></tr>';
        } else {
            for (var i = 0; i < data.Tickets.length; i++) {
                var ticket = data.Tickets[i];
                tableHTML += '<tr>';
                tableHTML += '<td><a href="' + Core.Config.Get('Baselink') + 'Action=AgentTicketZoom;TicketID=' + ticket.TicketID + '" target="_blank">' + ticket.TicketNumber + '</a></td>';
                tableHTML += '<td>' + TargetNS.EscapeHTML(ticket.Title) + '</td>';
                tableHTML += '<td>' + ticket.Priority + '</td>';
                tableHTML += '<td>' + ticket.Created + '</td>';
                tableHTML += '<td>' + ticket.Source + '</td>';
                tableHTML += '<td>' + TargetNS.EscapeHTML(ticket.Device) + '</td>';
                tableHTML += '<td>' + (ticket.ProdCat || '-') + '</td>';
                tableHTML += '<td>' + (ticket.OpsCat || '-') + '</td>';
                tableHTML += '<td>' + (ticket.ResCat || '-') + '</td>';
                tableHTML += '<td>' + (ticket.MSITicketNumber || '-') + '</td>';
                tableHTML += '</tr>';
            }
        }

        $('#IncidentTableBody').html(tableHTML);

        $('#PaginationInfo').text('Showing ' + data.Tickets.length + ' of ' + data.TotalCount + ' incidents');
        $('#PageInfo').text('Page ' + data.CurrentPage + ' of ' + data.TotalPages);

        $('#PrevPage').prop('disabled', data.CurrentPage <= 1);
        $('#NextPage').prop('disabled', data.CurrentPage >= data.TotalPages);
    };

    TargetNS.LoadMSIHandoverData = function () {
        var timeRange = $('#TimeRange').val();

        $.ajax({
            url: Core.Config.Get('Baselink'),
            type: 'POST',
            data: {
                Action: 'AgentIncidentReport',
                Subaction: 'GetMSIHandoverData',
                TimeRange: timeRange
            },
            dataType: 'json',
            success: function (response) {
                if (response.Success && response.Data) {
                    TargetNS.RenderMSIHandoverData(response.Data);
                }
            },
            error: function () {
                console.log('Error loading MSI handover data');
            }
        });
    };

    TargetNS.FormatTimeWithMSI = function (seconds) {
        if (!seconds || seconds <= 0) return '-';

        var hours = Math.floor(seconds / 3600);
        var minutes = Math.floor((seconds % 3600) / 60);

        if (hours < 1) {
            // Less than 1 hour: show minutes
            return minutes + 'm';
        } else if (hours < 24) {
            // Less than 24 hours: show hours and minutes
            if (minutes > 0) {
                return hours + 'h ' + minutes + 'm';
            }
            return hours + 'h';
        } else {
            // 24 hours or more: show days and hours
            var days = Math.floor(hours / 24);
            var remainingHours = hours % 24;
            if (remainingHours > 0) {
                return days + 'd ' + remainingHours + 'h';
            }
            return days + 'd';
        }
    };

    TargetNS.RenderMSIHandoverData = function (data) {
        $('#MSITotalHandovers').text(data.TotalHandovers || 0);
        $('#MSIPercentage').text((data.PercentageOfTotal || 0) + '%');
        $('#MSIHandoverCount').text(data.TotalHandovers || 0);

        var totalTime = 0;
        var count = 0;
        for (var i = 0; i < data.Details.length; i++) {
            var timeVal = parseFloat(data.Details[i].TimeWithMSI);
            if (!isNaN(timeVal) && timeVal > 0) {
                totalTime += timeVal;
                count++;
            }
        }
        var avgTimeSeconds = count > 0 ? totalTime / count : 0;
        $('#MSIAvgTime').text(TargetNS.FormatTimeWithMSI(avgTimeSeconds));

        var tableHTML = '';
        if (data.Details.length === 0) {
            tableHTML = '<tr><td colspan="7" class="Center">No MSI handovers found</td></tr>';
        } else {
            for (var i = 0; i < data.Details.length; i++) {
                var detail = data.Details[i];
                var timeWithMSI = TargetNS.FormatTimeWithMSI(detail.TimeWithMSI);
                tableHTML += '<tr>';
                tableHTML += '<td><a href="' + Core.Config.Get('Baselink') + 'Action=AgentTicketZoom;TicketID=' + detail.TicketID + '" target="_blank">' + detail.TicketNumber + '</a></td>';
                tableHTML += '<td>' + detail.Priority + '</td>';
                tableHTML += '<td>' + (detail.ProdCat || '-') + '</td>';
                tableHTML += '<td>' + (detail.OpsCat || '-') + '</td>';
                tableHTML += '<td>' + detail.EscalationDate + '</td>';
                tableHTML += '<td>' + timeWithMSI + '</td>';
                tableHTML += '<td>' + detail.MSITicketNumber + '</td>';
                tableHTML += '</tr>';
            }
        }
        $('#HandoverTableBody').html(tableHTML);
    };

    TargetNS.ExportCSV = function () {
        var timeRange = $('#TimeRange').val();
        var url = Core.Config.Get('Baselink') + 'Action=AgentIncidentReport;Subaction=ExportCSV';
        url += ';TimeRange=' + encodeURIComponent(timeRange);
        window.open(url, '_blank');
    };

    TargetNS.EscapeHTML = function (text) {
        if (!text) return '';
        var map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text.replace(/[&<>"']/g, function(m) { return map[m]; });
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;

}(Core.Agent.IncidentReport || {}));
