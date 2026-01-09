/**
 * QZ Tray POS Toolbar
 * Adds an "Open cash drawer" button to the Point of Sale page
 */

(function(window) {
    'use strict';

    function QZPosToolbar(drawer) {
        this.drawer = drawer;
        this.toolbarElement = null;
        this.openDrawerButton = null;
    }

    QZPosToolbar.prototype = {
        /**
         * Initialize the toolbar on the POS page
         * Only called once when QZ Tray is fully initialized
         */
        initialize: function() {
            // Only run on the POS page (pos/pay.pl)
            if (window.location.href.indexOf('pos/pay.pl') === -1) {
                return;
            }

            // Create and inject toolbar if it doesn't exist
            if (!this.toolbarElement) {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Creating POS toolbar');
                }
                this._createToolbar();
            }
        },

        /**
         * Create and inject the toolbar into the page
         */
        _createToolbar: function() {
            // Find the h1 "Point of sale" element
            var h1Element = this._findPointOfSaleHeading();
            if (!h1Element) {
                console.warn('QZ Tray: Could not find Point of sale heading');
                return;
            }

            // Create toolbar element
            this.toolbarElement = this._createToolbarElement();

            // Insert toolbar before the h1 heading
            h1Element.parentNode.insertBefore(this.toolbarElement, h1Element);

            if (window.qzConfig.debugMode) {
                console.log('QZ Tray: POS toolbar added successfully');
            }
        },

        /**
         * Find the "Point of sale" h1 heading
         */
        _findPointOfSaleHeading: function() {
            var headings = document.querySelectorAll('h1');
            for (var i = 0; i < headings.length; i++) {
                if (headings[i].textContent.trim() === 'Point of sale') {
                    return headings[i];
                }
            }
            return null;
        },

        /**
         * Create the toolbar element with standard Koha markup
         */
        _createToolbarElement: function() {
            var toolbar = document.createElement('div');
            toolbar.id = 'qz-toolbar';
            toolbar.className = 'btn-toolbar';

            // Create "Open cash drawer" button
            this.openDrawerButton = document.createElement('button');
            this.openDrawerButton.type = 'button';
            this.openDrawerButton.className = 'btn btn-default';
            this.openDrawerButton.id = 'qz-open-drawer';

            // Add icon
            var icon = document.createElement('i');
            icon.className = 'fa fa-money-bill-alt';
            icon.setAttribute('aria-hidden', 'true');

            this.openDrawerButton.appendChild(icon);
            this.openDrawerButton.appendChild(document.createTextNode(' Open cash drawer'));

            // Add click handler
            var self = this;
            this.openDrawerButton.addEventListener('click', function(e) {
                e.preventDefault();
                self._handleOpenDrawerClick();
                return false;
            });

            toolbar.appendChild(this.openDrawerButton);

            return toolbar;
        },

        /**
         * Handle "Open cash drawer" button click
         */
        _handleOpenDrawerClick: function() {
            var self = this;

            // Disable button during operation
            this.openDrawerButton.disabled = true;
            this.openDrawerButton.textContent = ' Opening drawer...';

            // Re-add icon
            var icon = document.createElement('i');
            icon.className = 'fa fa-spinner fa-spin';
            icon.setAttribute('aria-hidden', 'true');
            this.openDrawerButton.insertBefore(icon, this.openDrawerButton.firstChild);

            if (window.qzConfig.debugMode) {
                console.log('QZ Tray: Opening drawer from POS toolbar');
            }

            this.drawer.openDrawer()
                .then(function() {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Drawer opened successfully from toolbar');
                    }
                    self._resetButton(true);
                })
                .catch(function(error) {
                    console.error('QZ Tray: Drawer operation failed:', error);
                    self._resetButton(false);
                });
        },

        /**
         * Reset button to initial state
         */
        _resetButton: function(success) {
            var self = this;

            // Update button text to show result
            if (success) {
                this.openDrawerButton.className = 'btn btn-success';
                this.openDrawerButton.innerHTML = '<i class="fa fa-check" aria-hidden="true"></i> Drawer opened';
            } else {
                this.openDrawerButton.className = 'btn btn-warning';
                this.openDrawerButton.innerHTML = '<i class="fa fa-exclamation-triangle" aria-hidden="true"></i> Drawer open failed';
            }

            // Reset to normal state after 2 seconds
            setTimeout(function() {
                self.openDrawerButton.className = 'btn btn-default';
                self.openDrawerButton.innerHTML = '<i class="fa fa-money-bill-alt" aria-hidden="true"></i> Open cash drawer';
                self.openDrawerButton.disabled = false;
            }, 2000);
        },

        /**
         * Remove the toolbar (cleanup)
         */
        remove: function() {
            if (this.toolbarElement && this.toolbarElement.parentNode) {
                this.toolbarElement.parentNode.removeChild(this.toolbarElement);
                this.toolbarElement = null;
                this.openDrawerButton = null;
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: POS toolbar removed');
                }
            }
        },

        /**
         * Get debug information
         */
        getDebugInfo: function() {
            return {
                toolbarPresent: this.toolbarElement !== null,
                buttonPresent: this.openDrawerButton !== null,
                buttonDisabled: this.openDrawerButton ? this.openDrawerButton.disabled : null,
                onPosPage: window.location.href.indexOf('pos/pay.pl') !== -1
            };
        }
    };

    // Export to global scope
    window.QZPosToolbar = QZPosToolbar;

})(window);
