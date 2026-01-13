// --
// Copyright (C) 2025 MSST, https://msst.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace Core.Agent.OperationalKPIsReport
 * @memberof Core.Agent
 * @author MSST
 * @description
 *      This namespace contains the special module functions for the Operational KPIs Report.
 */
Core.Agent.OperationalKPIsReport = (function (TargetNS) {

    /**
     * @name Init
     * @memberof Core.Agent.OperationalKPIsReport
     * @function
     * @description
     *      This function initializes the Operational KPIs Report module.
     */
    TargetNS.Init = function () {

        // Initialize date pickers if available
        if ($.fn.datepicker) {
            $('#DateStart, #DateEnd').datepicker({
                dateFormat: 'yy-mm-dd',
                maxDate: 0, // No future dates
                onSelect: function(dateText, inst) {
                    // Validate date range
                    Core.Agent.OperationalKPIsReport.ValidateDateRange();
                }
            });
        }

        // Set default date range if not set
        if (!$('#DateStart').val() || !$('#DateEnd').val()) {
            Core.Agent.OperationalKPIsReport.SetDefaultDateRange();
        }

        // Bind form validation
        $('#OperationalKPIsFilterForm').on('submit', function(event) {
            if (!Core.Agent.OperationalKPIsReport.ValidateForm()) {
                event.preventDefault();
                return false;
            }
        });

        // Initialize loading states
        Core.Agent.OperationalKPIsReport.InitLoadingStates();

        // Initialize export handlers
        Core.Agent.OperationalKPIsReport.InitExportHandlers();
    };

    /**
     * @name ValidateDateRange
     * @memberof Core.Agent.OperationalKPIsReport
     * @function
     * @description
     *      Validates the selected date range.
     */
    TargetNS.ValidateDateRange = function () {
        var StartDate = $('#DateStart').val(),
            EndDate = $('#DateEnd').val(),
            StartDateObj = new Date(StartDate),
            EndDateObj = new Date(EndDate);

        // Clear previous validation messages
        $('.DateValidationError').remove();

        if (StartDate && EndDate) {
            if (StartDateObj > EndDateObj) {
                $('#DateEnd').after('<div class="DateValidationError Error">' +
                    Core.Language.Translate('End date must be after start date.') + '</div>');
                return false;
            }

            // Check against data retention period (180 days default)
            var MaxStartDate = new Date();
            MaxStartDate.setDate(MaxStartDate.getDate() - 180);

            if (StartDateObj < MaxStartDate) {
                $('#DateStart').after('<div class="DateValidationError Warning">' +
                    Core.Language.Translate('Start date exceeds data retention period. Results may be incomplete.') + '</div>');
            }
        }

        return true;
    };

    /**
     * @name ValidateForm
     * @memberof Core.Agent.OperationalKPIsReport
     * @function
     * @description
     *      Validates the entire filter form.
     */
    TargetNS.ValidateForm = function () {
        var IsValid = true;

        // Validate date range
        if (!Core.Agent.OperationalKPIsReport.ValidateDateRange()) {
            IsValid = false;
        }

        // Validate required fields
        $('#OperationalKPIsFilterForm input[required], #OperationalKPIsFilterForm select[required]').each(function() {
            if (!$(this).val()) {
                $(this).addClass('Error');
                if ($(this).next('.FieldError').length === 0) {
                    $(this).after('<div class="FieldError Error">' +
                        Core.Language.Translate('This field is required.') + '</div>');
                }
                IsValid = false;
            } else {
                $(this).removeClass('Error');
                $(this).next('.FieldError').remove();
            }
        });

        return IsValid;
    };

    /**
     * @name SetDefaultDateRange
     * @memberof Core.Agent.OperationalKPIsReport
     * @function
     * @description
     *      Sets the default date range (last 30 days).
     */
    TargetNS.SetDefaultDateRange = function () {
        var EndDate = new Date(),
            StartDate = new Date();

        StartDate.setDate(EndDate.getDate() - 30);

        $('#DateStart').val(StartDate.toISOString().split('T')[0]);
        $('#DateEnd').val(EndDate.toISOString().split('T')[0]);
    };

    /**
     * @name InitLoadingStates
     * @memberof Core.Agent.OperationalKPIsReport
     * @function
     * @description
     *      Initializes loading state handlers.
     */
    TargetNS.InitLoadingStates = function () {
        // Show loading indicator during AJAX requests
        $(document).ajaxStart(function() {
            $('#LoadingIndicator').removeClass('Hidden');
        });

        $(document).ajaxStop(function() {
            $('#LoadingIndicator').addClass('Hidden');
        });
    };

    /**
     * @name InitExportHandlers
     * @memberof Core.Agent.OperationalKPIsReport
     * @function
     * @description
     *      Initializes export link handlers.
     */
    TargetNS.InitExportHandlers = function () {
        // Add confirmation for large exports
        $('a[href*="ExportCSV"], a[href*="ExportExcel"]').on('click', function(event) {
            var Href = $(this).attr('href'),
                ReportType = Core.Agent.OperationalKPIsReport.GetURLParameter(Href, 'ReportType'),
                DateStart = Core.Agent.OperationalKPIsReport.GetURLParameter(Href, 'DateStart'),
                DateEnd = Core.Agent.OperationalKPIsReport.GetURLParameter(Href, 'DateEnd');

            if (DateStart && DateEnd) {
                var DaysDiff = Math.abs(new Date(DateEnd) - new Date(DateStart)) / (1000 * 60 * 60 * 24);

                // Warn for exports with more than 90 days of data
                if (DaysDiff > 90) {
                    if (!confirm(Core.Language.Translate('This export contains a large amount of data and may take several minutes. Continue?'))) {
                        event.preventDefault();
                        return false;
                    }
                }
            }
        });
    };

    /**
     * @name GetURLParameter
     * @memberof Core.Agent.OperationalKPIsReport
     * @function
     * @param {string} url - The URL to parse
     * @param {string} name - The parameter name to extract
     * @description
     *      Extracts a parameter value from a URL.
     */
    TargetNS.GetURLParameter = function (url, name) {
        name = name.replace(/[\[]/, '\\[').replace(/[\]]/, '\\]');
        var regex = new RegExp('[\\?&]' + name + '=([^&#]*)'),
            results = regex.exec(url);
        return results === null ? '' : decodeURIComponent(results[1].replace(/\+/g, ' '));
    };

    /**
     * @name RefreshReport
     * @memberof Core.Agent.OperationalKPIsReport
     * @function
     * @description
     *      Refreshes the current report with updated filters.
     */
    TargetNS.RefreshReport = function () {
        if (Core.Agent.OperationalKPIsReport.ValidateForm()) {
            $('#OperationalKPIsFilterForm').submit();
        }
    };

    return TargetNS;
}(Core.Agent.OperationalKPIsReport || {}));