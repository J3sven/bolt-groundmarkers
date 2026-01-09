'use strict';

import State from './state.js';
import Socket from './socket.js';
const ChunkGridModule = (() => {
    const elements = {
        section: document.getElementById('chunk-grid-section'),
        container: document.getElementById('chunk-grid'),
        help: document.getElementById('chunk-grid-help'),
        meta: document.getElementById('chunk-grid-meta'),
        colorSelect: document.getElementById('chunk-color-select')
    };

    function init() {
        const { container, colorSelect } = elements;
        if (container) {
            container.addEventListener('mouseover', handleHover);
            container.addEventListener('mouseleave', handleLeave);
            container.addEventListener('click', handleClick);
            container.addEventListener('wheel', handleWheel, { passive: false });
        }
        if (colorSelect) {
            colorSelect.addEventListener('change', handleColorChange);
        }
    }

    function handleColorChange() {
        const { colorSelect } = elements;
        if (!colorSelect) {
            return;
        }
        const parsed = Number(colorSelect.value);
        if (!Number.isNaN(parsed)) {
            State.setChunkSelectedColor(parsed);
            render();
        }
    }

    function isInteractive() {
        const chunkGrid = State.getState().chunkGrid;
        return chunkGrid && chunkGrid.enabled;
    }

    function resetHover(shouldNotify) {
        const { container } = elements;
        const currentKey = State.getChunkGridHoverKey();
        if (!currentKey) {
            return;
        }

        if (container) {
            const active = container.querySelector('.grid-cell.hover');
            if (active) {
                active.classList.remove('hover');
            }
        }

        State.setChunkGridHoverKey(null);
        if (shouldNotify) {
            Socket.sendToLua({ action: 'hover_chunk_tile', clear: true });
        }
    }

    function handleHover(event) {
        if (!isInteractive()) {
            return;
        }

        const { container } = elements;
        if (!container) {
            return;
        }

        const cell = event.target.closest('.grid-cell');
        if (!cell || !container.contains(cell)) {
            return;
        }

        const key = `${cell.dataset.localX},${cell.dataset.localZ}`;
        if (key === State.getChunkGridHoverKey()) {
            return;
        }

        const active = container.querySelector('.grid-cell.hover');
        if (active) {
            active.classList.remove('hover');
        }

        State.setChunkGridHoverKey(key);
        cell.classList.add('hover');

        Socket.sendToLua({
            action: 'hover_chunk_tile',
            localX: Number(cell.dataset.localX),
            localZ: Number(cell.dataset.localZ)
        });
    }

    function handleLeave() {
        resetHover(true);
    }

    function handleClick(event) {
        if (!isInteractive()) {
            return;
        }

        const { container } = elements;
        if (!container) {
            return;
        }

        const cell = event.target.closest('.grid-cell');
        if (!cell || !container.contains(cell)) {
            return;
        }

        const chunkGrid = State.getState().chunkGrid;
        Socket.sendToLua({
            action: 'toggle_chunk_tile',
            localX: Number(cell.dataset.localX),
            localZ: Number(cell.dataset.localZ),
            scope: chunkGrid ? chunkGrid.mode : null,
            colorIndex: State.getChunkSelectedColor()
        });
    }

    function handleWheel(event) {
        if (!isInteractive()) {
            return;
        }

        const { container } = elements;
        if (!container) {
            return;
        }

        const cell = event.target.closest('.grid-cell');
        if (!cell || !container.contains(cell)) {
            return;
        }

        if (!cell.classList.contains('marked')) {
            return;
        }

        if (!event.deltaY) {
            return;
        }

        event.preventDefault();

        const direction = Math.sign(event.deltaY) > 0 ? -1 : 1;
        const chunkGrid = State.getState().chunkGrid;

        Socket.sendToLua({
            action: 'adjust_chunk_tile_height',
            localX: Number(cell.dataset.localX),
            localZ: Number(cell.dataset.localZ),
            direction,
            directionLabel: direction < 0 ? 'down' : 'up',
            scope: chunkGrid ? chunkGrid.mode : null
        });
    }

    function syncSelectedColor(palette) {
        const colorSelect = elements.colorSelect;
        if (!colorSelect) {
            return;
        }

        if (!palette || palette.length === 0) {
            State.setChunkSelectedColor(1);
            colorSelect.innerHTML = '<option>No colors available</option>';
            colorSelect.disabled = true;
            return;
        }

        const currentSelection = State.getChunkSelectedColor();
        const hasSelection = palette.some((entry) => entry.index === currentSelection);
        if (!hasSelection) {
            const fallback = palette.find((entry) => entry.index === State.getState().currentColorIndex) || palette[0];
            if (fallback) {
                State.setChunkSelectedColor(fallback.index);
            }
        }

        const optionsHtml = palette.map((entry) => {
            const label = entry.name || `Color ${entry.index}`;
            return `<option value="${entry.index}">${label}</option>`;
        }).join('');

        colorSelect.innerHTML = optionsHtml;
        colorSelect.disabled = false;
        colorSelect.value = String(State.getChunkSelectedColor());
    }

    function render() {
        const { section, container, help, meta } = elements;
        if (!section || !container) {
            return;
        }

        const gridData = State.getState().chunkGrid;

        if (!gridData || typeof gridData.chunkX === 'undefined' || typeof gridData.chunkZ === 'undefined') {
            section.classList.add('chunk-grid-disabled');
            container.innerHTML = '';
            if (meta) {
                meta.textContent = 'Chunk (--, --)';
            }
            if (help) {
                help.textContent = 'Chunk information unavailable.';
            }
            resetHover(true);
            return;
        }

        const enabled = !!gridData.enabled;
        section.classList.toggle('chunk-grid-disabled', !enabled);

        if (help) {
            if (enabled) {
                const modeLabel = gridData.mode === 'instance'
                    ? 'Instance temporary tiles'
                    : 'Tile markers';
                const palette = State.getState().palette || [];
                const selected = palette.find((entry) => entry.index === State.getChunkSelectedColor());
                const colorLabel = selected ? selected.name : `Color ${State.getChunkSelectedColor()}`;
                const colorCode = selected ? selected.hex : '#ffffff';
                help.innerHTML = `Editing ${modeLabel} using <span style="color: ${colorCode}">${colorLabel}</span>. Hover to preview tiles, click to mark/unmark, and scroll over a marked tile to adjust its height. Orange shows where you stand.`;
            } else {
                help.textContent = 'Chunk information unavailable.';
            }
        }

        if (meta) {
            const chunkLabel = `Chunk (${gridData.chunkX}, ${gridData.chunkZ})`;
            let localLabel = 'Local (--, --)';
            if (typeof gridData.playerLocalX === 'number' && typeof gridData.playerLocalZ === 'number') {
                localLabel = `Local (${gridData.playerLocalX}, ${gridData.playerLocalZ})`;
            }
            const modeLabel = gridData.mode === 'instance' ? 'Instance Tiles' : 'World Markers';
            meta.textContent = `${chunkLabel} • ${localLabel} • ${modeLabel}`;
        }

        if (!enabled) {
            container.innerHTML = '';
            resetHover(true);
            return;
        }

        const size = gridData.size || 64;
        const marked = gridData.marked || [];
        const markedSet = new Set(
            marked
                .filter((tile) => typeof tile.localX === 'number' && typeof tile.localZ === 'number')
                .map((tile) => `${tile.localX},${tile.localZ}`)
        );

        let html = '';
        for (let displayZ = 0; displayZ < size; displayZ++) {
            const localZ = size - 1 - displayZ;
            for (let localX = 0; localX < size; localX++) {
                const key = `${localX},${localZ}`;
                const classes = ['grid-cell'];
                if (markedSet.has(key)) {
                    classes.push('marked');
                }
                if (gridData.playerLocalX === localX && gridData.playerLocalZ === localZ) {
                    classes.push('player');
                }
                if (State.getChunkGridHoverKey() === key) {
                    classes.push('hover');
                }
                html += `<div class="${classes.join(' ')}" data-local-x="${localX}" data-local-z="${localZ}"></div>`;
            }
        }

        container.innerHTML = html;
    }

    return {
        init,
        render,
        syncSelectedColor,
        resetHover: () => resetHover(true)
    };
})();

export default ChunkGridModule;
