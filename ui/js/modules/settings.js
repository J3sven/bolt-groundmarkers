'use strict';

import State from './state.js';
import Socket from './socket.js';
import Notifications from './notify.js';
import { escapeHtml, createPaletteSignature } from './utils.js';

const SettingsModule = (() => {
    const paletteEditor = document.getElementById('palette-editor');
    const thicknessInput = document.getElementById('line-thickness-input');
    const thicknessDecrease = document.getElementById('thickness-decrease');
    const thicknessIncrease = document.getElementById('thickness-increase');
    const labelToggle = document.getElementById('tile-label-toggle');
    let lastSignature = null;

    function init() {
        initPaletteEditor();
        initLineThickness();
        initLabelToggle();
    }

    function initPaletteEditor() {
        if (!paletteEditor) {
            return;
        }

        // Auto-save on color change
        paletteEditor.addEventListener('change', (event) => {
            const colorInput = event.target.closest('.palette-color-input');
            if (colorInput) {
                const row = colorInput.closest('.palette-row-compact');
                if (row) {
                    const index = Number(row.dataset.index);
                    if (!Number.isNaN(index)) {
                        savePaletteEntry(index);
                    }
                }
            }
        });

        // Auto-save on name blur
        paletteEditor.addEventListener('blur', (event) => {
            const nameInput = event.target.closest('.palette-name-input');
            if (nameInput) {
                const row = nameInput.closest('.palette-row-compact');
                if (row) {
                    const index = Number(row.dataset.index);
                    if (!Number.isNaN(index)) {
                        savePaletteEntry(index);
                    }
                }
            }
        }, true);
    }

    function initLineThickness() {
        if (!thicknessInput || !thicknessDecrease || !thicknessIncrease) {
            return;
        }

        const updateThickness = (newValue) => {
            const thickness = Number(newValue);
            if (thickness < 2 || thickness > 8) {
                return;
            }

            thicknessInput.value = thickness;

            Socket.sendToLua({
                action: 'update_line_thickness',
                thickness: thickness
            });
            Notifications.showNotification(`Line thickness set to ${thickness}`, 'success');
        };

        thicknessDecrease.addEventListener('click', () => {
            const current = Number(thicknessInput.value);
            if (current > 2) {
                updateThickness(current - 1);
            }
        });

        thicknessIncrease.addEventListener('click', () => {
            const current = Number(thicknessInput.value);
            if (current < 8) {
                updateThickness(current + 1);
            }
        });
    }

    function initLabelToggle() {
        if (!labelToggle) {
            return;
        }

        labelToggle.addEventListener('change', () => {
            Socket.sendToLua({
                action: 'set_tile_label_visibility',
                enabled: labelToggle.checked
            });
        });
    }

    function savePaletteEntry(index) {
        if (!paletteEditor) {
            return;
        }

        const row = paletteEditor.querySelector(`.palette-row-compact[data-index="${index}"]`);
        if (!row) {
            return;
        }

        const nameInput = row.querySelector('.palette-name-input');
        const colorInput = row.querySelector('.palette-color-input');
        if (!colorInput || !colorInput.value) {
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
    }

    function renderPalette() {
        if (!paletteEditor) {
            return;
        }

        const palette = State.getState().palette || [];
        if (palette.length === 0) {
            paletteEditor.innerHTML = '<p class="palette-empty">Palette unavailable.</p>';
            lastSignature = 'empty';
            return;
        }

        const signature = createPaletteSignature(palette);
        if (signature === lastSignature && paletteEditor.childElementCount > 0) {
            return;
        }

        lastSignature = signature;

        paletteEditor.innerHTML = palette.map((entry) => {
            const safeName = escapeHtml(entry.name || `Color ${entry.index}`);
            const hex = entry.hex || '#ffffff';
            return `
                <div class="palette-row-compact" data-index="${entry.index}">
                    <input type="color" class="palette-color-input" value="${hex}" aria-label="Pick color for ${safeName}" title="Click to change color">
                    <input type="text" class="palette-name-input" value="${safeName}" placeholder="Color name">
                </div>
            `;
        }).join('');
    }

    function updateLineThickness(thickness) {
        if (thicknessInput && thickness != null) {
            thicknessInput.value = thickness;
        }
    }

    function updateLabelVisibilityToggle(flag) {
        if (labelToggle) {
            labelToggle.checked = !!flag;
        }
    }

    function render() {
        renderPalette();

        // Update line thickness from state if available
        const state = State.getState();
        const lineThickness = state.lineThickness;
        if (lineThickness != null) {
            updateLineThickness(lineThickness);
        }

        updateLabelVisibilityToggle(state.showTileLabels);
    }

    return {
        init,
        render
    };
})();

export default SettingsModule;
