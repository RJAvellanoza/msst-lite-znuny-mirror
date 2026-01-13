// --
// Copyright (C) 2024 MSSTLite
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (GPL). If you
// did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

Core.Agent.MSSTLiteTicketSearch = (function (TargetNS) {

    TargetNS.Init = function () {
        console.log('MSSTLite: Ticket Search Filter Init');
        
        function fixDropdown() {
            // Target 1: The hidden SELECT element that contains the actual options
            var attributeSelect = document.getElementById('Attribute');
            var attributeOrigSelect = document.getElementById('AttributeOrig');
            
            console.log('MSSTLite: Fixing dropdowns - Found Attribute:', !!attributeSelect, 'AttributeOrig:', !!attributeOrigSelect);
            
            if (attributeSelect) {
                console.log('MSSTLite: Clearing and populating Attribute select...');
                attributeSelect.innerHTML = '';
                
                var options = [
                    { value: '', text: '-' },
                    { value: 'PriorityIDs', text: 'Priority' },
                    { value: 'StateIDs', text: 'State' },
                    { value: 'QueueIDs', text: 'Queue' },
                    { value: 'Title', text: 'Short Description' },
                    { value: '', text: '-' },
                    { value: 'Search_DynamicField_AssignedTo', text: 'Assigned To' },
                    // { value: 'DynamicField_TicketNumber', text: 'Ticket Number' },
                    // { value: 'DynamicField_IncidentSource', text: 'Incident Source' },
                    // { value: 'DynamicField_Priority', text: 'Priority (Dynamic)' },
                    // { value: 'DynamicField_AlarmID', text: 'Alarm ID' },
                    // { value: 'DynamicField_CI', text: 'CI' },
                    // { value: 'DynamicField_CIDeviceType', text: 'CI Device Type' },
                    // { value: 'DynamicField_Description', text: 'Description' },
                    // { value: 'DynamicField_EventID', text: 'Event ID' },
                    // { value: 'DynamicField_EventMessage', text: 'Event Message' },
                    // { value: 'DynamicField_EventSite', text: 'Event Site' }
                ];
                
                options.forEach(function(optionData) {
                    var option = document.createElement('option');
                    option.value = optionData.value;
                    option.textContent = optionData.text;
                    attributeSelect.appendChild(option);
                });
                
                console.log('MSSTLite: ✓ Populated Attribute select with', options.length, 'options');
            }
            
            if (attributeOrigSelect) {
                console.log('MSSTLite: Clearing and populating AttributeOrig select...');
                attributeOrigSelect.innerHTML = '';
                
                var options = [
                    { value: '', text: '-' },
                    { value: 'PriorityIDs', text: 'Priority' },
                    { value: 'StateIDs', text: 'State' },
                    { value: 'QueueIDs', text: 'Assignment Queue' },
                    { value: 'Search_DynamicField_AssignedTo', text: 'Assigned To' },
                    { value: 'Title', text: 'Short Description' }
                ];
                
                options.forEach(function(optionData) {
                    var option = document.createElement('option');
                    option.value = optionData.value;
                    option.textContent = optionData.text;
                    attributeOrigSelect.appendChild(option);
                });
                
                console.log('MSSTLite: ✓ Populated AttributeOrig select with', options.length, 'options');
            }
            
            // Target 2: Also try to find any jstree elements that might contain the options
            var jstreeContainer = document.getElementById('Attribute_Select');
            if (jstreeContainer) {
                console.log('MSSTLite: Found jstree container, clearing it...');
                jstreeContainer.innerHTML = '';
                console.log('MSSTLite: ✓ Cleared jstree container');
            }
        }
        
        // Watch for AJAX navigation to ticket search
        Core.App.Subscribe('Event.App.Responsive.ContentUpdate', function() {
            if (Core.Config.Get('Action') === 'AgentTicketSearch') {
                console.log('MSSTLite: Detected navigation to AgentTicketSearch');
                setTimeout(fixDropdown, 500);
                setTimeout(fixDropdown, 1000);
                setTimeout(fixDropdown, 2000);
            }
        });
        
        // Also hook into AJAX complete
        jQuery(document).on('ajaxComplete', function(event, xhr, settings) {
            if (settings && settings.url && settings.url.indexOf('AgentTicketSearch') !== -1) {
                console.log('MSSTLite: AJAX complete for AgentTicketSearch');
                setTimeout(fixDropdown, 500);
            }
        });
        
        // Run immediately if we're already on the search page
        if (Core.Config.Get('Action') === 'AgentTicketSearch') {
            setTimeout(fixDropdown, 500);
            setTimeout(fixDropdown, 1000);
            setTimeout(fixDropdown, 2000);
        }
        
        // Also watch for DOM changes
        var observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                if (mutation.type === 'childList') {
                    var addedNodes = Array.from(mutation.addedNodes);
                    var hasAttributeSelect = addedNodes.some(function(node) {
                        return node.nodeType === 1 && (
                            node.id === 'Attribute' || 
                            (node.querySelector && node.querySelector('#Attribute'))
                        );
                    });
                    
                    if (hasAttributeSelect) {
                        console.log('MSSTLite: Detected Attribute select via MutationObserver');
                        setTimeout(fixDropdown, 100);
                    }
                }
            });
        });
        
        // Start observing when body is ready
        if (document.body) {
            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
        }
    };

    // Initialize when jQuery is ready
    function waitForJQuery() {
        if (typeof jQuery !== 'undefined' && typeof Core !== 'undefined' && Core.App) {
            jQuery(document).ready(function() {
                TargetNS.Init();
            });
        } else {
            setTimeout(waitForJQuery, 100);
        }
    }
    
    waitForJQuery();

    return TargetNS;
}(Core.Agent.MSSTLiteTicketSearch || {}));