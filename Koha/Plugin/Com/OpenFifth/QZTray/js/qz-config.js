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
         * Get the current register ID from form fields
         */
        getCurrentRegister: function() {
            // 1. Check for register in form select dropdown
            var registerSelect = document.getElementById('registerid');
            if (registerSelect && registerSelect.value) {
                return registerSelect.value;
            }

            // 2. Check for register in hidden form fields
            var hiddenRegister = document.querySelector('input[name="registerid"]');
            if (hiddenRegister && hiddenRegister.value) {
                return hiddenRegister.value;
            }

            // 3. Fall back to session context register
            return this.currentRegister;
        },

        /**
         * Get the appropriate printer for the current context
         */
        getPrinter: function() {
            // Get the actual current register (from form or session)
            var activeRegister = this.getCurrentRegister();
            if (window.qzConfig.debugMode) {
                console.log('QZ Tray Config: Active register:', activeRegister);
                console.log('QZ Tray Config: Register mappings:', this.registerMappings);
            }

            // If we have an active register and a specific mapping for it, use that
            if (activeRegister && this.registerMappings[activeRegister]) {
                var printer = this.registerMappings[activeRegister];
                if (window.qzConfig.debugMode) {
                    console.log('QZ Tray Config: Mapped printer for register', activeRegister + ':', printer);
                }
                return printer;
            }

            // Otherwise, return empty string to use system default
            if (window.qzConfig.debugMode) {
                console.log('QZ Tray Config: No mapping found, using system default');
            }
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