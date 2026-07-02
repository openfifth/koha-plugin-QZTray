/**
 * QZ Tray Availability Checker
 * Handles upfront QZ availability detection and caching
 */

(function(window) {
    'use strict';

    // Hard cap on how long we wait for qz-tray's websocket probe before
    // declaring QZ unavailable. The qz-tray client probes several ports/TLS
    // combos sequentially when QZ isn't running, which can take 5-10s on a
    // cold page load — too slow for the "no till" warning to surface.
    var AVAILABILITY_TIMEOUT_MS = 1500;

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

            this.checkPromise = new Promise(function(resolve) {
                var settled = false;
                function settle(value) {
                    if (settled) return;
                    settled = true;
                    self.available = value;
                    self.checkInProgress = false;
                    resolve(value);
                }

                var timeoutId = setTimeout(function() {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Availability probe timed out after ' + AVAILABILITY_TIMEOUT_MS + 'ms');
                    }
                    settle(false);
                }, AVAILABILITY_TIMEOUT_MS);

                qz.websocket.connect({ retries: 0, delay: 0 })
                    .then(function() {
                        clearTimeout(timeoutId);
                        if (window.qzConfig.debugMode) {
                            console.log('QZ Tray: Available and connected');
                        }

                        // Late success after timeout still updates the cache so
                        // the next popDrawer call sees the correct state, even
                        // if we already resolved false to the UI.
                        self.available = true;

                        // Disconnect after check
                        return qz.websocket.disconnect()
                            .catch(function() {
                                // Ignore disconnect errors
                            })
                            .then(function() {
                                settle(true);
                            });
                    })
                    .catch(function(error) {
                        clearTimeout(timeoutId);
                        if (window.qzConfig.debugMode) {
                            console.log('QZ Tray: Not available - connection error:', error.message);
                        }
                        settle(false);
                    });
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
