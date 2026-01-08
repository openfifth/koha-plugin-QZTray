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
         * Can be called in two phases:
         * 1. Early DOM injection (drawer not yet ready)
         * 2. Enable button once drawer is ready
         */
        initialize: function(drawerReady) {
            // Only run on the POS page (pos/pay.pl)
            if (window.location.href.indexOf('pos/pay.pl') === -1) {
                return;
            }

            // If toolbar doesn't exist yet, create it
            if (!this.toolbarElement) {
                console.log('QZ Tray: Injecting POS toolbar early');
                this._createToolbar();
            }

            // If drawer is ready, enable the button
            if (drawerReady && this.openDrawerButton) {
                this.openDrawerButton.disabled = false;
                this.openDrawerButton.title = '';
                console.log('QZ Tray: POS toolbar button enabled');
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

            console.log('QZ Tray: POS toolbar added successfully');
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
            this.openDrawerButton.disabled = true; // Disabled until QZ Tray is ready
            this.openDrawerButton.title = 'Initializing QZ Tray...';

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

            console.log('QZ Tray: Opening drawer from POS toolbar');

            this.drawer.openDrawer()
                .then(function() {
                    console.log('QZ Tray: Drawer opened successfully from toolbar');
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
                console.log('QZ Tray: POS toolbar removed');
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
