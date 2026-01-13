// --
// Copyright (C) 2025 MSST, https://msst.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};
Core.Agent.EscalationView = Core.Agent.EscalationView || {};

/**
 * @namespace Core.Agent.EscalationView.BulkUpdate
 * @memberof Core.Agent.EscalationView
 * @description
 *      Handles bulk update functionality for eBonded incidents in AgentTicketEscalationView.
 */
Core.Agent.EscalationView.BulkUpdate = (function (TargetNS) {

    /**
     * @private
     * @name MaxTickets
     * @description Maximum number of tickets that can be selected for bulk update
     */
    var MaxTickets = 10;

    /**
     * @private
     * @name CooldownTickets
     * @description Object mapping ticket IDs to their last update timestamp (format: {ticketID: "timestamp"})
     */
    var CooldownTickets = {};

    /**
     * @private
     * @name BulkUpdateButton
     * @description jQuery object for the bulk update button
     */
    var BulkUpdateButton = null;

    /**
     * @private
     * @name OriginalPageURL
     * @description Stores the page URL when bulk update starts (to check if user navigated away)
     */
    var OriginalPageURL = '';

    /**
     * @name Init
     * @memberof Core.Agent.EscalationView.BulkUpdate
     * @function
     * @description
     *      Initialize the bulk update functionality
     */
    TargetNS.Init = function () {
        // Only run on AgentTicketEscalationView page
        if (Core.Config.Get('Action') !== 'AgentTicketEscalationView') {
            return;
        }

        // Wait for DOM to be ready
        $(document).ready(function() {

            // Check if bulk update button exists
            BulkUpdateButton = $('#BulkUpdateButton');
            if (!BulkUpdateButton.length) {
                return;
            }

            // Check if cooldown data container exists
            var $CooldownContainer = $('#BulkUpdateCooldownData');
            if (!$CooldownContainer.length) {
                return;
            }

            // Get cooldown ticket data from hidden data container (now an object: {ticketID: "timestamp"})
            var CooldownData = $CooldownContainer.data('cooldown-tickets');

            if (CooldownData && typeof CooldownData === 'object') {
                CooldownTickets = CooldownData;
            }

            // Check if checkboxes exist
            var $Checkboxes = $('.BulkUpdateCheckbox');

            if ($Checkboxes.length === 0) {
                return;
            }

            // Disable checkboxes for tickets in cooldown
            $.each(CooldownTickets, function(ticketID, updateTime) {
                var $Checkbox = $('.BulkUpdateCheckbox[data-ticket-id="' + ticketID + '"]');
                if ($Checkbox.length) {
                    $Checkbox.prop('disabled', true);
                    $Checkbox.css('opacity', '0.4');
                    $Checkbox.css('cursor', 'not-allowed');

                    // Add tooltip
                    $Checkbox.attr('title', 'Next update could only be triggered after 10 mins for recently updated tickets');

                    // Prevent parent row click from interfering
                    $Checkbox.closest('td').on('click', function(e) {
                        e.stopPropagation();
                    });
                }
            });

            // Bind checkbox change events
            $Checkboxes.on('change', function() {
                TargetNS.OnCheckboxChange();
            });

            // Prevent MasterAction row click when clicking checkbox column
            // Znuny's Core.Agent.Overview.js makes entire row clickable, we need to stop that
            $('.BulkUpdateCheckboxColumn').on('click', function(e) {
                e.stopPropagation();
            });

            // Also prevent on checkbox itself
            $('.BulkUpdateCheckbox').on('click', function(e) {
                e.stopPropagation();
            });

            // Bind bulk update button click event
            BulkUpdateButton.on('click', function() {
                TargetNS.PerformBulkUpdate();
            });

            // Initialize button state (disabled since no tickets selected initially)
            TargetNS.UpdateButtonState();
        });
    };

    /**
     * @name OnCheckboxChange
     * @memberof Core.Agent.EscalationView.BulkUpdate
     * @function
     * @description
     *      Handle checkbox selection change - enforce 10-ticket maximum
     */
    TargetNS.OnCheckboxChange = function () {
        var $CheckedBoxes = $('.BulkUpdateCheckbox:checked');
        var CheckedCount = $CheckedBoxes.length;

        // Enforce maximum selection limit
        if (CheckedCount > MaxTickets) {
            // Uncheck the last checked checkbox
            var $LastChecked = $CheckedBoxes.last();
            $LastChecked.prop('checked', false);

            // Show simple alert (more reliable than ShowAlert dialog)
            alert('Maximum ' + MaxTickets + ' tickets can be selected');

            return;
        }

        // Update button state based on selection count
        TargetNS.UpdateButtonState();
    };

    /**
     * @name UpdateButtonState
     * @memberof Core.Agent.EscalationView.BulkUpdate
     * @function
     * @description
     *      Update bulk update button enabled/disabled state based on selection
     */
    TargetNS.UpdateButtonState = function () {
        var CheckedCount = $('.BulkUpdateCheckbox:checked').length;

        if (CheckedCount === 0) {
            BulkUpdateButton.prop('disabled', true);
        } else {
            BulkUpdateButton.prop('disabled', false);
        }
    };

    /**
     * @name PerformBulkUpdate
     * @memberof Core.Agent.EscalationView.BulkUpdate
     * @function
     * @description
     *      Execute bulk update - send sequential AJAX requests for selected tickets
     */
    TargetNS.PerformBulkUpdate = function () {
        // Get selected ticket IDs
        var SelectedTickets = [];
        $('.BulkUpdateCheckbox:checked').each(function() {
            var TicketID = $(this).data('ticket-id');
            if (TicketID) {
                SelectedTickets.push(TicketID);
            }
        });

        if (SelectedTickets.length === 0) {
            return;
        }

        // Store original page URL to check if user navigates away
        OriginalPageURL = window.location.href;

        // Disable button and change text to "Updating 0/N..."
        var TotalCount = SelectedTickets.length;
        BulkUpdateButton.prop('disabled', true);
        BulkUpdateButton.text('Updating 0/' + TotalCount + '...');

        // Track results with details
        var SuccessResults = [];  // Array of {ticketID, ticketNumber, ticketTitle, message}
        var FailureResults = [];  // Array of {ticketID, ticketNumber, ticketTitle, message}
        var UpdatedCount = 0;

        // Process tickets sequentially with 200ms delay between requests
        var ProcessNextTicket = function(index) {
            if (index >= SelectedTickets.length) {
                // All tickets processed - show detailed summary and reload if still on same page
                TargetNS.ShowDetailedSummary(SuccessResults, FailureResults, TotalCount);
                return;
            }

            var TicketID = SelectedTickets[index];

            // Update button text: "Updating X/N..."
            BulkUpdateButton.text('Updating ' + UpdatedCount + '/' + TotalCount + '...');

            // Send AJAX request
            $.ajax({
                url: Core.Config.Get('Baselink'),
                type: 'POST',
                data: {
                    Action: 'AgentEscalationViewBulkUpdate',
                    TicketID: TicketID
                },
                dataType: 'json',
                success: function(Response) {
                    UpdatedCount++;

                    if (Response && Response.success) {
                        SuccessResults.push({
                            ticketID: Response.ticketID || TicketID,
                            ticketNumber: Response.ticketNumber || 'Unknown',
                            ticketTitle: Response.ticketTitle || '',
                            message: Response.message || 'Updated successfully'
                        });
                    } else {
                        FailureResults.push({
                            ticketID: Response.ticketID || TicketID,
                            ticketNumber: Response.ticketNumber || 'Unknown',
                            ticketTitle: Response.ticketTitle || '',
                            message: Response.message || 'Update failed'
                        });
                    }

                    // Wait 200ms AFTER response, BEFORE next request (except for last one)
                    if (index < SelectedTickets.length - 1) {
                        setTimeout(function() {
                            ProcessNextTicket(index + 1);
                        }, 200);
                    } else {
                        // Last ticket - no delay needed
                        ProcessNextTicket(index + 1);
                    }
                },
                error: function(jqXHR, textStatus, errorThrown) {
                    UpdatedCount++;
                    FailureResults.push({
                        ticketID: TicketID,
                        ticketNumber: 'Unknown',
                        ticketTitle: '',
                        message: 'Network error: ' + textStatus
                    });

                    // Wait 200ms before next request (or complete if last)
                    if (index < SelectedTickets.length - 1) {
                        setTimeout(function() {
                            ProcessNextTicket(index + 1);
                        }, 200);
                    } else {
                        ProcessNextTicket(index + 1);
                    }
                }
            });
        };

        // Start processing first ticket (no initial delay)
        ProcessNextTicket(0);
    };

    /**
     * @name ShowDetailedSummary
     * @memberof Core.Agent.EscalationView.BulkUpdate
     * @function
     * @param {Array} SuccessResults - Array of successful updates with ticket details
     * @param {Array} FailureResults - Array of failed updates with ticket details
     * @param {Number} TotalCount - Total number of tickets processed
     * @description
     *      Show detailed completion summary with list of successes and failures, and offer unlink option
     */
    TargetNS.ShowDetailedSummary = function (SuccessResults, FailureResults, TotalCount) {
        var SuccessCount = SuccessResults.length;
        var FailureCount = FailureResults.length;

        // Build text summary
        var SummaryText = '';

        // Summary header
        if (FailureCount === 0) {
            SummaryText += 'All ' + SuccessCount + ' tickets updated successfully!\n\n';
        } else if (SuccessCount === 0) {
            SummaryText += 'All ' + FailureCount + ' ticket updates failed.\n\n';
        } else {
            SummaryText += SuccessCount + ' of ' + TotalCount + ' tickets updated successfully. ' + FailureCount + ' failed.\n\n';
        }

        // Show successful tickets
        if (SuccessCount > 0) {
            SummaryText += '✓ Successfully Updated:\n';
            SuccessResults.forEach(function(result) {
                var titleText = result.ticketTitle ? ' - ' + result.ticketTitle : '';
                SummaryText += '  • ' + result.ticketNumber + titleText + '\n';
            });
            SummaryText += '\n';
        }

        // Show failed tickets
        if (FailureCount > 0) {
            SummaryText += '✗ Failed Updates:\n';
            FailureResults.forEach(function(result) {
                var titleText = result.ticketTitle ? ' - ' + result.ticketTitle : '';
                var errorText = result.message ? ' (' + result.message + ')' : '';
                SummaryText += '  • ' + result.ticketNumber + titleText + errorText + '\n';
            });
        }

        // Show alert with summary
        alert(SummaryText);

        // Reload page after summary (do not offer unlink option for failed tickets)
        TargetNS.ReloadPageIfNeeded();
    };

    /**
     * @name ReloadPageIfNeeded
     * @memberof Core.Agent.EscalationView.BulkUpdate
     * @function
     * @description
     *      Reload page if user is still on AgentTicketEscalationView
     */
    TargetNS.ReloadPageIfNeeded = function () {
        var CurrentURL = window.location.href;

        // Check if URL still contains Action=AgentTicketEscalationView
        if (CurrentURL.indexOf('Action=AgentTicketEscalationView') !== -1 &&
            CurrentURL === OriginalPageURL) {
            // User is still on same page - reload to refresh data
            window.location.reload();
        } else {
            // User navigated away - just reset button
            BulkUpdateButton.text('Bulk Update');
            BulkUpdateButton.prop('disabled', false);
        }
    };

    /**
     * @name UnlinkFailedTickets
     * @memberof Core.Agent.EscalationView.BulkUpdate
     * @function
     * @param {Array} FailureResults - Array of failed ticket results
     * @description
     *      Unlink failed tickets from ServiceNow by clearing MSI dynamic fields
     */
    TargetNS.UnlinkFailedTickets = function (FailureResults) {
        // Extract ticket IDs
        var TicketIDs = FailureResults.map(function(result) {
            return result.ticketID;
        });

        // Disable button and show progress
        BulkUpdateButton.text('Unlinking tickets...');
        BulkUpdateButton.prop('disabled', true);

        // Send AJAX request to unlink tickets
        $.ajax({
            url: Core.Config.Get('Baselink'),
            type: 'POST',
            data: {
                Action: 'AgentEscalationViewUnlinkTickets',
                TicketIDs: TicketIDs.join(',')
            },
            dataType: 'json',
            success: function(Response) {
                if (Response && Response.success) {
                    alert('Successfully unlinked ' + Response.unlinkedCount + ' tickets from ServiceNow.\n\nThe page will now reload.');
                    window.location.reload();
                } else {
                    alert('Error unlinking tickets: ' + (Response.message || 'Unknown error'));
                    BulkUpdateButton.text('Bulk Update');
                    BulkUpdateButton.prop('disabled', false);
                }
            },
            error: function(jqXHR, textStatus) {
                alert('Network error while unlinking tickets: ' + textStatus);
                BulkUpdateButton.text('Bulk Update');
                BulkUpdateButton.prop('disabled', false);
            }
        });
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;

}(Core.Agent.EscalationView.BulkUpdate || {}));
