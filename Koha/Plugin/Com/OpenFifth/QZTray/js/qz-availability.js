/**
 * QZ Tray Availability Checker
 * Handles upfront QZ availability detection and caching
 */

(function(window) {
    'use strict';

    // Default cap on how long we wait for qz-tray's websocket probe before
    // declaring QZ unavailable. The qz-tray client probes several ports/TLS
    // combos sequentially when QZ isn't running, which can take 5-10s on a
    // cold page load — too slow for the "no till" warning to surface.
    //
    // This is only a fallback: the effective value comes from
    // window.qzConfig.availabilityTimeoutMs (set on the plugin config page),
    // so sites where QZ shows an "Allow" trust prompt on first connect — which
    // the user must click before the socket completes — can raise it.
    var DEFAULT_AVAILABILITY_TIMEOUT_MS = 1500;

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

                var timeoutMs = self._getTimeoutMs();
                var timeoutId = setTimeout(function() {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Availability probe timed out after ' + timeoutMs + 'ms');
                    }
                    // A timeout (rather than an outright error) is a strong signal
                    // that something is intercepting/blocking the local socket —
                    // exactly the fingerprint of a network filter. Capture it.
                    self.logDiagnostic({ category: 'connection', failureType: 'timeout', timeoutMs: timeoutMs });
                    settle(false);
                }, timeoutMs);

                self.ensureConnected()
                    .then(function() {
                        clearTimeout(timeoutId);
                        if (window.qzConfig.debugMode) {
                            console.log('QZ Tray: Available and connected');
                        }

                        // Late success after timeout still updates the cache so
                        // the next popDrawer call sees the correct state, even
                        // if we already resolved false to the UI.
                        self.available = true;

                        // Keep the socket open so drawer/discovery operations can
                        // reuse it — this avoids a second "Allow" trust prompt and
                        // the connect/disconnect churn on every action.
                        settle(true);
                    })
                    .catch(function(error) {
                        clearTimeout(timeoutId);
                        if (window.qzConfig.debugMode) {
                            console.log('QZ Tray: Not available - connection error:', error.message);
                        }
                        self.logDiagnostic({ category: 'connection', failureType: 'error', error: error });
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
         * Ensure a live QZ Tray socket, reusing an existing one when present.
         * qz.websocket.connect() rejects if a socket is already open, so we
         * only connect when isActive() reports no live connection.
         */
        ensureConnected: function() {
            if (qz.websocket && qz.websocket.isActive && qz.websocket.isActive()) {
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Reusing existing open connection');
                }
                return Promise.resolve();
            }
            return qz.websocket.connect({ retries: 0, delay: 0 });
        },

        /**
         * Resolve the effective availability-probe timeout (ms). Prefers the
         * admin-configured value from plugin config, falling back to the
         * built-in default when unset or invalid.
         */
        _getTimeoutMs: function() {
            var configured = window.qzConfig && window.qzConfig.availabilityTimeoutMs;
            var n = parseInt(configured, 10);
            return (isFinite(n) && n > 0) ? n : DEFAULT_AVAILABILITY_TIMEOUT_MS;
        },

        /**
         * Report a QZ Tray diagnostic failure to the server for fleet-wide
         * visibility. Handles both connection-probe failures and drawer-
         * operation failures via the `category` field. Only fires when
         * discovery or debug mode is enabled, so an admin can turn it on
         * centrally and see which tills are failing (and why) without touching
         * each machine. Fire-and-forget: never blocks or breaks the caller.
         *
         * opts: { category, failureType, error, timeoutMs, printer }
         */
        logDiagnostic: function(opts) {
            if (!window.qzConfig.discoveryMode && !window.qzConfig.debugMode) {
                return;
            }

            opts = opts || {};
            var error = opts.error;

            try {
                var payload = {
                    category: opts.category || 'connection',
                    failure_type: opts.failureType || 'error',
                    error_message: (error && error.message) ? String(error.message) : (opts.errorMessage || ''),
                    error_name: (error && error.name) ? String(error.name) : '',
                    timeout_ms: (opts.timeoutMs != null) ? opts.timeoutMs : null,
                    secure_context: (typeof window.isSecureContext === 'boolean') ? window.isSecureContext : null,
                    printer: opts.printer || '',
                    user_agent: navigator.userAgent || '',
                    register_id: this.config.getCurrentRegister ? (this.config.getCurrentRegister() || '') : '',
                    page_url: window.location.pathname || 'unknown'
                };

                fetch(this.config.getApiUrl('/log-connection'), {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json'
                    },
                    credentials: 'same-origin',
                    body: JSON.stringify(payload)
                }).then(function(response) {
                    if (window.qzConfig.debugMode && response.ok) {
                        console.log('QZ Tray: Diagnostic failure logged (' + payload.category + ')');
                    }
                }).catch(function(logError) {
                    if (window.qzConfig.debugMode) {
                        console.log('QZ Tray: Failed to log diagnostic failure:', logError);
                    }
                });
            } catch (e) {
                // Diagnostics must never interfere with normal operation
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray: Error while logging diagnostic failure:', e);
                }
            }
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
