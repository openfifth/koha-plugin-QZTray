/**
 * QZ Tray Availability Checker
 * Handles upfront QZ availability detection and caching
 */

(function(window) {
    'use strict';

    function QZAvailability(config, auth) {
        this.config = config;
        this.auth = auth;
        this.available = undefined; // undefined = not checked, true = available, false = unavailable
        this.checkInProgress = false;
        this.checkPromise = null;
    }

    QZAvailability.prototype = {
        /**
         * Check if QZ Tray is available (with caching)
         * Returns a promise that resolves to true/false
         */
        checkAvailability: function() {
            var self = this;

            // Return cached result if available
            if (this.available !== undefined) {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Using cached availability status:', this.available);
                }
                return Promise.resolve(this.available);
            }

            // Return existing check promise if one is in progress
            if (this.checkInProgress && this.checkPromise) {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Availability check already in progress');
                }
                return this.checkPromise;
            }

            // Perform new availability check
            this.checkInProgress = true;

            if (window.qzConfig.debugMode) {
                console.log('QZ Tray: Checking availability...');
            }

            // Set up authentication before checking
            this.auth.setupSecurity();

            this.checkPromise = qz.websocket.connect({ retries: 0, delay: 0 })
                .then(function() {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Available and connected');
                    }
                    self.available = true;
                    self.checkInProgress = false;

                    // Disconnect after check
                    return qz.websocket.disconnect()
                        .catch(function() {
                            // Ignore disconnect errors
                        })
                        .then(function() {
                            return true;
                        });
                })
                .catch(function(error) {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Not available - connection error:', error.message);
                    }

                    self.available = false;
                    self.checkInProgress = false;
                    return false;
                });

            return this.checkPromise;
        },

        /**
         * Check if QZ Tray is currently available (synchronous)
         * Returns: true if available, false if unavailable, undefined if not yet checked
         */
        isAvailable: function() {
            return this.available;
        },

        /**
         * Force recheck of QZ availability (clears cache)
         */
        recheckAvailability: function() {
            if (window.qzConfig.debugMode) {
                console.log('QZ Tray: Forcing availability recheck');
            }
            this.available = undefined;
            this.checkInProgress = false;
            this.checkPromise = null;
            return this.checkAvailability();
        },

        /**
         * Mark QZ as unavailable (called when operations fail)
         */
        markUnavailable: function() {
            if (window.qzConfig.debugMode) {
                console.log('QZ Tray: Marked as unavailable');
            }
            this.available = false;
        },

        /**
         * Get availability status for debugging
         */
        getStatus: function() {
            return {
                available: this.available,
                checkInProgress: this.checkInProgress,
                statusText: this.available === undefined ? 'Not checked' :
                           this.available ? 'Available' : 'Unavailable'
            };
        }
    };

    // Export to global scope
    window.QZAvailability = QZAvailability;

})(window);
