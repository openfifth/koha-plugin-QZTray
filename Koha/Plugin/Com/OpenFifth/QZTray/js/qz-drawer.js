/**
 * QZ Tray Cash Drawer Operations
 * Handles printer communication and drawer opening logic
 */

(function(window) {
    'use strict';

    function QZDrawer(config, messaging, auth, availability, picker) {
        this.config = config;
        this.messaging = messaging;
        this.auth = auth;
        this.availability = availability;
        this.picker = picker;
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
         * Test whether a printer name matches a supported printer pattern.
         * Mirrors getDrawerCode's case-insensitive matching.
         */
        isSupportedPrinter: function(printer) {
            if (!printer || typeof printer !== 'string') {
                return false;
            }
            var printerLower = printer.toLowerCase();
            var supportMapping = window.qzConfig.printerSupport;
            for (var pattern in supportMapping) {
                if (pattern === '_default') continue;
                if (printerLower.indexOf(pattern.toLowerCase()) !== -1) {
                    return true;
                }
            }
            return false;
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

            // Track the printer we actually tried so drawer failures can be
            // reported against it in the diagnostics store.
            var attemptedPrinter = '';

            // Reuse the socket opened at page load instead of reconnecting —
            // avoids a second "Allow" prompt and connect/disconnect churn.
            return this.availability.ensureConnected()
                .then(function() {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray connection ready (reused if already open)');
                    }
                    return self._getPrinter();
                })
                .then(function(printer) {
                    attemptedPrinter = printer;
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
                    // Intentionally keep the socket open for the next operation.
                })
                .catch(function(error) {
                    // Staff dismissed the printer picker — benign, let the
                    // transaction continue without a scary warning or a
                    // diagnostics entry.
                    if (error && error.message === 'PRINTER_SELECTION_CANCELLED') {
                        if (window.qzConfig.debugMode) {
                            console.log('QZ Tray: Printer selection cancelled by user');
                        }
                        throw error;
                    }

                    // Mark QZ as unavailable if connection fails
                    if (error.message && error.message.indexOf('Unable to establish connection') !== -1) {
                        self.availability.markUnavailable();
                    }

                    self.messaging.handleQZError(error, 'qztray_drawer_operation');

                    // Feed drawer-operation failures into the same diagnostics
                    // store as connection failures (kept alongside the warning).
                    self.availability.logDiagnostic({
                        category: 'drawer',
                        failureType: self._drawerFailureType(error),
                        error: error,
                        printer: attemptedPrinter
                    });

                    throw error; // Re-throw to maintain promise chain
                })
                .finally(function() {
                    // Reset operation flag after a short delay to prevent rapid-fire clicking
                    setTimeout(function() {
                        self.operationInProgress = false;
                    }, 500);
                });
        },

        /**
         * Classify a drawer-operation failure for diagnostics.
         */
        _drawerFailureType: function(error) {
            var msg = (error && error.message) ? error.message : '';
            if (msg.toLowerCase().indexOf('printer') !== -1) {
                return 'printer_not_found';
            }
            if (msg.indexOf('WebSocket') !== -1) {
                return 'websocket';
            }
            return 'error';
        },

        /**
         * Get printer to use for this operation.
         *
         * Order of preference:
         *  1. The register's configured mapping, if any.
         *  2. If exactly one supported printer is detected, use it and remember
         *     it for this register.
         *  3. If several supported printers are detected, ask the operator to
         *     choose (and optionally remember the choice).
         *  4. Otherwise fall back to the system default printer, preserving the
         *     prior behaviour (and its "printer not found" warning) when nothing
         *     supported is attached.
         */
        _getPrinter: function() {
            var self = this;

            var selectedPrinter = this.config.getPrinter();
            if (selectedPrinter) {
                return Promise.resolve(selectedPrinter);
            }

            return qz.printers.find().then(function(printers) {
                if (!Array.isArray(printers)) {
                    printers = printers ? [printers] : [];
                }

                var supported = printers.filter(function(p) {
                    return self.isSupportedPrinter(p);
                });

                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: No register mapping; supported printers detected:', supported);
                }

                if (supported.length === 1) {
                    var only = supported[0];
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Auto-selecting the only supported printer:', only);
                    }
                    self._saveRegisterPrinter(only);
                    return only;
                }

                if (supported.length > 1 && self.picker) {
                    return self.picker.pick(supported).then(function(result) {
                        if (result && result.save) {
                            self._saveRegisterPrinter(result.printer);
                        }
                        return result.printer;
                    });
                }

                // Nothing supported found — fall back to the system default.
                return qz.printers.getDefault();
            });
        },

        /**
         * Persist a register -> printer mapping chosen at the till so future
         * operations skip discovery/selection. Fire-and-forget; also updates the
         * in-memory mapping so we don't re-prompt during this session.
         */
        _saveRegisterPrinter: function(printer) {
            var registerId = this.config.getCurrentRegister ? this.config.getCurrentRegister() : '';
            if (!registerId || !printer) {
                return; // Nothing to persist without a register context
            }

            // Optimistically update the in-memory mapping first.
            if (this.config.registerMappings) {
                this.config.registerMappings[registerId] = printer;
            }

            try {
                fetch(this.config.getApiUrl('/set-register-printer'), {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json'
                    },
                    credentials: 'same-origin',
                    body: JSON.stringify({ register_id: String(registerId), printer: printer })
                }).then(function(response) {
                    if (window.qzConfig.debugMode && response.ok) {
                        console.log('QZ Tray: Saved register printer mapping:', printer);
                    }
                }).catch(function(err) {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Failed to save register printer mapping:', err);
                    }
                });
            } catch (e) {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Error saving register printer mapping:', e);
                }
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
         * Check if drawer operation is in progress
         */
        isOperationInProgress: function() {
            return this.operationInProgress;
        }
    };

    // Export to global scope
    window.QZDrawer = QZDrawer;

})(window);
