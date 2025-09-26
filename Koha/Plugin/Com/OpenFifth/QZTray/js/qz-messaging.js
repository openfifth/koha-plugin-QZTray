/**
 * QZ Tray Messaging System
 * Handles error reporting and user feedback using Koha's native messaging
 */

(function(window) {
    'use strict';

    function QZMessaging(config) {
        this.config = config;
    }

    QZMessaging.prototype = {
        /**
         * Get or create the transient result element
         */
        _getTransientResultElement: function() {
            return document.getElementById('transient_result');
        },

        /**
         * Replace transient result content with new message
         */
        _replaceTransientResult: function(content) {
            var element = this._getTransientResultElement();
            if (element) {
                element.outerHTML = content;
            }
        },

        /**
         * Show success message to user
         */
        showSuccess: function(message) {
            var element = this._getTransientResultElement();
            if (element) {
                this._replaceTransientResult(
                    '<div id="transient_result" class="alert alert-success">' +
                    message +
                    '</div>'
                );
            } else {
                console.log('Success: ' + message);
            }
        },

        /**
         * Show warning message to user
         */
        showWarning: function(message) {
            var element = this._getTransientResultElement();
            if (element) {
                this._replaceTransientResult(
                    '<div id="transient_result" class="alert alert-warning">' +
                    message +
                    '</div>'
                );
            } else {
                // Fallback to browser alert if transient_result div not found
                alert(message);
            }
        },

        /**
         * Show info message to user
         */
        showInfo: function(message) {
            var element = this._getTransientResultElement();
            if (element) {
                this._replaceTransientResult(
                    '<div id="transient_result" class="alert alert-info">' +
                    message +
                    '</div>'
                );
            } else {
                console.log('Info: ' + message);
            }
        },

        /**
         * Show error message to user
         */
        showError: function(message) {
            var element = this._getTransientResultElement();
            if (element) {
                this._replaceTransientResult(
                    '<div id="transient_result" class="alert alert-danger">' +
                    message +
                    '</div>'
                );
            } else {
                alert(message);
            }
        },

        /**
         * Get user-friendly error message based on error type
         */
        getUserFriendlyErrorMessage: function(error) {
            var userMessage = 'Unable to open cash drawer. Please check QZ Tray connection.';

            if (error && error.message) {
                if (error.message.includes('WebSocket')) {
                    userMessage = 'QZ Tray is not running or not accessible. Please start QZ Tray and try again.';
                } else if (error.message.includes('printer')) {
                    userMessage = 'Printer not found or not accessible. Please check printer configuration.';
                } else if (error.message.includes('Certificate')) {
                    userMessage = 'Certificate authentication failed. Please check plugin configuration.';
                }
            }

            return userMessage;
        },

        /**
         * Log error to server for monitoring
         */
        logError: function(errorDetails) {
            if (!this.config || !this.config.getLogUrl) {
                console.error('QZ Tray Error (no logging configured):', errorDetails);
                return Promise.resolve();
            }

            var logData = {
                error: errorDetails.error || 'Unknown error',
                context: errorDetails.context || 'qztray_operation',
                user_agent: navigator.userAgent,
                page_url: window.location.href
            };

            // Add any additional details
            if (errorDetails.details) {
                Object.assign(logData, errorDetails.details);
            }

            return fetch(this.config.getLogUrl(), {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(logData)
            }).catch(function(logError) {
                console.error('Failed to log error to server:', logError);
                console.error('Original error:', errorDetails);
            });
        },

        /**
         * Handle QZ Tray operation error with comprehensive error reporting and user feedback
         */
        handleQZError: function(error, context) {
            context = context || 'qztray_operation';

            // Log detailed error for monitoring
            this.logError({
                error: 'QZ Tray operation failed: ' + (error.message || error),
                context: context,
                details: {
                    error_type: error.name || 'Unknown',
                    stack: error.stack || 'No stack trace'
                }
            });

            // Show user-friendly message with continuation notice
            var userMessage = this.getUserFriendlyErrorMessage(error);
            userMessage += ' The transaction will continue normally.';
            this.showWarning(userMessage);

            // Also log to console for debugging
            console.error('QZ Tray operation failed:', error);
        }
    };

    // Export to global scope
    window.QZMessaging = QZMessaging;

})(window);