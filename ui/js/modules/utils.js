'use strict';

export function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

export function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

export function createPaletteSignature(palette) {
    if (!palette || palette.length === 0) {
        return 'empty';
    }
    return palette.map((entry) => `${entry.index}:${entry.name || ''}:${entry.hex || ''}`).join('|');
}
