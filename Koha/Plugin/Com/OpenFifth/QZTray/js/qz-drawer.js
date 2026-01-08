/**
 * QZ Tray Cash Drawer Operations
 * Handles printer communication and drawer opening logic
 */

(function(window) {
    'use strict';

    function QZDrawer(config, messaging, auth) {
        this.config = config;
        this.messaging = messaging;
        this.auth = auth;
        this.operationInProgress = false;
    }

    QZDrawer.prototype = {
        /**
         * Get drawer control code based on printer model
         */
        getDrawerCode: function(printer) {
            var chr = function(i) {
                return String.fromCharCode(i);
            };

            var code = [chr(27) + chr(112) + chr(48) + chr(55) + chr(121)]; // default code

            // Handle case where printer is undefined or null
            if (!printer || typeof printer !== 'string') {
                console.log('No printer name provided, using default drawer code');
                return code;
            }

            if (printer.indexOf('Bixolon SRP-350') !== -1 ||
                printer.indexOf('Epson TM-T88V') !== -1 ||
                printer.indexOf('Metapace T') !== -1) {
                code = [chr(27) + chr(112) + chr(48) + chr(55) + chr(121)];
            }
            if (printer.indexOf('Citizen CBM1000') !== -1 ||
                printer.indexOf('Citizen CT-S2000') !== -1 ||
                printer.indexOf('CT-S2000') !== -1 ||
                printer.indexOf('Citizen CTS2000') !== -1 ||
                printer.indexOf('CTS2000') !== -1) {
                code = [chr(27) + chr(112) + chr(0) + chr(50) + chr(250)];
            }
            return code;
        },

        /**
         * Open cash drawer with comprehensive error handling
         */
        openDrawer: function() {
            var self = this;

            // Prevent duplicate operations
            if (this.operationInProgress) {
                console.log('Drawer operation already in progress, skipping');
                return Promise.reject(new Error('Operation already in progress'));
            }

            this.operationInProgress = true;

            // Set up authentication
            this.auth.setupSecurity();

            return qz.websocket
                .connect()
                .then(function() {
                    console.log('QZ Tray connected successfully');
                    return self._getPrinter();
                })
                .then(function(printer) {
                    console.log('QZ Tray: Using printer:', printer);
                    console.log('QZ Tray: Drawer code for this printer:', self.getDrawerCode(printer));
                    return self._sendDrawerCommand(printer);
                })
                .then(function() {
                    console.log('Cash drawer command sent successfully');
                    self.messaging.showSuccess('Cash drawer opened successfully');
                    return self._disconnect();
                })
                .catch(function(error) {
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