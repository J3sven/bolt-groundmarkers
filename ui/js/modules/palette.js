'use strict';

import State from './state.js';
import Socket from './socket.js';
import Notifications from './notify.js';
import { escapeHtml, createPaletteSignature } from './utils.js';

const PaletteModule = (() => {
    const editor = document.getElementById('palette-editor');
    let lastSignature = null;

    function init() {
        if (!editor) {
            return;
        }

        editor.addEventListener('click', (event) => {
            const button = event.target.closest('.palette-save');
            if (!button) {
                return;
            }
            const index = Number(button.dataset.index);
            if (Number.isNaN(index)) {
                return;
            }
            savePaletteEntry(index);
        });
    }

    function savePaletteEntry(index) {
        if (!editor) {
            return;
        }

        const row = editor.querySelector(`.palette-row[data-index="${index}"]`);
        if (!row) {
            return;
        }

        const nameInput = row.querySelector('.palette-name-input');
        const colorInput = row.querySelector('.palette-color-input');
        if (!colorInput || !colorInput.value) {
            Notifications.showNotification('Pick a color before saving.', 'warning');
            return;
        }

        const hex = colorInput.value.trim();
        if (!/^#[0-9a-fA-F]{6}$/.test(hex)) {
            Notifications.showNotification('Provide a valid hex color (e.g., #00d4ff).', 'error');
            return;
        }

        Socket.sendToLua({
            action: 'update_palette_color',
            index,
            name: nameInput ? nameInput.value.trim() : '',
            color: hex
        });

        Notifications.showNotification('Palette color updated.', 'success');
    }

    function render() {
        if (!editor) {
            return;
        }

        const palette = State.getState().palette || [];
        if (palette.length === 0) {
            editor.innerHTML = '<p class="palette-empty">Palette unavailable.</p>';
            lastSignature = 'empty';
            return;
        }

        const signature = createPaletteSignature(palette);
        if (signature === lastSignature && editor.childElementCount > 0) {
            return;
        }

        lastSignature = signature;

        editor.innerHTML = palette.map((entry) => {
            const safeName = escapeHtml(entry.name || `Color ${entry.index}`);
            const hex = entry.hex || '#ffffff';
            return `
                <div class="palette-row" data-index="${entry.index}">
                    <input type="color" class="palette-color-input" value="${hex}" aria-label="Pick color for ${safeName}">
                    <div class="palette-fields">
                        <label>
                            Name
                            <input type="text" class="palette-name-input" value="${safeName}">
                        </label>
                    </div>
                    <button class="palette-save" data-index="${entry.index}">Save</button>
                </div>
            `;
        }).join('');
    }

    return {
        init,
        render
    };
})();

export default PaletteModule;
