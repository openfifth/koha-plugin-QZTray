/**
 * QZ Tray Page Detection
 * Improved page detection and configuration management
 */

(function(window) {
    'use strict';

    function QZPageDetector() {
        this.pageConfigs = [
            {
                urlPattern: 'pos/pay.pl',
                selector: '#submitbutton',
                drawerButtonText: 'Confirm',
                originalButtonText: 'Commit payment',
                description: 'POS Payment Confirmation'
            },
            {
                urlPattern: 'pos/register.pl',
                selector: '#pos_cashup',
                drawerButtonText: 'Record cashup',
                originalButtonText: 'Continue cashup',
                description: 'POS Register Cashup'
            },
            {
                urlPattern: 'pos/register.pl',
                selector: '#pos_refund_confirm',
                drawerButtonText: 'Refund',
                originalButtonText: 'Commit refund',
                description: 'POS Refund Confirmation'
            },
            {
                urlPattern: 'pos/registers.pl',
                selector: '.cashup_all',
                drawerButtonText: 'Cashup all',
                originalButtonText: 'Continue cashup',
                description: 'All Registers Cashup'
            },
            {
                urlPattern: 'pos/registers.pl',
                selector: 'button[data-register$="Till"]',
                drawerButtonText: 'Start cashup',
                originalButtonText: 'Continue cashup',
                description: 'Individual Register Cashup'
            },
            {
                urlPattern: 'members/boraccount.pl',
                selector: '#borr_payout_confirm',
                drawerButtonText: 'Confirm',
                originalButtonText: 'Commit payout',
                description: 'Member Account Payout'
            },
            {
                urlPattern: 'members/paycollect.pl',
                selector: '#paysubmit',
                drawerButtonText: 'Confirm',
                originalButtonText: 'Commit payment',
                description: 'Member Payment Collection'
            }
        ];
    }

    QZPageDetector.prototype = {
        /**
         * Detect current page and return matching configurations
         */
        detectCurrentPage: function() {
            var currentUrl = window.location.href;
            var matchedConfigs = [];

            this.pageConfigs.forEach(function(config) {
                if (this._matchesUrlPattern(currentUrl, config.urlPattern)) {
                    matchedConfigs.push(config);
                }
            }.bind(this));

            return matchedConfigs;
        },

        /**
         * Check if current URL matches a pattern
         */
        _matchesUrlPattern: function(url, pattern) {
            // Support for both exact substring matching and regex patterns
            if (pattern instanceof RegExp) {
                return pattern.test(url);
            }
            return url.indexOf(pattern) !== -1;
        },

        /**
         * Get configuration for a specific page pattern
         */
        getConfigForPattern: function(urlPattern) {
            return this.pageConfigs.find(function(config) {
                return config.urlPattern === urlPattern;
            });
        },

        /**
         * Add or update page configuration
         */
        addPageConfig: function(config) {
            if (!config.urlPattern || !config.selector) {
                throw new Error('Page configuration must include urlPattern and selector');
            }

            var existingIndex = this.pageConfigs.findIndex(function(existing) {
                return existing.urlPattern === config.urlPattern && existing.selector === config.selector;
            });

            if (existingIndex !== -1) {
                this.pageConfigs[existingIndex] = config;
            } else {
                this.pageConfigs.push(config);
            }
        },

        /**
         * Remove page configuration
         */
        removePageConfig: function(urlPattern, selector) {
            this.pageConfigs = this.pageConfigs.filter(function(config) {
                return !(config.urlPattern === urlPattern && config.selector === selector);
            });
        },

        /**
         * Get all page configurations
         */
        getAllConfigs: function() {
            return this.pageConfigs.slice(); // Return copy to prevent external modification
        },

        /**
         * Check if current page is supported
         */
        isCurrentPageSupported: function() {
            return this.detectCurrentPage().length > 0;
        },

        /**
         * Get debug information about current page
         */
        getDebugInfo: function() {
            var currentUrl = window.location.href;
            var matchedConfigs = this.detectCurrentPage();

            return {
                currentUrl: currentUrl,
                matchedConfigs: matchedConfigs,
                isSupported: matchedConfigs.length > 0,
                availableConfigs: this.getAllConfigs()
            };
        }
    };

    // Export to global scope
    window.QZPageDetector = QZPageDetector;

})(window);