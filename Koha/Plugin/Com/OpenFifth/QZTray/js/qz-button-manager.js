/**
 * QZ Tray Button Manager
 * Handles button replacement and UI manipulation for cash drawer integration
 */

(function(window) {
    'use strict';

    function QZButtonManager(drawer, pageDetector) {
        this.drawer = drawer;
        this.pageDetector = pageDetector;
        this.buttonRegistry = new Map();
    }

    QZButtonManager.prototype = {
        /**
         * Initialize button replacement on current page
         */
        initialize: function() {
            var matchedConfigs = this.pageDetector.detectCurrentPage();

            if (matchedConfigs.length === 0) {
                console.log('QZ Tray: Current page not configured for cash drawer integration');
                return;
            }

            console.log('QZ Tray: Initializing button replacement for', matchedConfigs.length, 'configuration(s)');

            matchedConfigs.forEach(function(config) {
                this._replaceButtonsForConfig(config);
            }.bind(this));
        },

        /**
         * Replace buttons based on page configuration
         */
        _replaceButtonsForConfig: function(config) {
            var self = this;
            var elements = document.querySelectorAll(config.selector);

            elements.forEach(function(element) {
                self._replaceButton(element, config);
            });
        },

        /**
         * Replace individual button with drawer-enabled version
         */
        _replaceButton: function(originalButton, config) {
            if (!originalButton) {
                console.warn('QZ Tray: Button not found for selector:', config.selector);
                return;
            }

            var buttonId = this._generateButtonId();
            var originalClasses = originalButton.className || '';
            var originalType = originalButton.type || 'button';

            // Store original button state
            this.buttonRegistry.set(buttonId, {
                original: originalButton,
                drawer: null,
                config: config,
                originalText: originalButton.textContent || originalButton.value,
                originalClasses: originalClasses,
                originalType: originalType
            });

            // Update original button
            originalButton.textContent = config.originalButtonText;
            originalButton.value = config.originalButtonText;
            originalButton.className = originalClasses + ' qz-original-button-' + buttonId;
            originalButton.style.display = 'none';

            // Create drawer button
            var drawerButton = this._createDrawerButton(buttonId, originalClasses, originalType, config);
            originalButton.parentNode.insertBefore(drawerButton, originalButton);

            // Store drawer button reference
            var buttonData = this.buttonRegistry.get(buttonId);
            buttonData.drawer = drawerButton;
            this.buttonRegistry.set(buttonId, buttonData);

            console.log('QZ Tray: Button replaced for', config.description, 'with ID', buttonId);
        },

        /**
         * Create drawer button element
         */
        _createDrawerButton: function(buttonId, originalClasses, originalType, config) {
            var self = this;

            var drawerButton = document.createElement('input');
            drawerButton.type = originalType;
            drawerButton.className = originalClasses + ' qz-drawer-button-' + buttonId;
            drawerButton.id = 'qz-drawer-button-' + buttonId;
            drawerButton.value = config.drawerButtonText;

            // Add click handler
            drawerButton.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                self._handleDrawerButtonClick(buttonId);
                return false;
            });

            return drawerButton;
        },

        /**
         * Handle drawer button click
         */
        _handleDrawerButtonClick: function(buttonId) {
            var buttonData = this.buttonRegistry.get(buttonId);
            if (!buttonData) {
                console.error('QZ Tray: Button data not found for ID:', buttonId);
                return;
            }

            console.log('QZ Tray: Opening drawer for', buttonData.config.description);

            this.drawer.openDrawer()
                .then(function() {
                    // On success, hide drawer button and show original
                    buttonData.drawer.style.display = 'none';
                    buttonData.original.style.display = '';
                })
                .catch(function(error) {
                    console.error('QZ Tray: Drawer operation failed:', error);

                    // On error, automatically proceed with workflow after brief delay
                    // This allows the user to continue with their Koha workflow even if the till drawer fails
                    setTimeout(function() {
                        buttonData.drawer.style.display = 'none';
                        buttonData.original.style.display = '';
                        console.log('QZ Tray: Proceeding with workflow despite drawer error');
                    }, 500); // 1/2 second delay to allow user to see the error message
                });
        },

        /**
         * Generate unique button ID
         */
        _generateButtonId: function() {
            return Math.floor(Math.random() * 1000000) + 1;
        },

        /**
         * Reset button states (useful for testing or cleanup)
         */
        resetButtons: function() {
            this.buttonRegistry.forEach(function(buttonData, buttonId) {
                if (buttonData.drawer) {
                    buttonData.drawer.remove();
                }
                buttonData.original.style.display = '';
                buttonData.original.className = buttonData.original.className.replace(' qz-original-button-' + buttonId, '');
            });

            this.buttonRegistry.clear();
            console.log('QZ Tray: All buttons reset');
        },

        /**
         * Get debug information about managed buttons
         */
        getDebugInfo: function() {
            var buttons = [];

            this.buttonRegistry.forEach(function(buttonData, buttonId) {
                buttons.push({
                    buttonId: buttonId,
                    config: buttonData.config,
                    originalVisible: buttonData.original.style.display !== 'none',
                    drawerVisible: buttonData.drawer ? buttonData.drawer.style.display !== 'none' : false
                });
            });

            return {
                totalButtons: this.buttonRegistry.size,
                buttons: buttons,
                pageSupported: this.pageDetector.isCurrentPageSupported()
            };
        }
    };

    // Export to global scope
    window.QZButtonManager = QZButtonManager;

})(window);
