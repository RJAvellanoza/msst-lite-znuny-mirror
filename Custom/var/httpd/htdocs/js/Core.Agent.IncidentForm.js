"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace Core.Agent.IncidentForm
 * @memberof Core.Agent
 * @author MSST Solutions
 * @description
 *      This namespace contains the special functions for Incident form handling.
 */
Core.Agent.IncidentForm = (function (TargetNS) {

    /**
     * @name DisableHTML5ValidationTooltips
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Disables HTML5 validation tooltips while keeping validation logic.
     */
    TargetNS.DisableHTML5ValidationTooltips = function () {
        // Add novalidate to the incident form to prevent browser tooltips
        $('#IncidentForm').attr('novalidate', 'novalidate');
        
        // Remove HTML5 required attributes but keep Validate_Required class
        $('#IncidentForm').find('input[required], select[required], textarea[required]').each(function() {
            $(this).removeAttr('required');
        });
        
        // For all elements with Validate_Required class, ensure no required attribute
        $('#IncidentForm').find('.Validate_Required').each(function() {
            $(this).removeAttr('required');
        });
        
        // Handle dynamically added content
        var observer = new MutationObserver(function(mutations) {
            $('#IncidentForm').attr('novalidate', 'novalidate');
            $('#IncidentForm').find('input[required], select[required], textarea[required]').removeAttr('required');
            $('#IncidentForm').find('.Validate_Required').removeAttr('required');
        });
        
        // Start observing the form for changes
        if ($('#IncidentForm').length) {
            observer.observe($('#IncidentForm')[0], {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['required']
            });
        }
        
        // Prevent the browser's default validation UI
        $('#IncidentForm').on('invalid', 'input, select, textarea', function(e) {
            e.preventDefault();
            return false;
        });
    };

    /**
     * @name Init
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes the incident form functionality.
     */
    TargetNS.Init = function () {
        // Disable HTML5 validation tooltips
        TargetNS.DisableHTML5ValidationTooltips();
        
        // Initialize form validation if available
        if (typeof Core.Form !== 'undefined' && typeof Core.Form.Validate !== 'undefined') {
            Core.Form.Validate.Init();
        }
        
        // Initialize RichTextEditor with minimal toolbar
        if (typeof Core.UI.RichTextEditor !== 'undefined') {
            Core.Config.Set('RichText.Toolbar', [
                ['Bold', 'Italic', 'Underline', 'Strike', '-', 'RemoveFormat'],
                ['NumberedList', 'BulletedList'],
                ['Link', 'Unlink'],
                ['Undo', 'Redo'],
                ['Source']
            ]);
            Core.UI.RichTextEditor.Init();
        }
        
        // Initialize tab switching
        TargetNS.InitTabs();
        
        // Initialize category cascades
        TargetNS.InitCategoryCascades();
        
        // Initialize state validation
        TargetNS.InitStateValidation();
        
        // Initialize auto-save functionality
        TargetNS.InitAutoSave();
        
        // Initialize form submission handling
        TargetNS.InitFormSubmission();
        
        // Initialize field formatting
        TargetNS.InitFieldFormatting();
        
        // Initialize work notes functionality
        TargetNS.InitWorkNotes();
        TargetNS.InitResolutionNotes();

        // Initialize Easy MSI Escalation submission
        TargetNS.InitEBondingSubmission();

        // Initialize modernized fields
        $('.Modernize').each(function() {
            Core.UI.InputFields.Init($(this));
        });
    };

    /**
     * @name InitTabs
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes tab switching functionality.
     */
    TargetNS.InitTabs = function () {
        var $TabNavigation = $('.TabNavigation'),
            $TabContent = $('.TabContent');

        if (!$TabNavigation.length) {
            return;
        }

        // Handle tab clicks
        $TabNavigation.on('click', 'li a', function (Event) {
            var $Link = $(this),
                $Tab = $Link.parent('li'),
                TabID = $Link.attr('href').replace('#', '');

            Event.preventDefault();

            // Don't do anything if tab is already active
            if ($Tab.hasClass('Active')) {
                return;
            }

            // Update active tab
            $TabNavigation.find('li').removeClass('Active');
            $Tab.addClass('Active');

            // Show corresponding content
            $TabContent.addClass('Hidden');
            $('#' + TabID).removeClass('Hidden');

            // Save active tab to local storage
            if (typeof(Storage) !== "undefined") {
                localStorage.setItem('IncidentFormActiveTab', TabID);
            }
        });

        // Restore last active tab from local storage
        if (typeof(Storage) !== "undefined") {
            var LastActiveTab = localStorage.getItem('IncidentFormActiveTab');
            if (LastActiveTab && $('#' + LastActiveTab).length) {
                $TabNavigation.find('a[href="#' + LastActiveTab + '"]').click();
            }
        }
    };

    /**
     * @name InitCategoryCascades
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes category cascade functionality.
     */
    TargetNS.InitCategoryCascades = function () {
        // Initialize Product Category cascades
        TargetNS.InitProductCategories();
        
        // Initialize Operational Category cascades  
        TargetNS.InitOperationalCategories();
        
        // Initialize Resolution Category cascades
        TargetNS.InitResolutionCategories();
    };

    /**
     * @name InitProductCategories
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes product category cascade functionality.
     */
    TargetNS.InitProductCategories = function () {
        var $ProductCat1 = $('#ProductCat1'),
            $ProductCat2 = $('#ProductCat2'),
            $ProductCat3 = $('#ProductCat3'),
            $ProductCat4 = $('#ProductCat4');

        if (!$ProductCat1.length) {
            return;
        }

        // Don't load categories on init - they're already loaded by the server-side template
        
        // Initialize child dropdowns to proper disabled state
        TargetNS.InitializeCategoryState($ProductCat1, $ProductCat2, $ProductCat3, $ProductCat4);

        // Handle ProductCat1 change
        $ProductCat1.on('change', function () {
            var SelectedID = $(this).val();
            
            // Clear and disable dependent dropdowns properly
            TargetNS.ClearCategoryDropdown($ProductCat2);
            TargetNS.ClearCategoryDropdown($ProductCat3);
            TargetNS.ClearCategoryDropdown($ProductCat4);
            
            if (SelectedID) {
                // Enable ProductCat2 and load categories
                TargetNS.EnableCategoryDropdown($ProductCat2);
                TargetNS.LoadProductCategories(2, {Tier1: SelectedID}, $ProductCat2);
            }
        });

        // Handle ProductCat2 change
        $ProductCat2.on('change', function () {
            var SelectedID = $(this).val();
            
            // Clear dependent dropdowns
            TargetNS.ClearCategoryDropdown($ProductCat3);
            TargetNS.ClearCategoryDropdown($ProductCat4);
            
            if (SelectedID) {
                // Enable ProductCat3 and load categories
                TargetNS.EnableCategoryDropdown($ProductCat3);
                TargetNS.LoadProductCategories(3, {
                    Tier1: $ProductCat1.val(),
                    Tier2: SelectedID
                }, $ProductCat3);
            } else {
                // Clear child categories when parent is cleared
                TargetNS.ClearCategoryDropdown($ProductCat3);
            }
        });

        // Handle ProductCat3 change
        $ProductCat3.on('change', function () {
            var SelectedID = $(this).val();
            
            // Clear dependent dropdown
            TargetNS.ClearCategoryDropdown($ProductCat4);
            
            if (SelectedID) {
                // Enable ProductCat4 and load categories
                TargetNS.EnableCategoryDropdown($ProductCat4);
                TargetNS.LoadProductCategories(4, {
                    Tier1: $ProductCat1.val(),
                    Tier2: $ProductCat2.val(),
                    Tier3: SelectedID
                }, $ProductCat4);
            } else {
                // Clear child category when parent is cleared
                TargetNS.ClearCategoryDropdown($ProductCat4);
            }
        });
    };

    /**
     * @name InitOperationalCategories
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes operational category cascade functionality.
     */
    TargetNS.InitOperationalCategories = function () {
        var $OperationalCat1 = $('#OperationalCat1'),
            $OperationalCat2 = $('#OperationalCat2'),
            $OperationalCat3 = $('#OperationalCat3');

        if (!$OperationalCat1.length) {
            return;
        }

        // Don't load categories on init - they're already loaded by the server-side template
        
        // Initialize child dropdowns to proper disabled state
        TargetNS.InitializeCategoryState($OperationalCat1, $OperationalCat2, $OperationalCat3);

        // Handle OperationalCat1 change
        $OperationalCat1.on('change', function () {
            var SelectedID = $(this).val();
            
            // Clear and disable dependent dropdowns properly
            TargetNS.ClearCategoryDropdown($OperationalCat2);
            TargetNS.ClearCategoryDropdown($OperationalCat3);
            
            if (SelectedID) {
                // Enable OperationalCat2 and load categories
                TargetNS.EnableCategoryDropdown($OperationalCat2);
                TargetNS.LoadOperationalCategories(2, {Tier1: SelectedID}, $OperationalCat2);
            } else {
                // Keep child categories enabled even when parent is cleared
                // Users can select categories in any order
            }
        });

        // Handle OperationalCat2 change
        $OperationalCat2.on('change', function () {
            var SelectedID = $(this).val();
            
            // Clear dependent dropdown
            TargetNS.ClearCategoryDropdown($OperationalCat3);
            
            if (SelectedID) {
                // Enable OperationalCat3 and load categories
                TargetNS.EnableCategoryDropdown($OperationalCat3);
                TargetNS.LoadOperationalCategories(3, {
                    Tier1: $OperationalCat1.val(),
                    Tier2: SelectedID
                }, $OperationalCat3);
            } else {
                // Keep child category enabled even when parent is cleared
                // Users can select categories in any order
            }
        });
    };

    /**
     * @name InitResolutionCategories
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes resolution category cascade functionality.
     */
    TargetNS.InitResolutionCategories = function () {
        var $ResolutionCat1 = $('#ResolutionCat1'),
            $ResolutionCat2 = $('#ResolutionCat2'),
            $ResolutionCat3 = $('#ResolutionCat3');

        if (!$ResolutionCat1.length) {
            return;
        }

        // Initialize child dropdowns to proper disabled state
        TargetNS.InitializeCategoryState($ResolutionCat1, $ResolutionCat2, $ResolutionCat3);

        // Handle ResolutionCat1 change
        $ResolutionCat1.on('change', function () {
            var SelectedID = $(this).val();
            
            // Clear and disable dependent dropdowns properly
            TargetNS.ClearCategoryDropdown($ResolutionCat2);
            TargetNS.ClearCategoryDropdown($ResolutionCat3);
            
            if (SelectedID) {
                // Enable ResolutionCat2 and load categories
                TargetNS.EnableCategoryDropdown($ResolutionCat2);
                TargetNS.LoadResolutionCategories(2, {Tier1: SelectedID}, $ResolutionCat2);
            } else {
                // Keep child categories enabled even when parent is cleared
                // Users can select categories in any order
            }
        });

        // Handle ResolutionCat2 change
        $ResolutionCat2.on('change', function () {
            var SelectedID = $(this).val();
            
            // Clear dependent dropdown
            TargetNS.ClearCategoryDropdown($ResolutionCat3);
            
            if (SelectedID) {
                // Enable ResolutionCat3 and load categories
                TargetNS.EnableCategoryDropdown($ResolutionCat3);
                TargetNS.LoadResolutionCategories(3, {
                    Tier1: $ResolutionCat1.val(),
                    Tier2: SelectedID
                }, $ResolutionCat3);
            } else {
                // Keep child category enabled even when parent is cleared
                // Users can select categories in any order
            }
        });
    };

    /**
     * @name InitializeCategoryState
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {...jQueryObject} $Elements - Category elements in hierarchy order
     * @description
     *      Initializes category dropdown states - now keeps all dropdowns enabled.
     */
    TargetNS.InitializeCategoryState = function () {
        var $Elements = Array.prototype.slice.call(arguments);
        
        // Enable all category dropdowns - users can select in any order
        for (var i = 0; i < $Elements.length; i++) {
            var $Current = $Elements[i];
            if (!$Current || !$Current.length) continue;
            
            // Make sure all dropdowns are enabled
            TargetNS.EnableCategoryDropdown($Current);
        }
    };

    /**
     * @name ClearCategoryDropdown
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {jQueryObject} $Element - Select element to clear
     * @description
     *      Properly clears a category dropdown and refreshes select2 display.
     */
    TargetNS.ClearCategoryDropdown = function ($Element) {
        if (!$Element || !$Element.length) {
            return;
        }
        
        // Clear the dropdown and add default option
        $Element.empty().append('<option value="">-</option>');
        
        // Set value to empty
        $Element.val('');
        
        // For modernized fields, reinitialize the UI
        if ($Element.hasClass('Modernize') && typeof Core.UI.InputFields !== 'undefined') {
            Core.UI.InputFields.Init($Element);
        }
        
        // Trigger change event
        $Element.trigger('change');
    };

    /**
     * @name DisableCategoryDropdown
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {jQueryObject} $Element - Select element to disable
     * @description
     *      Properly disables a category dropdown and updates modernized UI.
     */
    TargetNS.DisableCategoryDropdown = function ($Element) {
        if (!$Element || !$Element.length) {
            return;
        }
        
        // Disable the element
        $Element.prop('disabled', true);
        
        // Update modernized UI if available
        var $Container = $Element.closest('.InputField_Container');
        if ($Container.length) {
            var $SearchInput = $Container.find('.InputField_Search');
            if ($SearchInput.length) {
                $SearchInput.prop('readonly', true).attr('title', 'Please select a parent category first');
            }
        }
    };

    /**
     * @name EnableCategoryDropdown
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {jQueryObject} $Element - Select element to enable
     * @description
     *      Properly enables a category dropdown and updates modernized UI.
     */
    TargetNS.EnableCategoryDropdown = function ($Element) {
        if (!$Element || !$Element.length) {
            return;
        }
        
        // Enable the element
        $Element.prop('disabled', false);
        
        // For modernized fields, we need to update the UI container
        if ($Element.hasClass('Modernize')) {
            var $Container = $Element.closest('.Field');
            $Container.removeClass('Disabled');
            
            // Find the search input and enable it too
            var $SearchInput = $('#' + $Element.attr('id') + '_Search');
            if ($SearchInput.length) {
                $SearchInput.prop('disabled', false).prop('readonly', false);
            }
        }
    };

    /**
     * @name LoadProductCategories
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {Number} Tier - Category tier (1, 2, 3, or 4)
     * @param {Object} Parents - Parent category names (Tier1, Tier2, Tier3)
     * @param {jQueryObject} $TargetElement - Target select element
     * @description
     *      Loads product categories via AJAX with proper hierarchy.
     */
    TargetNS.LoadProductCategories = function (Tier, Parents, $TargetElement) {
        var Data = {
            Action: 'AgentIncidentForm',
            Subaction: 'LoadCategories',
            Type: 'Product',
            Tier: Tier
        };
        
        // Add parent parameters
        if (Parents.Tier1) Data.Tier1 = Parents.Tier1;
        if (Parents.Tier2) Data.Tier2 = Parents.Tier2;
        if (Parents.Tier3) Data.Tier3 = Parents.Tier3;

        // Handle modernized dropdowns - find search input for loading indicator
        var $SearchInput = $('#' + $TargetElement.attr('id') + '_Search');
        
        // Show loading indicator
        $TargetElement.prop('disabled', true);
        $SearchInput.prop('readonly', true).val('Loading...');

        $.ajax({
            url: Core.Config.Get('Baselink'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                var Categories = Response.Categories || [];
                
                // Handle modernized dropdowns
                var $ActualSelect = $TargetElement;
                var $SearchInput = $('#' + $TargetElement.attr('id') + '_Search');
                
                // Update the actual select element
                $ActualSelect.empty().append('<option value="">-</option>');
                
                $.each(Categories, function(Index, Category) {
                    $ActualSelect.append(
                        $('<option></option>').val(Category.ID).text(Category.Name)
                    );
                });
                
                // Re-enable elements
                $ActualSelect.prop('disabled', false).prop('readonly', false);
                $SearchInput.prop('readonly', false).removeAttr('title').val('');
                
                // Force modernized UI to refresh
                if (typeof Core.UI.InputFields !== 'undefined') {
                    Core.UI.InputFields.Init($ActualSelect);
                }
                
                // Trigger update events
                $ActualSelect.trigger('change');
            },
            error: function () {
                Core.UI.ShowNotification(Core.Language.Translate('Failed to load categories for Tier: ') + Tier, 'Error');
                var $SearchInput = $('#' + $TargetElement.attr('id') + '_Search');
                $TargetElement.prop('disabled', false).prop('readonly', false);
                $SearchInput.prop('readonly', false).removeAttr('title').val('');
            }
        });
    };

    /**
     * @name LoadOperationalCategories
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {Number} Tier - Category tier (1, 2, or 3)
     * @param {Object} Parents - Parent category names (Tier1, Tier2)
     * @param {jQueryObject} $TargetElement - Target select element
     * @description
     *      Loads operational categories via AJAX with proper hierarchy.
     */
    TargetNS.LoadOperationalCategories = function (Tier, Parents, $TargetElement) {
        var Data = {
            Action: 'AgentIncidentForm',
            Subaction: 'LoadCategories',
            Type: 'operational',
            Tier: Tier
        };
        
        // Add parent parameters
        if (Parents.Tier1) Data.Tier1 = Parents.Tier1;
        if (Parents.Tier2) Data.Tier2 = Parents.Tier2;

        // Handle modernized dropdowns - find the actual select element and search input
        var $ActualSelect = $TargetElement;
        var $SearchInput = $('#' + $TargetElement.attr('id') + '_Search');

        // Show loading indicator on both elements
        $ActualSelect.prop('disabled', true);
        $SearchInput.prop('readonly', true).val('Loading...');

        $.ajax({
            url: Core.Config.Get('Baselink'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                var Categories = Response.Categories || [];
                
                // Update the actual select element
                $ActualSelect.empty().append('<option value="">-</option>');
                
                $.each(Categories, function(Index, Category) {
                    $ActualSelect.append(
                        $('<option></option>').val(Category.ID).text(Category.Name)
                    );
                });
                
                // Re-enable elements
                $ActualSelect.prop('disabled', false).prop('readonly', false);
                $SearchInput.prop('readonly', false).removeAttr('title').val('');
                
                // Force modernized UI to refresh
                if (typeof Core.UI.InputFields !== 'undefined') {
                    // Reinitialize the modernized field to reflect new options
                    Core.UI.InputFields.Init($ActualSelect);
                }
                
                // Trigger update events
                $ActualSelect.trigger('change');
            },
            error: function (xhr, status, error) {
                Core.UI.ShowNotification(Core.Language.Translate('Failed to load operational categories for Tier: ') + Tier, 'Error');
                $ActualSelect.prop('disabled', false).prop('readonly', false);
                $SearchInput.prop('readonly', false).removeAttr('title').val('');
            }
        });
    };

    /**
     * @name LoadResolutionCategories
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {Number} Tier - Category tier (1, 2, or 3)
     * @param {Object} Parents - Parent category names (Tier1, Tier2)
     * @param {jQueryObject} $TargetElement - Target select element
     * @description
     *      Loads resolution categories via AJAX with proper hierarchy.
     */
    TargetNS.LoadResolutionCategories = function (Tier, Parents, $TargetElement) {
        var Data = {
            Action: 'AgentIncidentForm',
            Subaction: 'LoadCategories',
            Type: 'resolution',
            Tier: Tier
        };
        
        // Add parent parameters
        if (Parents.Tier1) Data.Tier1 = Parents.Tier1;
        if (Parents.Tier2) Data.Tier2 = Parents.Tier2;

        // Handle modernized dropdowns - find the actual select element and search input
        var $ActualSelect = $TargetElement;
        var $SearchInput = $('#' + $TargetElement.attr('id') + '_Search');

        // Show loading indicator on both elements
        $ActualSelect.prop('disabled', true);
        $SearchInput.prop('readonly', true).val('Loading...');

        $.ajax({
            url: Core.Config.Get('Baselink'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                var Categories = Response.Categories || [];
                
                // Update the actual select element
                $ActualSelect.empty().append('<option value="">-</option>');
                
                $.each(Categories, function(Index, Category) {
                    $ActualSelect.append(
                        $('<option></option>').val(Category.ID).text(Category.Name)
                    );
                });
                
                // Re-enable elements
                $ActualSelect.prop('disabled', false).prop('readonly', false);
                $SearchInput.prop('readonly', false).removeAttr('title').val('');
                
                // Force modernized UI to refresh
                if (typeof Core.UI.InputFields !== 'undefined') {
                    Core.UI.InputFields.Init($ActualSelect);
                }
                
                // Trigger update events
                $ActualSelect.trigger('change');
            },
            error: function (xhr, status, error) {
                Core.UI.ShowNotification(Core.Language.Translate('Failed to load resolution categories for Tier: ') + Tier, 'Error');
                $ActualSelect.prop('disabled', false).prop('readonly', false);
                $SearchInput.prop('readonly', false).removeAttr('title').val('');
            }
        });
    };

    /**
     * @name UpdateCategoryDropdown
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {String} Type - Category type ('Product', 'Operational', 'Resolution')
     * @param {Number} Level - Category level (2, 3, or 4)
     * @param {String} Tier1Value - First tier value
     * @param {String} Tier2Value - Second tier value (optional)
     * @param {String} Tier3Value - Third tier value (optional)
     * @description
     *      Updates category dropdown - compatibility function for template.
     */
    TargetNS.UpdateCategoryDropdown = function (Type, Level, Tier1Value, Tier2Value, Tier3Value) {
        var $TargetElement;
        var Parents = {};
        
        // Map to target element
        if (Type === 'Product') {
            $TargetElement = $('#ProductCat' + Level);
            if (Tier1Value) Parents.Tier1 = Tier1Value;
            if (Tier2Value) Parents.Tier2 = Tier2Value;
            if (Tier3Value) Parents.Tier3 = Tier3Value;
            
            TargetNS.LoadProductCategories(Level, Parents, $TargetElement);
        } else if (Type === 'Operational') {
            $TargetElement = $('#OperationalCat' + Level);
            if (Tier1Value) Parents.Tier1 = Tier1Value;
            if (Tier2Value) Parents.Tier2 = Tier2Value;
            
            TargetNS.LoadOperationalCategories(Level, Parents, $TargetElement);
        } else if (Type === 'Resolution') {
            $TargetElement = $('#ResolutionCat' + Level);
            if (Tier1Value) Parents.Tier1 = Tier1Value;
            if (Tier2Value) Parents.Tier2 = Tier2Value;
            
            TargetNS.LoadResolutionCategories(Level, Parents, $TargetElement);
        }
        
        // Clear dependent dropdowns
        if (Type === 'Product') {
            for (var i = Level + 1; i <= 4; i++) {
                $('#ProductCat' + i).empty().append('<option value="">-</option>');
            }
        } else if (Type === 'Operational' && Level === 2) {
            $('#OperationalCat3').empty().append('<option value="">-</option>');
        } else if (Type === 'Resolution' && Level === 2) {
            $('#ResolutionCat3').empty().append('<option value="">-</option>');
        }
    };

    /**
     * @name LoadCategories
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {String} Type - Category type ('Product' or 'Operational')
     * @param {Number} Level - Category level (1, 2, 3, or 4)
     * @param {Number} ParentID - Parent category ID
     * @param {jQueryObject} $TargetElement - Target select element
     * @description
     *      Loads categories via AJAX.
     */
    TargetNS.LoadCategories = function (Type, Level, ParentID, $TargetElement) {
        var Data = {
            Action: 'AgentIncidentForm',
            Subaction: 'LoadCategories',
            Type: Type,
            Level: Level,
            ParentID: ParentID || 0
        };

        // Show loading indicator
        $TargetElement.prop('disabled', true);

        $.ajax({
            url: Core.Config.Get('Baselink'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
            var Categories = Response.Categories || [];
            
            $TargetElement.empty().append('<option value="">-</option>');
            
            $.each(Categories, function(Index, Category) {
                $TargetElement.append(
                    $('<option></option>').val(Category.ID).text(Category.Name)
                );
            });
            
            $TargetElement.prop('disabled', false);
            
            // Trigger change event if there's only one option (plus empty option)
            if ($TargetElement.find('option').length === 2) {
                $TargetElement.find('option:last').prop('selected', true).trigger('change');
            }
        },
        error: function () {
            Core.UI.ShowNotification(Core.Language.Translate('Failed to load categories for Type: ') + Type + ', Level: ' + Level, 'Error');
            $TargetElement.prop('disabled', false);
        }
    });
    };

    /**
     * @name InitStateValidation
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes state transition validation.
     */
    TargetNS.InitStateValidation = function () {
        var $StateID = $('#State'),
            $Form = $('#IncidentForm'),
            OriginalState = $StateID.find('option:selected').text().toLowerCase();

        if (!$StateID.length) {
            return;
        }

        // Store original state (already lowercase from line 808)
        $StateID.data('original-state', OriginalState);
        // Store the saved state separately (this is the state from the database)
        $StateID.data('saved-state', OriginalState);

        // Initialize assignee validation for current state
        TargetNS.ValidateAssigneeForState(OriginalState);

        // Update state dropdown to show/hide 'closed' option based on current state
        TargetNS.UpdateStateDropdown(OriginalState);

        // Validate state changes
        $StateID.on('change', function () {
            var NewState = $(this).find('option:selected').text().toLowerCase(),
                SavedState = $(this).data('saved-state'); // Use saved state for restrictions

            // State transition validation disabled
            // if (!TargetNS.IsValidStateTransition(CurrentState, NewState)) {
            //     alert(Core.Language.Translate('Invalid state transition. Please select a valid state.'));
            //     $(this).val(CurrentState);
            //     return false;
            // }

            // Validate assignee requirement for specific states
            TargetNS.ValidateAssigneeForState(NewState);

            // Update state dropdown based on SAVED state, not the new selection
            // This prevents the dropdown from being restricted when user selects cancelled
            TargetNS.UpdateStateDropdown(SavedState);

            // Update current selection tracking (but not saved state)
            $(this).data('original-state', NewState.toLowerCase());

            // Note: Validation for closing states is handled during form submission, not state change
        });
    };

    /**
     * @name ValidateAssigneeForState
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {String} StateValue - Target state value
     * @description
     *      Validates that an assignee is selected for states that require one.
     */
    TargetNS.ValidateAssigneeForState = function (StateValue) {
        var $AssignedTo = $('#AssignedTo'),
            $AssignedToLabel = $('label[for="AssignedTo"]'),
            // States that require an assigned user
            StatesRequiringAssignee = ['assigned', 'in progress', 'pending', 'resolved'];


        if (!StateValue || !$AssignedTo.length) {
            return;
        }

        // Use the state value directly for comparison (case insensitive)
        var StateValueLower = StateValue.toLowerCase();

        // Check if this state requires an assignee
        var RequiresAssignee = false;
        for (var i = 0; i < StatesRequiringAssignee.length; i++) {
            if (StateValueLower.indexOf(StatesRequiringAssignee[i]) !== -1) {
                RequiresAssignee = true;
                break;
            }
        }

        if (RequiresAssignee) {
            // Make AssignedTo field required
            $AssignedTo.addClass('Validate_Required');
            
            // Always update the label to ensure correct marker state
            if ($AssignedToLabel.length) {
                // Force update by setting text content directly
                $AssignedToLabel.empty().append('<span class="Marker">*</span> ' + Core.Language.Translate('Assigned To') + ':');
            }
        } else {
            // Remove required validation
            $AssignedTo.removeClass('Validate_Required Error');
            
            // Remove required marker from label
            if ($AssignedToLabel.length) {
                // Force update by setting text content directly
                $AssignedToLabel.empty().append(Core.Language.Translate('Assigned To') + ':');
            }
        }
        
        // Re-initialize form validation to pick up changes
        if (typeof Core.Form !== 'undefined' && typeof Core.Form.Init === 'function') {
            Core.Form.Init();
        }
        
        // Fix: Re-apply the marker and validation after form initialization
        setTimeout(function() {
            if (RequiresAssignee) {
                // Re-add the validation class
                $AssignedTo.addClass('Validate_Required');
                // Re-add the marker
                if ($AssignedToLabel.length) {
                    $AssignedToLabel.empty().append('<span class="Marker">*</span> ' + Core.Language.Translate('Assigned To') + ':');
                }
            }
        }, 0);
    };

    /**
     * @name UpdateStateDropdown
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {String} CurrentState - Current state value
     * @description
     *      Updates the state dropdown based on current state restrictions.
     */
    TargetNS.UpdateStateDropdown = function (CurrentState) {
        var $StateDropdown = $('#State'),
            $Form = $('#IncidentForm'),
            IsCreate = !$Form.find('input[name="IncidentID"]').val() && !$Form.find('input[name="IncidentNumber"]').val();
        
        // Normalize state to lowercase for comparison
        if (CurrentState) {
            CurrentState = CurrentState.toLowerCase();
        }
        
        if (!$StateDropdown.length || IsCreate) {
            console.log('Returning early - no dropdown or in create mode');
            return;
        }

        // Store current selection (get the text, not the value)
        var SelectedText = $StateDropdown.find('option:selected').text().toLowerCase();
        
        // Define state options based on current state
        var StateOptions = [];
        
        // Convert CurrentState to lowercase for comparison
        var CurrentStateLower = CurrentState ? CurrentState.toLowerCase() : '';
        
        if (CurrentStateLower === 'new') {
            // When in 'new' state, don't allow pending or resolved transitions
            StateOptions = [
                {value: 'new', text: 'New'},
                {value: 'assigned', text: 'Assigned'},
                {value: 'in progress', text: 'In Progress'},
                {value: 'cancelled', text: 'Cancelled'}
            ];
        }
        else if (CurrentStateLower === 'assigned') {
            // When in 'assigned' state, only allow these transitions
            StateOptions = [
                {value: 'assigned', text: 'Assigned'},
                {value: 'in progress', text: 'In Progress'},
                {value: 'cancelled', text: 'Cancelled'}
            ];
        }
        else if (CurrentStateLower === 'in progress') {
            // When in 'in progress' state, only allow these transitions
            StateOptions = [
                {value: 'assigned', text: 'Assigned'},
                {value: 'in progress', text: 'In Progress'},
                {value: 'pending', text: 'Pending'},
                {value: 'resolved', text: 'Resolved'},
                {value: 'cancelled', text: 'Cancelled'}
            ];
        }
        else if (CurrentStateLower === 'pending') {
            // When in 'pending' state, allow going back to in progress or forward to resolved
            StateOptions = [
                {value: 'in progress', text: 'In Progress'},
                {value: 'pending', text: 'Pending'},
                {value: 'resolved', text: 'Resolved'},
                {value: 'cancelled', text: 'Cancelled'}
            ];
        }
        else if (CurrentStateLower === 'resolved') {
            // When in 'resolved' state, allow these transitions
            StateOptions = [
                {value: 'assigned', text: 'Assigned'},
                {value: 'in progress', text: 'In Progress'},
                {value: 'pending', text: 'Pending'},
                {value: 'resolved', text: 'Resolved'},
                {value: 'closed', text: 'Closed'},
                {value: 'cancelled', text: 'Cancelled'}
            ];
        }
        else if (CurrentStateLower === 'closed' || CurrentStateLower === 'closed successful') {
            // When in 'closed' state, form should be read-only but show current state
            StateOptions = [
                {value: 'closed', text: 'Closed'}
            ];
        }
        else if (CurrentStateLower === 'cancelled') {
            // When in 'cancelled' state, form should be read-only but show current state
            StateOptions = [
                {value: 'cancelled', text: 'Cancelled'}
            ];
        }
        else {
            // Default allowed states (excluding 'closed')
            StateOptions = [
                {value: 'new', text: 'New'},
                {value: 'assigned', text: 'Assigned'},
                {value: 'in progress', text: 'In Progress'},
                {value: 'pending', text: 'Pending'},
                {value: 'resolved', text: 'Resolved'},
                {value: 'cancelled', text: 'Cancelled'}
            ];
        }

        // Clear and rebuild dropdown
        $StateDropdown.empty();
        
        // Add options
        $.each(StateOptions, function(Index, Option) {
            $StateDropdown.append(
                $('<option></option>')
                    .val(Option.value)
                    .text(Option.text)
            );
        });
        
        // Restore selection if it's still valid (match by text)
        var $MatchingOption = $StateDropdown.find('option').filter(function() {
            return $(this).text().toLowerCase() === SelectedText;
        });
        
        if ($MatchingOption.length) {
            $StateDropdown.val($MatchingOption.val());
        } else {
            // Try to select the current state if previous selection is not valid
            var $CurrentOption = $StateDropdown.find('option').filter(function() {
                return $(this).text().toLowerCase() === CurrentState;
            });
            
            if ($CurrentOption.length) {
                $StateDropdown.val($CurrentOption.val());
            } else {
                // If neither is valid, select the first available option
                $StateDropdown.val($StateDropdown.find('option:first').val());
            }
        }

        // Refresh modernized dropdown UI if available
        if (typeof Core.UI.InputFields !== 'undefined') {
            Core.UI.InputFields.Init($StateDropdown);
        }
    };

    /**
     * @name IsValidStateTransition
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {String} FromState - Current state
     * @param {String} ToState - Target state
     * @returns {Boolean} True if transition is valid
     * @description
     *      Checks if a state transition is valid.
     */
    TargetNS.IsValidStateTransition = function (FromState, ToState) {
        // State transitions using lowercase state names to match Znuny
        var ValidTransitions = {
            'new': ['assigned', 'in progress', 'pending reminder', 'cancelled'],
            'assigned': ['in progress', 'pending reminder', 'resolved', 'closed successful', 'cancelled'],
            'in progress': ['pending reminder', 'resolved', 'closed successful', 'cancelled'],
            'pending reminder': ['in progress', 'resolved', 'closed successful', 'cancelled'],
            'resolved': ['in progress', 'closed successful'],
            'closed successful': ['in progress'],
            'cancelled': ['in progress']
        };

        if (!FromState || !ToState || FromState === ToState) {
            return true;
        }

        return ValidTransitions[FromState] && ValidTransitions[FromState].indexOf(ToState) !== -1;
    };

    /**
     * @name ValidateRequiredFieldsForClosing
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {String} NewState - The new state being transitioned to.
     * @returns {Boolean} True if all required fields are filled
     * @description
     *      Validates required fields for closing an incident.
     */
    TargetNS.ValidateRequiredFieldsForClosing = function (NewState) {
        var RequiredFields = [],
            IsValid = true;

        // Resolution fields are all optional per specification
        // No required fields for resolved state

        $.each(RequiredFields, function (Index, Selector) {
            var $Field = $(Selector);
            if ($Field.length && !$Field.val()) {
                $Field.addClass('Error');
                IsValid = false;
            } else {
                $Field.removeClass('Error');
            }
        });

        return IsValid;
    };

    /**
     * @name InitAutoSave
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes auto-save functionality.
     */
    TargetNS.InitAutoSave = function () {
        var $Form = $('#IncidentForm'),
            AutoSaveTimer,
            AutoSaveInterval = 30000; // 30 seconds

        if (!$Form.length || !$Form.data('incident-id')) {
            return;
        }

        // Track form changes
        $Form.on('change', 'input, select, textarea', function () {
            clearTimeout(AutoSaveTimer);
            
            // Don't auto-save if form is invalid
            if (!Core.Form.Validate.ValidateForm($Form)) {
                return;
            }

            AutoSaveTimer = setTimeout(function () {
                TargetNS.AutoSave();
            }, AutoSaveInterval);
        });

        // Auto-save on tab switch
        $('.TabNavigation').on('click', 'li a', function () {
            if ($Form.data('changed')) {
                TargetNS.AutoSave();
            }
        });

        // Mark form as changed
        $Form.on('change', function () {
            $(this).data('changed', true);
        });
    };

    /**
     * @name AutoSave
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Performs auto-save of the incident form.
     */
    TargetNS.AutoSave = function () {
        var $Form = $('#IncidentForm'),
            URL = Core.Config.Get('Baselink'),
            Data = Core.AJAX.SerializeForm($Form);

        // Add auto-save flag
        Data.Subaction = 'AutoSave';
        Data.AutoSave = 1;

        // Show saving indicator
        Core.UI.ShowNotification(Core.Language.Translate('Saving...'), 'Info');

        $.ajax({
            url: URL,
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                if (Response.Success) {
                    Core.UI.ShowNotification(Core.Language.Translate('Auto-saved'), 'Success');
                    $Form.data('changed', false);
                    
                    // Update the saved state after successful auto-save
                    var $StateID = $('#State');
                    if ($StateID.length) {
                        var CurrentStateText = $StateID.find('option:selected').text().toLowerCase();
                        $StateID.data('saved-state', CurrentStateText);
                        // Update dropdown restrictions based on new saved state
                        TargetNS.UpdateStateDropdown(CurrentStateText);
                    }
                    
                    // Update last modified timestamp if provided
                    if (Response.LastModified) {
                        $('#LastModified').text(Response.LastModified);
                    }
                } else {
                    Core.UI.ShowNotification(
                        Core.Language.Translate('Auto-save failed: ') + (Response.Message || 'Unknown error'),
                        'Error'
                    );
                }
            },
            error: function () {
                Core.UI.ShowNotification(Core.Language.Translate('Auto-save failed'), 'Error');
            }
        });
    };

    /**
     * @name InitFormSubmission
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes form submission handling.
     */
    TargetNS.InitFormSubmission = function () {
        var $Form = $('#IncidentForm');

        if (!$Form.length) {
            return;
        }
        
        // Store the original state when form loads
        var $StateField = $('#State');
        var OriginalState = '';
        if ($StateField.length) {
            OriginalState = $StateField.val() || '';
            // Store as data attribute for later reference
            $StateField.data('original-state', OriginalState);
        }

        // Override form submission
        $Form.on('submit', function (Event) {
            var $SubmitButton = $(this).find('button[type="submit"]:focus'),
                $AllSubmitButtons = $Form.find('button[type="submit"]'),
                CurrentState = $StateField.val() || '',
                OriginalStateStored = $StateField.data('original-state') || '',
                CurrentStateText = $StateField.find('option:selected').text().toLowerCase(),
                OriginalStateText = '';
            
            // Get original state text
            $StateField.find('option').each(function() {
                if ($(this).val() === OriginalStateStored) {
                    OriginalStateText = $(this).text().toLowerCase();
                }
            });
            
            // Debug: Log the states to console for troubleshooting
            if (window.console && window.console.log) {
                console.log('Status Change Check - Original State:', OriginalStateStored, 'Original Text:', OriginalStateText);
                console.log('Status Change Check - Current State:', CurrentState, 'Current Text:', CurrentStateText);
            }
            
            // Check if status is being changed TO Closed or Cancelled
            // Handle various text formats (Closed, closed, closed successful)
            var IsChangingToClosedOrCancelled = false;
            var CurrentStateNormalized = CurrentStateText.toLowerCase().trim();
            var OriginalStateNormalized = OriginalStateText.toLowerCase().trim();
            
            if (CurrentStateNormalized === 'closed' || CurrentStateNormalized === 'cancelled' || 
                CurrentStateNormalized === 'closed successful') {
                // Only show prompt if original state was NOT already closed or cancelled
                if (OriginalStateNormalized !== 'closed' && 
                    OriginalStateNormalized !== 'cancelled' && 
                    OriginalStateNormalized !== 'closed successful' &&
                    OriginalStateNormalized !== '') {  // Also check for non-empty original state
                    IsChangingToClosedOrCancelled = true;
                }
            }
            
            // If changing to Closed or Cancelled and not yet confirmed
            if (IsChangingToClosedOrCancelled && !$Form.data('status-change-confirmed')) {
                Event.preventDefault();
                
                // Debug log
                if (window.console && window.console.log) {
                    console.log('Showing confirmation dialog for status change to closed/cancelled');
                }
                
                // Check if dialog function exists
                if (typeof Core.UI.Dialog === 'undefined' || typeof Core.UI.Dialog.ShowDialog !== 'function') {
                    // Fallback to native confirm dialog if Core.UI.Dialog is not available
                    if (confirm('Reminder! Ticket is not editable after Closed or Cancelled.\n\nDo you want to proceed?')) {
                        $Form.data('status-change-confirmed', true);
                        $Form.submit();
                    } else {
                        $AllSubmitButtons.prop('disabled', false);
                        $Form.data('status-change-confirmed', false);
                    }
                    return false;
                }
                
                // Show confirmation dialog
                Core.UI.Dialog.ShowDialog({
                    Title: Core.Language.Translate('Confirm Status Change'),
                    HTML: '<p>' + Core.Language.Translate('Reminder! Ticket is not editable after Closed or Cancelled.') + '</p>',
                    Modal: true,
                    CloseOnClickOutside: false,
                    CloseOnEscape: false,
                    PositionTop: '30%',
                    PositionLeft: 'Center',
                    Buttons: [
                        {
                            Label: Core.Language.Translate('Proceed'),
                            Class: 'Primary',
                            Function: function() {
                                // Set confirmation flag
                                $Form.data('status-change-confirmed', true);
                                // Close dialog
                                Core.UI.Dialog.CloseDialog($('.Dialog:visible'));
                                // Re-submit the form
                                $Form.submit();
                            }
                        },
                        {
                            Label: Core.Language.Translate('Cancel'),
                            Function: function() {
                                // Close dialog
                                Core.UI.Dialog.CloseDialog($('.Dialog:visible'));
                                // Re-enable submit buttons
                                $AllSubmitButtons.prop('disabled', false);
                                // Clear any confirmation flag
                                $Form.data('status-change-confirmed', false);
                            }
                        }
                    ]
                });
                
                return false;
            }
            
            // Clear confirmation flag after successful submission
            $Form.data('status-change-confirmed', false);
            
            // Ensure submit button value is included in form data
            if ($SubmitButton.length && $SubmitButton.attr('name')) {
                // Remove any existing hidden input with same name
                $Form.find('input[type="hidden"][name="' + $SubmitButton.attr('name') + '"]').remove();
                // Add hidden input with button value
                $('<input>').attr({
                    type: 'hidden',
                    name: $SubmitButton.attr('name'),
                    value: $SubmitButton.val() || 'Save'
                }).appendTo($Form);
            }

            // Use our enhanced validation function
            if (!TargetNS.ValidateRequiredFields()) {
                Event.preventDefault();
                // Re-enable submit buttons on validation failure
                $AllSubmitButtons.prop('disabled', false);
                return false;
            }
            
            // Also run Znuny's validation as backup
            if (typeof Core.Form !== 'undefined' && 
                typeof Core.Form.Validate !== 'undefined' && 
                typeof Core.Form.Validate.ValidateRequired === 'function') {
                if (!Core.Form.Validate.ValidateRequired($Form[0])) {
                    Event.preventDefault();
                    // Re-enable submit buttons on validation failure
                    $AllSubmitButtons.prop('disabled', false);
                    return false;
                }
            }

            // Resolution fields are optional, no special validation needed for resolved state

            // Show loading indicator
            Core.UI.ShowNotification(Core.Language.Translate('Processing...'), 'Info');
            
            // Disable submit buttons to prevent double submission
            $AllSubmitButtons.prop('disabled', true);
            
            // Form should submit naturally here since we didn't prevent default
        });
        
        // Re-enable submit buttons when form fields change (after validation failure)
        $Form.on('change keyup', 'input, select, textarea', function() {
            var $AllSubmitButtons = $Form.find('button[type="submit"]');
            if ($AllSubmitButtons.prop('disabled')) {
                $AllSubmitButtons.prop('disabled', false);
            }
        });
    };

    /**
     * @name ValidateRequiredFields
     * @memberof Core.Agent.IncidentForm
     * @function
     * @returns {Boolean} True if all required fields are filled
     * @description
     *      Validates all required fields in the form.
     */
    TargetNS.ValidateRequiredFields = function () {
        var IsValid = true;
        var FirstErrorField = null;

        $('.Validate_Required').each(function () {
            var $Field = $(this);
            if (!$Field.val()) {
                $Field.addClass('Error');
                
                // Store the first error field for focusing
                if (!FirstErrorField) {
                    FirstErrorField = $Field;
                }
                
                // Find the widget containing this field
                var $Widget = $Field.closest('.WidgetSimple');
                if ($Widget.length) {
                    // Check if the widget is collapsed
                    if ($Widget.hasClass('Collapsed')) {
                        // Expand the widget by clicking the toggle
                        var $Toggle = $Widget.find('.WidgetAction.Toggle a');
                        if ($Toggle.length) {
                            $Toggle.click();
                        }
                    }
                }
                
                IsValid = false;
            } else {
                $Field.removeClass('Error');
            }
        });

        // Focus on the first error field after expanding widgets
        if (FirstErrorField) {
            setTimeout(function() {
                FirstErrorField.focus();
                
                // If it's a modernized dropdown, focus on the search input instead
                var $SearchInput = $('#' + FirstErrorField.attr('id') + '_Search');
                if ($SearchInput.length) {
                    $SearchInput.focus();
                }
            }, 100);
        }

        return IsValid;
    };

    /**
     * @name InitFieldFormatting
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes field formatting (phone numbers, states, etc).
     */
    TargetNS.InitFieldFormatting = function () {
        // Format phone numbers
        $('input[name*="_phone"], input[name*="Phone"]').on('blur', function() {
            var phone = $(this).val().replace(/\D/g, '');
            if (phone.length === 10) {
                $(this).val(phone.replace(/(\d{3})(\d{3})(\d{4})/, '($1) $2-$3'));
            }
        });

        // Uppercase state fields
        $('input[name*="_state"], input[name*="State"]').on('blur', function() {
            $(this).val($(this).val().toUpperCase());
        });

        // Auto-calculate duration if both date/time fields are filled
        $('#IncidentDate, #IncidentTime, #ResolutionDate, #ResolutionTime').on('change', function() {
            TargetNS.CalculateDuration();
        });
    };

    /**
     * @name CalculateDuration
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Calculates incident duration between incident and resolution times.
     */
    TargetNS.CalculateDuration = function () {
        var $IncidentDate = $('#IncidentDate'),
            $IncidentTime = $('#IncidentTime'),
            $ResolutionDate = $('#ResolutionDate'),
            $ResolutionTime = $('#ResolutionTime'),
            $Duration = $('#Duration');

        if (!$Duration.length) {
            return;
        }

        if ($IncidentDate.val() && $IncidentTime.val() && $ResolutionDate.val() && $ResolutionTime.val()) {
            var IncidentDateTime = new Date($IncidentDate.val() + ' ' + $IncidentTime.val()),
                ResolutionDateTime = new Date($ResolutionDate.val() + ' ' + $ResolutionTime.val()),
                DiffMs = ResolutionDateTime - IncidentDateTime,
                DiffDays = Math.floor(DiffMs / 86400000),
                DiffHours = Math.floor((DiffMs % 86400000) / 3600000),
                DiffMinutes = Math.round(((DiffMs % 86400000) % 3600000) / 60000),
                Duration = '';

            if (DiffMs > 0) {
                if (DiffDays > 0) {
                    Duration += DiffDays + ' day' + (DiffDays > 1 ? 's' : '') + ' ';
                }
                if (DiffHours > 0) {
                    Duration += DiffHours + ' hour' + (DiffHours > 1 ? 's' : '') + ' ';
                }
                if (DiffMinutes > 0) {
                    Duration += DiffMinutes + ' minute' + (DiffMinutes > 1 ? 's' : '');
                }
                $Duration.val(Duration.trim());
            }
        }
    };

    /**
     * @name UpdateAssignedToDropdown
     * @memberof Core.Agent.IncidentForm
     * @function
     * @param {String} GroupID - Assignment group ID
     * @description
     *      Updates the assigned to dropdown based on selected group.
     */
    TargetNS.UpdateAssignedToDropdown = function (GroupID) {
        var $AssignedTo = $('#AssignedTo');
        
        if (!$AssignedTo.length) {
            return;
        }
        
        // Clear current options and reset value
        $AssignedTo.empty().append('<option value="">-</option>').val('');
        
        // Force visual refresh of the dropdown
        $AssignedTo[0].selectedIndex = 0;
        
        // Trigger change event to ensure any other dependent logic runs
        $AssignedTo.trigger('change');
        
        if (!GroupID) {
            return;
        }
        
        // Show loading indicator
        $AssignedTo.prop('disabled', true);
        
        var Data = {
            Action: 'AgentIncidentForm',
            Subaction: 'LoadAssignedUsers',
            GroupID: GroupID
        };

        $.ajax({
            url: Core.Config.Get('Baselink'),
            type: 'POST',
            dataType: 'json',
            data: Data,
            success: function (Response) {
                var Users = Response.Users || [];
                
                // Clear and reset dropdown
                $AssignedTo.empty().append('<option value="">-</option>').val('');
                
                // Force visual refresh of the dropdown
                $AssignedTo[0].selectedIndex = 0;
                
                $.each(Users, function(Index, User) {
                    $AssignedTo.append(
                        $('<option></option>').val(User.ID).text(User.Name)
                    );
                });
                
                // Re-enable dropdown and trigger change to ensure UI updates
                $AssignedTo.prop('disabled', false).trigger('change');
            },
            error: function () {
                Core.UI.ShowNotification(Core.Language.Translate('Failed to load users for group: ') + GroupID, 'Error');
                $AssignedTo.prop('disabled', false);
            }
        });
    };

    /**
     * @name InitWorkNotes
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes work notes functionality.
     */
    TargetNS.InitWorkNotes = function () {
        var $WorkNoteText = $('#WorkNoteText'),
            $IncludeInMSI = $('#IncludeInMSI'),
            $TicketID = $('input[name="TicketID"]'),
            $IncidentID = $('input[name="IncidentID"]'),
            $Subaction = $('input[name="Subaction"]');

        // Check if we're in update mode (either TicketID or IncidentID exists, or Subaction is UpdateAction)
        var IsUpdateMode = ($TicketID.length && $TicketID.val()) || 
                          ($IncidentID.length && $IncidentID.val()) || 
                          ($Subaction.length && $Subaction.val() === 'UpdateAction');

        if (!IsUpdateMode) {
            // Hide work notes section for new incidents
            if ($WorkNoteText.length) {
                $WorkNoteText.closest('.WidgetSimple').hide();
            }
            return;
        }

        // No button functionality needed - work notes are saved with the main form
    };

    /**
     * @name InitEBondingSubmission
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes Easy MSI Escalation ServiceNow submission functionality.
     */
    TargetNS.InitEBondingSubmission = function () {
        var $SubmitButton = $('#SubmitToServiceNowButton'),
            $Spinner = $('#SubmitToServiceNowSpinner'),
            $Result = $('#SubmitToServiceNowResult'),
            $IncidentID = $('input[name="IncidentID"]');

        if (!$SubmitButton.length) {
            return;
        }

        // Handle submit button click
        $SubmitButton.on('click', function (Event) {
            Event.preventDefault();

            var IncidentID = $IncidentID.val();

            if (!IncidentID) {
                Core.UI.ShowNotification(Core.Language.Translate('No incident ID found'), 'Error');
                return;
            }

            // Disable button and show spinner
            $SubmitButton.prop('disabled', true);
            $Spinner.show();
            $Result.empty();

            // Get CSRF token
            var ChallengeToken = $('input[name="ChallengeToken"]').val();

            // Make AJAX request
            $.ajax({
                url: Core.Config.Get('CGIHandle'),
                type: 'POST',
                dataType: 'json',
                data: {
                    Action: 'AgentIncidentForm',
                    Subaction: 'SubmitToServiceNow',
                    IncidentID: IncidentID,
                    ChallengeToken: ChallengeToken
                },
                success: function (Response) {
                    $Spinner.hide();

                    if (Response.Success) {
                        // Show success message
                        var SuccessHTML = '<div class="MessageBox Success">' +
                            '<p><i class="fa fa-check-circle"></i> ' +
                            Core.Language.Translate('Successfully submitted to MSI CMSO ServiceNow') +
                            ': <strong>' + (Response.MSITicketNumber || '') + '</strong></p>' +
                            '</div>';
                        $Result.html(SuccessHTML);

                        // Hide the button
                        $SubmitButton.hide();

                        // Show notification
                        Core.UI.ShowNotification(
                            Core.Language.Translate('Successfully submitted to MSI CMSO ServiceNow') +
                            ': ' + (Response.MSITicketNumber || ''),
                            'Success'
                        );

                        // Reload page after 2 seconds to refresh MSI fields
                        setTimeout(function() {
                            window.location.reload();
                        }, 2000);
                    } else {
                        // Show error message (backend message already includes context)
                        var ErrorHTML = '<div class="MessageBox Error">' +
                            '<p><i class="fa fa-exclamation-circle"></i> ' +
                            (Response.Message || Core.Language.Translate('Submission failed: Unknown error')) +
                            '</p></div>';
                        $Result.html(ErrorHTML);

                        // Re-enable button
                        $SubmitButton.prop('disabled', false);

                        // Don't show duplicate notification - error is already visible inline
                    }
                },
                error: function (xhr, status, error) {
                    $Spinner.hide();

                    // Show error message
                    var ErrorHTML = '<div class="MessageBox Error">' +
                        '<p><i class="fa fa-exclamation-circle"></i> ' +
                        Core.Language.Translate('Submission failed') + ': ' +
                        Core.Language.Translate('Network error or server unavailable') +
                        '</p></div>';
                    $Result.html(ErrorHTML);

                    // Re-enable button
                    $SubmitButton.prop('disabled', false);

                    // Show notification
                    Core.UI.ShowNotification(
                        Core.Language.Translate('Submission failed') + ': ' +
                        Core.Language.Translate('Network error or server unavailable'),
                        'Error'
                    );
                }
            });
        });
    };

    /**
     * @name InitResolutionNotes
     * @memberof Core.Agent.IncidentForm
     * @function
     * @description
     *      Initializes resolution notes functionality.
     */
    TargetNS.InitResolutionNotes = function () {
        var $AddButton = $('#AddResolutionNoteButton'),
            $ResolutionNotes = $('#ResolutionNotes'),
            $ResolutionCat1 = $('#ResolutionCat1'),
            $ResolutionCat2 = $('#ResolutionCat2'),
            $ResolutionCat3 = $('#ResolutionCat3'),
            $TicketID = $('input[name="TicketID"]'),
            $IncidentID = $('input[name="IncidentID"]'),
            $Subaction = $('input[name="Subaction"]');

        if (!$AddButton.length) {
            return;
        }

        // Check if we're in update mode
        var IsUpdateMode = ($TicketID.length && $TicketID.val()) || 
                          ($IncidentID.length && $IncidentID.val()) || 
                          ($Subaction.length && $Subaction.val() === 'UpdateAction');

        if (!IsUpdateMode) {
            return;
        }

        // Handle add resolution note button click
        $AddButton.on('click', function () {
            var NoteText = '';
            
            // Check if it's a rich text editor
            if ($ResolutionNotes.hasClass('RichText') && typeof CKEDITOR !== 'undefined') {
                var editor = CKEDITOR.instances[$ResolutionNotes.attr('id')];
                if (editor) {
                    NoteText = $.trim(editor.getData().replace(/<[^>]*>/g, '')); // Strip HTML tags for validation
                } else {
                    NoteText = $.trim($ResolutionNotes.val());
                }
            } else {
                NoteText = $.trim($ResolutionNotes.val());
            }
            
            if (!NoteText) {
                alert(Core.Language.Translate('Please enter resolution notes.'));
                $ResolutionNotes.focus();
                return;
            }

            // Disable button to prevent double submission
            $AddButton.prop('disabled', true);

            // Get the actual content to send (with HTML formatting)
            var ResolutionContent = '';
            if ($ResolutionNotes.hasClass('RichText') && typeof CKEDITOR !== 'undefined') {
                var editor = CKEDITOR.instances[$ResolutionNotes.attr('id')];
                if (editor) {
                    ResolutionContent = editor.getData();
                } else {
                    ResolutionContent = $ResolutionNotes.val();
                }
            } else {
                ResolutionContent = $ResolutionNotes.val();
            }

            // Use direct jQuery AJAX
            $.ajax({
                url: Core.Config.Get('Baselink'),
                type: 'POST',
                dataType: 'json',
                data: {
                    Action: 'AgentIncidentForm',
                    Subaction: 'AddResolutionNote',
                    TicketID: $TicketID.val() || '',
                    IncidentID: $IncidentID.val() || '',
                    ResolutionCat1: $ResolutionCat1.val() || '',
                    ResolutionCat2: $ResolutionCat2.val() || '',
                    ResolutionCat3: $ResolutionCat3.val() || '',
                    ResolutionNotes: ResolutionContent
                },
                success: function (Response) {
                if (Response.Success) {
                    // Clear the form
                    if ($ResolutionNotes.hasClass('RichText') && typeof CKEDITOR !== 'undefined') {
                        var editor = CKEDITOR.instances[$ResolutionNotes.attr('id')];
                        if (editor) {
                            editor.setData('');
                        } else {
                            $ResolutionNotes.val('');
                        }
                    } else {
                        $ResolutionNotes.val('');
                    }
                    
                    // Show success message
                    Core.UI.ShowNotification(Core.Language.Translate('Resolution note added successfully'), 'Success');
                    
                    // Reload the page to show updated history
                    window.location.reload();
                } else {
                    alert(Response.Message || Core.Language.Translate('Failed to add resolution note'));
                    $AddButton.prop('disabled', false);
                }
                },
                error: function () {
                    alert(Core.Language.Translate('Failed to add resolution note'));
                    $AddButton.prop('disabled', false);
                }
            });
        });
    };

    // Register namespace if Core.Init is available
    if (typeof Core.Init !== 'undefined' && typeof Core.Init.RegisterNamespace === 'function') {
        Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');
    }

    return TargetNS;
}(Core.Agent.IncidentForm || {}));