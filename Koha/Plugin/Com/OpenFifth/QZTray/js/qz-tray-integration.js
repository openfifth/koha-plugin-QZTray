/**
 * QZ Tray Cash Drawer Integration for Koha
 * Main integration file that orchestrates all QZ Tray components
 * Pure vanilla JavaScript - no jQuery dependency
 */

(function(window) {
    'use strict';

    // Ensure all required modules are available
    if (typeof QZTransactionLock === 'undefined' ||
        typeof QZConfig === 'undefined' ||
        typeof QZMessaging === 'undefined' ||
        typeof QZAuth === 'undefined' ||
        typeof QZAvailability === 'undefined' ||
        typeof QZDrawer === 'undefined' ||
        typeof QZPageDetector === 'undefined' ||
        typeof QZButtonManager === 'undefined' ||
        typeof QZPosToolbar === 'undefined') {
        console.error('QZ Tray: Required modules not loaded. Please ensure all JavaScript files are included.');
        return;
    }

    // Global QZ Tray integration manager
    var QZTrayIntegration = {
        config: null,
        messaging: null,
        auth: null,
        availability: null,
        drawer: null,
        pageDetector: null,
        buttonManager: null,
        posToolbar: null,
        initialized: false,

        /**
         * Initialize QZ Tray integration
         */
        initialize: function(configData) {
            if (this.initialized) {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Already initialized');
                }
                return Promise.resolve();
            }

            if (window.qzConfig.debugMode) {
                console.log('QZ Tray: Initializing integration components');
            }

            // Initialize modules
            this.config = new QZConfig(configData || window.qzConfig || {});
            this.messaging = new QZMessaging(this.config);
            this.auth = new QZAuth(this.config, this.messaging);
            this.availability = new QZAvailability(this.config, this.auth);
            this.drawer = new QZDrawer(this.config, this.messaging, this.auth, this.availability);
            this.pageDetector = new QZPageDetector();
            this.buttonManager = new QZButtonManager(this.drawer, this.pageDetector);
            this.posToolbar = new QZPosToolbar(this.drawer);

            // Initialize configuration and check certificate status
            return this.config.initialize().then(function(status) {
                // Check QZ Tray availability at page load
                return this.availability.checkAvailability().then(function(available) {
                    // Always log availability status for user awareness
                    if (available) {
                        console.log('QZ Tray: Available - cash drawer operations enabled');
                    } else {
                        console.log('QZ Tray: Not available - transactions will proceed without drawer operations');

                        // Show user-visible info message when QZ is unavailable
                        this.messaging.showWarning('Cash register not detected, transactions can continue but the any attached cash drawer will not open.');
                    }

                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Availability check complete:', available ? 'Available' : 'Not available');
                    }

                    this.initialized = true;

                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Integration initialized successfully');
                    }

                    // Only initialize button replacement and toolbar if QZ is available
                    if (available) {
                        // Initialize button replacement
                        this.buttonManager.initialize();

                        // Initialize POS toolbar now that drawer is ready
                        this.posToolbar.initialize();

                        // Discover and log printers if debug mode is enabled
                        if (window.qzConfig.debugMode) {
                            this.discoverPrinters();
                        }
                    } else {
                        if (window.qzConfig.debugMode) {
                            console.log('QZ Tray: Skipping button replacement - QZ not available');
                        }
                    }

                    return status;
                }.bind(this));
            }.bind(this)).catch(function(error) {
                console.error('QZ Tray: Initialization failed:', error);
                this.messaging.showError('QZ Tray initialization failed: ' + error.message);
                throw error;
            }.bind(this));
        },

        /**
         * Open cash drawer (legacy function for backward compatibility)
         */
        openDrawer: function() {
            if (!this.initialized) {
                console.error('QZ Tray: Not initialized');
                return Promise.reject(new Error('QZ Tray not initialized'));
            }

            return this.drawer.openDrawer();
        },

        /**
         * Get debug information
         */
        getDebugInfo: function() {
            if (!this.initialized) {
                return { initialized: false, error: 'QZ Tray not initialized' };
            }

            return {
                initialized: this.initialized,
                availability: this.availability.getStatus(),
                config: {
                    isValid: this.config.isValid(),
                    apiBase: this.config.apiBase,
                    preferredPrinter: this.config.preferredPrinter
                },
                page: this.pageDetector.getDebugInfo(),
                buttons: this.buttonManager.getDebugInfo(),
                posToolbar: this.posToolbar.getDebugInfo(),
                drawer: {
                    operationInProgress: this.drawer.isOperationInProgress()
                }
            };
        },

        /**
         * Reset integration state (useful for testing)
         */
        reset: function() {
            if (this.buttonManager) {
                this.buttonManager.resetButtons();
            }
            if (this.posToolbar) {
                this.posToolbar.remove();
            }
            this.initialized = false;
            if (window.qzConfig.debugMode) {
                console.log('QZ Tray: Integration reset');
            }
        },

        /**
         * Discover all available printers and log to server (debug mode only)
         */
        discoverPrinters: function() {
            if (!window.qzConfig.debugMode) {
                return;
            }

            if (window.qzConfig.debugMode) {
                console.log('QZ Tray: Starting printer discovery for debugging');
            }

            var self = this;

            // Set up authentication
            this.auth.setupSecurity();

            qz.websocket.connect().then(function() {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Connected for printer discovery');
                }
                return qz.printers.find();
            }).then(function(printers) {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Discovered printers:', printers);
                }

                // Send discovered printers to server for logging
                self._logDiscoveredPrinters(printers);

                return qz.websocket.disconnect();
            }).catch(function(error) {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Printer discovery failed:', error);
                }
                // Try to disconnect even if discovery failed
                if (qz.websocket && qz.websocket.disconnect) {
                    qz.websocket.disconnect().catch(function() {});
                }
            });
        },

        /**
         * Log discovered printers to server (internal method)
         */
        _logDiscoveredPrinters: function(printers) {
            if (!window.qzConfig.debugMode || !printers || printers.length === 0) {
                return;
            }

            var logUrl = this.config.getApiUrl('/log-printer');
            var registerid = this.config.getCurrentRegister();

            fetch(logUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json'
                },
                credentials: 'same-origin',
                body: JSON.stringify({
                    printers: printers,
                    register_id: registerid || '',
                    page_url: window.location.pathname || 'unknown'
                })
            }).then(function(response) {
                if (window.qzConfig.debugMode && response.ok) {
                    console.log('QZ Tray: Printer discovery logged successfully');
                }
            }).catch(function(error) {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Failed to log printer discovery:', error);
                }
            });
        }
    };

    // Legacy functions for backward compatibility
    function popDrawer(showClass, hideClass) {
        console.warn('QZ Tray: popDrawer() is deprecated. Use QZTrayIntegration.openDrawer() instead.');

        if (!QZTrayIntegration.initialized) {
            console.error('QZ Tray: Integration not initialized');
            return false;
        }

        QZTrayIntegration.openDrawer().then(function() {
            // Handle legacy button visibility logic
            if (hideClass) {
                var elements = document.querySelectorAll('.' + hideClass);
                elements.forEach(function(el) { el.style.display = 'none'; });
            }
            if (showClass) {
                var elements = document.querySelectorAll('.' + showClass);
                elements.forEach(function(el) { el.style.display = ''; });
            }
        }).catch(function(error) {
            // Handle legacy button visibility logic on error
            if (hideClass) {
                var elements = document.querySelectorAll('.' + hideClass);
                elements.forEach(function(el) { el.style.display = 'none'; });
            }
            if (showClass) {
                var elements = document.querySelectorAll('.' + showClass);
                elements.forEach(function(el) { el.style.display = ''; });
            }
        });

        return false;
    }

    function displayError(err) {
        console.error('QZ Tray (legacy):', err);
    }

    function chr(i) {
        return String.fromCharCode(i);
    }

    function drawerCode(printer) {
        if (QZTrayIntegration.drawer) {
            return QZTrayIntegration.drawer.getDrawerCode(printer);
        }
        // Fallback for legacy compatibility
        var code = [chr(27) + chr(112) + chr(48) + chr(55) + chr(121)];
        return code;
    }

    // Export to global scope
    window.QZTrayIntegration = QZTrayIntegration;

    // Legacy function exports for backward compatibility
    window.popDrawer = popDrawer;
    window.displayError = displayError;
    window.chr = chr;
    window.drawerCode = drawerCode;

    // Auto-initialize when DOM is ready (or immediately if already ready)
    function documentReady(fn) {
        // Run immediately if DOM is already interactive or complete
        if (document.readyState === 'interactive' || document.readyState === 'complete') {
            // Use setTimeout to avoid blocking the current execution
            setTimeout(fn, 0);
        } else if (document.readyState === 'loading') {
            // Wait for DOMContentLoaded if still loading
            document.addEventListener('DOMContentLoaded', fn);
        }
    }

    documentReady(function() {
        // Use global qzConfig if available
        var config = window.qzConfig || {
            apiBase: '',
            preferredPrinter: ''
        };

        QZTrayIntegration.initialize(config).catch(function(error) {
            console.error('QZ Tray: Auto-initialization failed:', error);
        });
    });

})(window);
