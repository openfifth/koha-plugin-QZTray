/**
 * QZ Tray Configuration Manager
 * Handles configuration storage and validation
 */

(function(window) {
    'use strict';

    function QZConfig(config) {
        this.apiBase = config.apiBase || '';
        this.registerMappings = config.registerMappings || {};
        this.currentRegister = config.currentRegister || '';
        this.initialized = false;
    }

    QZConfig.prototype = {
        /**
         * Initialize configuration and check certificate status
         */
        initialize: function() {
            if (this.initialized) {
                return Promise.resolve();
            }

            return this.checkCertificateStatus().then(function(status) {
                this.initialized = true;
                return status;
            }.bind(this));
        },

        /**
         * Check if certificates are configured
         */
        checkCertificateStatus: function() {
            return fetch(this.apiBase + '/certificate', {
                method: 'GET',
                credentials: 'same-origin'
            }).then(function(response) {
                if (response.ok) {
                    console.log('QZ Tray certificates: Configured and ready');
                    return { configured: true, message: 'Configured and ready' };
                } else {
                    console.log('QZ Tray certificates: Not configured - operations will require user trust prompts');
                    return { configured: false, message: 'Not configured - operations will require user trust prompts' };
                }
            }).catch(function(error) {
                console.log('QZ Tray certificates: Unable to check configuration status');
                return { configured: false, message: 'Unable to check configuration status', error: error };
            });
        },

        /**
         * Get API endpoint URL
         */
        getApiUrl: function(endpoint) {
            return this.apiBase + endpoint;
        },

        /**
         * Get logging endpoint URL
         */
        getLogUrl: function() {
            return this.apiBase + '/log-error';
        },

        /**
         * Get the appropriate printer for the current context
         */
        getPrinter: function() {
            // If we have a current register and a specific mapping for it, use that
            if (this.currentRegister && this.registerMappings[this.currentRegister]) {
                return this.registerMappings[this.currentRegister];
            }

            // Otherwise, return empty string to use system default
            return '';
        },

        /**
         * Check if configuration is valid
         */
        isValid: function() {
            return !!(this.apiBase && this.initialized);
        }
    };

    // Export to global scope
    window.QZConfig = QZConfig;

})(window);