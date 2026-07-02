/**
 * QZ Tray Printer Picker
 * Lightweight, self-contained modal used when a register has no configured
 * printer mapping and more than one supported printer is detected. Lets the
 * operator choose which printer opens the cash drawer, and optionally remember
 * that choice for the register.
 *
 * Pure vanilla JS with no dependency on Bootstrap's JavaScript — it builds its
 * own overlay so it works regardless of what the host page has loaded.
 */

(function(window) {
    'use strict';

    function QZPrinterPicker() {
        this._active = false;
    }

    QZPrinterPicker.prototype = {
        /**
         * Present the picker.
         *
         * @param {string[]} printers - supported printer names to choose from
         * @returns {Promise<{printer: string, save: boolean}>} resolves with the
         *          chosen printer; rejects with Error('PRINTER_SELECTION_CANCELLED')
         *          if the operator dismisses the dialog.
         */
        pick: function(printers) {
            var self = this;

            return new Promise(function(resolve, reject) {
                if (self._active) {
                    reject(new Error('PRINTER_SELECTION_CANCELLED'));
                    return;
                }
                self._active = true;

                var overlay = document.createElement('div');
                overlay.className = 'qz-picker-overlay';
                overlay.setAttribute('style',
                    'position:fixed;top:0;left:0;right:0;bottom:0;z-index:2050;' +
                    'display:flex;align-items:center;justify-content:center;' +
                    'background:rgba(0,0,0,0.5);');

                var box = document.createElement('div');
                box.className = 'qz-picker-dialog';
                box.setAttribute('style',
                    'background:#fff;color:#000;border-radius:6px;max-width:440px;' +
                    'width:90%;padding:20px;box-shadow:0 4px 24px rgba(0,0,0,0.35);');

                var title = document.createElement('h3');
                title.textContent = 'Select a till printer';
                title.style.marginTop = '0';

                var intro = document.createElement('p');
                intro.className = 'text-muted';
                intro.textContent = 'More than one supported printer was found. Choose which one should open the cash drawer.';

                var select = document.createElement('select');
                select.className = 'form-select form-control';
                select.setAttribute('aria-label', 'Supported printers');
                select.style.width = '100%';
                select.style.marginBottom = '12px';
                printers.forEach(function(name) {
                    var opt = document.createElement('option');
                    opt.value = name;
                    opt.textContent = name;
                    select.appendChild(opt);
                });

                var saveWrap = document.createElement('div');
                saveWrap.style.margin = '4px 0 18px';
                var saveCb = document.createElement('input');
                saveCb.type = 'checkbox';
                saveCb.id = 'qz-picker-save';
                saveCb.checked = true;
                var saveLbl = document.createElement('label');
                saveLbl.htmlFor = 'qz-picker-save';
                saveLbl.textContent = ' Remember this printer for this register';
                saveLbl.style.marginLeft = '6px';
                saveWrap.appendChild(saveCb);
                saveWrap.appendChild(saveLbl);

                var btnRow = document.createElement('div');
                btnRow.style.textAlign = 'right';

                var cancelBtn = document.createElement('button');
                cancelBtn.type = 'button';
                cancelBtn.className = 'btn btn-default btn-secondary';
                cancelBtn.textContent = 'Cancel';
                cancelBtn.style.marginRight = '8px';

                var okBtn = document.createElement('button');
                okBtn.type = 'button';
                okBtn.className = 'btn btn-primary';
                okBtn.textContent = 'Open drawer';

                btnRow.appendChild(cancelBtn);
                btnRow.appendChild(okBtn);

                box.appendChild(title);
                box.appendChild(intro);
                box.appendChild(select);
                box.appendChild(saveWrap);
                box.appendChild(btnRow);
                overlay.appendChild(box);
                document.body.appendChild(overlay);

                // Focus the select so keyboard users land in the dialog.
                try { select.focus(); } catch (e) { /* ignore */ }

                function cleanup() {
                    if (overlay.parentNode) {
                        overlay.parentNode.removeChild(overlay);
                    }
                    self._active = false;
                }

                function cancel() {
                    cleanup();
                    reject(new Error('PRINTER_SELECTION_CANCELLED'));
                }

                cancelBtn.addEventListener('click', cancel);

                okBtn.addEventListener('click', function() {
                    var chosen = select.value;
                    var save = saveCb.checked;
                    cleanup();
                    resolve({ printer: chosen, save: save });
                });

                overlay.addEventListener('keydown', function(e) {
                    if (e.key === 'Escape') {
                        cancel();
                    }
                });
            });
        }
    };

    // Export to global scope
    window.QZPrinterPicker = QZPrinterPicker;

})(window);
