/**
 * QZ Tray Cash Drawer Operations
 * Handles printer communication and drawer opening logic
 */

(function(window) {
    'use strict';

    function QZDrawer(config, messaging, auth, availability) {
        this.config = config;
        this.messaging = messaging;
        this.auth = auth;
        this.availability = availability;
        this.operationInProgress = false;
    }

    QZDrawer.prototype = {
        /**
         * Get drawer control code based on printer model
         * Uses printer support mapping from config for case-insensitive matching
         */
        getDrawerCode: function(printer) {
            var chr = function(i) {
                return String.fromCharCode(i);
            };

            var bytesToString = function(bytes) {
                var result = '';
                for (var i = 0; i < bytes.length; i++) {
                    result += chr(bytes[i]);
                }
                return result;
            };

            // Get default code
            var defaultBytes = window.qzConfig.printerSupport._default.bytes;
            var defaultCode = [bytesToString(defaultBytes)];

            // Handle case where printer is undefined or null
            if (!printer || typeof printer !== 'string') {
                if (window.qzConfig.debugMode) {
                    console.log('No printer name provided, using default drawer code');
                }
                return defaultCode;
            }

            // Case-insensitive matching against supported printer patterns
            var printerLower = printer.toLowerCase();
            var supportMapping = window.qzConfig.printerSupport;

            for (var pattern in supportMapping) {
                if (pattern === '_default') continue; // Skip default entry

                var patternLower = pattern.toLowerCase();
                if (printerLower.indexOf(patternLower) !== -1) {
                    var bytes = supportMapping[pattern].bytes;
                    if (window.qzConfig.debugMode) {
                        console.log('Matched printer pattern:', pattern, '- Using drawer code:', supportMapping[pattern].description);
                    }
                    return [bytesToString(bytes)];
                }
            }

            // No match found, use default
            if (window.qzConfig.debugMode) {
                console.log('No matching printer pattern found for:', printer, '- Using default drawer code');
            }
            return defaultCode;
        },

        /**
         * Open cash drawer with comprehensive error handling
         */
        openDrawer: function() {
            var self = this;

            // Prevent duplicate operations
            if (this.operationInProgress) {
                if (window.qzConfig.debugMode) {
                    console.log('Drawer operation already in progress, skipping');
                }
                return Promise.reject(new Error('Operation already in progress'));
            }

            this.operationInProgress = true;

            // Check QZ availability first for fast fallback
            var qzAvailable = this.availability.isAvailable();

            if (qzAvailable === false) {
                // QZ is known to be unavailable, skip connection attempt
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray not available, skipping drawer operation');
                }
                this.operationInProgress = false;
                return Promise.reject(new Error('QZ Tray not available'));
            }

            // Set up authentication
            this.auth.setupSecurity();

            return qz.websocket
                .connect()
                .then(function() {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray connected successfully');
                    }
                    return self._getPrinter();
                })
                .then(function(printer) {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Using printer:', printer);
                        console.log('QZ Tray: Drawer code for this printer:', self.getDrawerCode(printer));
                    }
                    return self._sendDrawerCommand(printer);
                })
                .then(function() {
                    if (window.qzConfig.debugMode) {
                        console.log('Cash drawer command sent successfully');
                    }
                    self.messaging.showSuccess('Cash drawer opened successfully');
                    return self._disconnect();
                })
                .catch(function(error) {
                    // Mark QZ as unavailable if connection fails
                    if (error.message && error.message.indexOf('Unable to establish connection') !== -1) {
                        self.availability.markUnavailable();
                    }

                    self.messaging.handleQZError(error, 'qztray_drawer_operation');
                    return self._disconnect().then(function() {
                        throw error; // Re-throw to maintain promise chain
                    });
                })
                .finally(function() {
                    // Reset operation flag after a short delay to prevent rapid-fire clicking
                    setTimeout(function() {
                        self.operationInProgress = false;
                    }, 500);
                });
        },

        /**
         * Get printer to use (register-specific, preferred, or default)
         */
        _getPrinter: function() {
            var selectedPrinter = this.config.getPrinter();
            if (selectedPrinter) {
                return Promise.resolve(selectedPrinter);
            } else {
                return qz.printers.getDefault();
            }
        },

        /**
         * Send drawer command to printer
         */
        _sendDrawerCommand: function(printer) {
            var config = qz.configs.create(printer);
            var data = this.getDrawerCode(printer);
            return qz.print(config, data);
        },

        /**
         * Disconnect from QZ Tray
         */
        _disconnect: function() {
            if (qz.websocket && qz.websocket.disconnect) {
                return qz.websocket.disconnect();
            }
            return Promise.resolve();
        },

        /**
         * Check if drawer operation is in progress
         */
        isOperationInProgress: function() {
            return this.operationInProgress;
        }
    };

    // Export to global scope
    window.QZDrawer = QZDrawer;

})(window);
