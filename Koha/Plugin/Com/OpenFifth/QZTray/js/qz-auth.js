/**
 * QZ Tray Authentication Manager
 * Handles certificate loading and message signing via API
 */

(function(window) {
    'use strict';

    function QZAuth(config, messaging) {
        this.config = config;
        this.messaging = messaging;
    }

    QZAuth.prototype = {
        /**
         * Set up QZ Tray security promises for certificate and signing
         */
        setupSecurity: function() {
            this.setupCertificatePromise();
            this.setupSignaturePromise();
        },

        /**
         * Configure certificate loading from API
         */
        setupCertificatePromise: function() {
            var self = this;

            qz.security.setCertificatePromise(function(resolve, reject) {
                fetch(self.config.getApiUrl('/certificate'), {
                    method: 'GET',
                    cache: 'no-store',
                    credentials: 'same-origin'
                }).then(function(response) {
                    if (response.ok) {
                        return response.text();
                    } else {
                        // Try to parse JSON error response for better error messages
                        return response.json().then(function(errorData) {
                            var message = errorData.error || 'Certificate not configured';
                            var code = errorData.error_code || 'UNKNOWN_ERROR';
                            throw new Error(message + ' (' + code + ')');
                        }).catch(function() {
                            // Fallback if JSON parsing fails
                            throw new Error('Certificate not configured');
                        });
                    }
                }).then(function(certificate) {
                    resolve(certificate);
                }).catch(function(error) {
                    console.error('Failed to load certificate:', error);

                    // Report error to server for monitoring
                    self.messaging.logError({
                        error: 'Certificate loading failed: ' + error.message,
                        context: 'qztray_certificate_load'
                    });

                    resolve(''); // Allow operation to continue without certificate
                });
            });
        },

        /**
         * Configure message signing via API
         */
        setupSignaturePromise: function() {
            var self = this;

            qz.security.setSignaturePromise(function(toSign) {
                return function(resolve, reject) {
                    fetch(self.config.getApiUrl('/sign'), {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                        },
                        credentials: 'same-origin',
                        body: JSON.stringify({ message: toSign })
                    }).then(function(response) {
                        if (response.ok) {
                            return response.text();
                        } else {
                            // Try to parse JSON error response for better error messages
                            return response.json().then(function(errorData) {
                                var message = errorData.error || 'Signing failed';
                                var code = errorData.error_code || 'UNKNOWN_ERROR';
                                throw new Error(message + ' (' + code + ')');
                            }).catch(function() {
                                // Fallback if JSON parsing fails
                                throw new Error('Signing failed');
                            });
                        }
                    }).then(function(signature) {
                        resolve(signature);
                    }).catch(function(error) {
                        console.error('Failed to sign message:', error);

                        // Report error to server for monitoring
                        self.messaging.logError({
                            error: 'Message signing failed: ' + error.message,
                            context: 'qztray_message_signing'
                        });

                        resolve(''); // Allow operation to continue without signature
                    });
                };
            });
        }
    };

    // Export to global scope
    window.QZAuth = QZAuth;

})(window);