/**
 * QZ Tray Transaction Lock Manager
 * Simple global transaction locking to prevent concurrent operations
 */

(function(window) {
    'use strict';

    // Single source of truth for transaction state
    var transactionInProgress = false;

    var QZTransactionLock = {
        /**
         * Attempt to acquire transaction lock
         * Returns true if lock acquired, false if already locked
         */
        lock: function() {
            if (transactionInProgress) {
                if (window.qzConfig && window.qzConfig.debugMode) {
                    console.warn('QZ Tray: Transaction already in progress');
                }
                return false;
            }

            transactionInProgress = true;

            if (window.qzConfig && window.qzConfig.debugMode) {
                console.log('QZ Tray: Transaction lock acquired');
            }

            return true;
        },

        /**
         * Release transaction lock
         */
        unlock: function() {
            if (window.qzConfig && window.qzConfig.debugMode) {
                console.log('QZ Tray: Transaction lock released');
            }

            transactionInProgress = false;
        },

        /**
         * Check if transaction is currently in progress
         */
        isLocked: function() {
            return transactionInProgress;
        },

        /**
         * Force unlock (use with caution - mainly for error recovery)
         */
        forceUnlock: function() {
            if (window.qzConfig && window.qzConfig.debugMode) {
                console.warn('QZ Tray: Transaction lock force-released');
            }

            transactionInProgress = false;
        }
    };

    // Export to global scope
    window.QZTransactionLock = QZTransactionLock;

})(window);
