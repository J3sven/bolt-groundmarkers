'use strict';

import State from './state.js';
import Socket from './socket.js';

const VIEW_SIZES = [64, 48, 32, 24, 16];

const ChunkGridModule = (() => {
    const elements = {
        section: document.getElementById('chunk-grid-section'),
        container: document.getElementById('chunk-grid'),
        help: document.getElementById('chunk-grid-help'),
        meta: document.getElementById('chunk-grid-meta'),
        colorSelect: document.getElementById('chunk-color-select')
    };
    let zoomIndex = 0;

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

        const chunkGrid = State.getState().chunkGrid;
        if (!chunkGrid) {
            return;
        }

        if (!event.deltaY) {
            return;
        }

        if (event.shiftKey) {
            handleHeightScroll(event, chunkGrid);
            return;
        }

        event.preventDefault();
        const direction = Math.sign(event.deltaY);
        if (!direction) {
            return;
        }
        if (direction < 0) {
            zoomIn();
        } else {
            zoomOut();
        }
    }

    function handleHeightScroll(event, chunkGrid) {
        const { container } = elements;
        if (!container) {
            return;
        }

        const cell = event.target.closest('.grid-cell');
        if (!cell || !container.contains(cell) || !cell.classList.contains('marked')) {
            return;
        }

        event.preventDefault();

        const direction = Math.sign(event.deltaY) > 0 ? -1 : 1;

        Socket.sendToLua({
            action: 'adjust_chunk_tile_height',
            localX: Number(cell.dataset.localX),
            localZ: Number(cell.dataset.localZ),
            direction,
            directionLabel: direction < 0 ? 'down' : 'up',
            scope: chunkGrid ? chunkGrid.mode : null
        });
    }

    function zoomIn() {
        if (zoomIndex < VIEW_SIZES.length - 1) {
            zoomIndex++;
            resetHover(true);
            render();
        }
    }

    function zoomOut() {
        if (zoomIndex > 0) {
            zoomIndex--;
            resetHover(true);
            render();
        }
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

    function getViewSize(chunkSize) {
        const size = chunkSize || 64;
        const desired = VIEW_SIZES[Math.min(zoomIndex, VIEW_SIZES.length - 1)];
        return Math.min(size, desired);
    }

    function getViewportOrigin(playerCoord, chunkSize, viewSize) {
        if (!Number.isFinite(playerCoord)) {
            return Math.max(0, Math.floor((chunkSize - viewSize) / 2));
        }
        const half = Math.floor(viewSize / 2);
        const raw = playerCoord - half;
        return Math.max(0, Math.min(chunkSize - viewSize, raw));
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

        const chunkSize = gridData.size || 64;
        const viewSize = getViewSize(chunkSize);
        const playerLocalX = Number.isFinite(gridData.playerLocalX) ? gridData.playerLocalX : Math.floor(chunkSize / 2);
        const playerLocalZ = Number.isFinite(gridData.playerLocalZ) ? gridData.playerLocalZ : Math.floor(chunkSize / 2);
        const viewStartX = getViewportOrigin(playerLocalX, chunkSize, viewSize);
        const viewStartZ = getViewportOrigin(playerLocalZ, chunkSize, viewSize);

        if (help) {
            if (enabled) {
                const modeLabel = gridData.mode === 'instance'
                    ? 'Instance temporary tiles'
                    : 'Tile markers';
                const palette = State.getState().palette || [];
                const selected = palette.find((entry) => entry.index === State.getChunkSelectedColor());
                const colorLabel = selected ? selected.name : `Color ${State.getChunkSelectedColor()}`;
                const colorCode = selected ? selected.hex : '#ffffff';
                help.innerHTML = `Editing ${modeLabel} using <span style="color: ${colorCode}">${colorLabel}</span>. Scroll to zoom, hover to preview tiles, click to mark/unmark, and <strong>Shift+Scroll</strong> over a marked tile to adjust its height. Orange shows where you stand.`;
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
            const zoomFactor = chunkSize / viewSize;
            const zoomLabelValue = viewSize === chunkSize
                ? '1'
                : (Number.isInteger(zoomFactor) ? zoomFactor.toFixed(0) : zoomFactor.toFixed(1));
            const zoomLabel = `Zoom ${zoomLabelValue}×`;
            meta.textContent = `${chunkLabel} • ${localLabel} • ${modeLabel} • ${zoomLabel}`;
        }

        if (!enabled) {
            container.innerHTML = '';
            resetHover(true);
            return;
        }

        container.style.gridTemplateColumns = `repeat(${viewSize}, minmax(0, 1fr))`;

        const marked = gridData.marked || [];
        const markedSet = new Set(
            marked
                .filter((tile) => typeof tile.localX === 'number' && typeof tile.localZ === 'number')
                .map((tile) => `${tile.localX},${tile.localZ}`)
        );

        const layoutTiles = gridData.layoutTiles || [];
        const layoutSet = new Set(
            layoutTiles
                .filter((tile) => typeof tile.localX === 'number' && typeof tile.localZ === 'number')
                .map((tile) => `${tile.localX},${tile.localZ}`)
        );

        let html = '';
        for (let displayZ = 0; displayZ < viewSize; displayZ++) {
            const localZ = viewStartZ + viewSize - 1 - displayZ;
            for (let offsetX = 0; offsetX < viewSize; offsetX++) {
                const localX = viewStartX + offsetX;
                const key = `${localX},${localZ}`;
                const classes = ['grid-cell'];
                if (markedSet.has(key)) {
                    classes.push('marked');
                } else if (layoutSet.has(key)) {
                    classes.push('layout');
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
