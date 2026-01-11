'use strict';

import State from './state.js';
import Socket from './socket.js';
import { escapeHtml } from './utils.js';

const VIEW_SIZES = [64, 48, 32, 24, 16];

const LayoutEditorModule = (() => {
    const elements = {
        section: document.getElementById('editor-section'),
        container: document.getElementById('editor-grid'),
        help: document.getElementById('editor-help'),
        meta: document.getElementById('editor-grid-meta'),
        colorSelect: document.getElementById('editor-color-select'),
        title: document.getElementById('editor-title'),
        closeButton: document.getElementById('editor-close-button'),
        viewButton: document.getElementById('editor-view-button')
    };

    let zoomIndex = 0;
    let currentLayoutId = null;
    let currentLayout = null;
    let editorSelectedColor = 1;
    let hoverKey = null;

    function init() {
        const { container, colorSelect, closeButton } = elements;
        if (container) {
            container.addEventListener('mouseover', handleHover);
            container.addEventListener('mouseleave', handleLeave);
            container.addEventListener('click', handleClick);
            container.addEventListener('wheel', handleWheel, { passive: false });
        }
        if (colorSelect) {
            colorSelect.addEventListener('change', handleColorChange);
        }
        if (closeButton) {
            closeButton.addEventListener('click', closeEditor);
        }
    }

    function handleColorChange() {
        const { colorSelect } = elements;
        if (!colorSelect) {
            return;
        }
        const parsed = Number(colorSelect.value);
        if (!Number.isNaN(parsed)) {
            editorSelectedColor = parsed;
            render();
        }
    }

    function resetHover(shouldNotify) {
        const { container } = elements;
        if (!hoverKey) {
            return;
        }

        if (container) {
            const active = container.querySelector('.grid-cell.hover');
            if (active) {
                active.classList.remove('hover');
            }
        }

        hoverKey = null;

        if (shouldNotify) {
            Socket.sendToLua({ action: 'hover_layout_tile', clear: true, layoutId: currentLayoutId });
        }
    }

    function handleHover(event) {
        if (!currentLayoutId || !currentLayout) {
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

        const localX = Number(cell.dataset.localX);
        const localZ = Number(cell.dataset.localZ);
        const key = `${localX},${localZ}`;

        if (key === hoverKey) {
            return;
        }

        const active = container.querySelector('.grid-cell.hover');
        if (active) {
            active.classList.remove('hover');
        }

        hoverKey = key;
        cell.classList.add('hover');

        // Send hover notification to Lua
        const isChunkLayout = currentLayout.layoutType === 'chunk';
        const message = {
            action: 'hover_layout_tile',
            layoutId: currentLayoutId,
            localX,
            localZ
        };

        // For chunk layouts, include chunk coordinates
        if (isChunkLayout) {
            const chunkX = Number(cell.dataset.chunkX);
            const chunkZ = Number(cell.dataset.chunkZ);
            if (Number.isFinite(chunkX) && Number.isFinite(chunkZ)) {
                message.chunkX = chunkX;
                message.chunkZ = chunkZ;
            }
        }

        Socket.sendToLua(message);
    }

    function handleLeave() {
        resetHover(true);
    }

    function handleClick(event) {
        if (!currentLayoutId || !currentLayout) {
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

        const localX = Number(cell.dataset.localX);
        const localZ = Number(cell.dataset.localZ);
        const chunkX = Number(cell.dataset.chunkX);
        const chunkZ = Number(cell.dataset.chunkZ);

        if (!Number.isFinite(localX) || !Number.isFinite(localZ)) {
            return;
        }

        const isChunkLayout = currentLayout.layoutType === 'chunk';
        if (isChunkLayout && (!Number.isFinite(chunkX) || !Number.isFinite(chunkZ))) {
            return;
        }

        if ((event.ctrlKey || event.metaKey) && cell.classList.contains('marked')) {
            event.preventDefault();
            // Open label editor for this tile
            Socket.sendToLua({
                action: 'open_layout_tile_label_editor',
                layoutId: currentLayoutId,
                localX,
                localZ,
                chunkX: isChunkLayout ? chunkX : undefined,
                chunkZ: isChunkLayout ? chunkZ : undefined
            });
            return;
        }

        // Toggle tile in layout
        Socket.sendToLua({
            action: 'toggle_layout_tile',
            layoutId: currentLayoutId,
            localX,
            localZ,
            chunkX: isChunkLayout ? chunkX : undefined,
            chunkZ: isChunkLayout ? chunkZ : undefined,
            colorIndex: editorSelectedColor
        });
    }

    function handleWheel(event) {
        if (!currentLayoutId) {
            return;
        }

        if (!event.deltaY) {
            return;
        }

        // Always prevent default and stop propagation to avoid page scrolling
        event.preventDefault();
        event.stopPropagation();

        if (event.shiftKey) {
            handleHeightScroll(event);
            return;
        }

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

    function handleHeightScroll(event) {
        const { container } = elements;
        if (!container || !currentLayoutId || !currentLayout) {
            return;
        }

        const cell = event.target.closest('.grid-cell');
        if (!cell || !container.contains(cell) || !cell.classList.contains('marked')) {
            return;
        }

        event.preventDefault();

        const direction = Math.sign(event.deltaY) > 0 ? -1 : 1;
        const localX = Number(cell.dataset.localX);
        const localZ = Number(cell.dataset.localZ);
        const chunkX = Number(cell.dataset.chunkX);
        const chunkZ = Number(cell.dataset.chunkZ);

        const isChunkLayout = currentLayout.layoutType === 'chunk';

        Socket.sendToLua({
            action: 'adjust_layout_tile_height',
            layoutId: currentLayoutId,
            localX,
            localZ,
            chunkX: isChunkLayout ? chunkX : undefined,
            chunkZ: isChunkLayout ? chunkZ : undefined,
            direction
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
            editorSelectedColor = 1;
            colorSelect.innerHTML = '<option>No colors available</option>';
            colorSelect.disabled = true;
            return;
        }

        const hasSelection = palette.some((entry) => entry.index === editorSelectedColor);
        if (!hasSelection) {
            const fallback = palette.find((entry) => entry.index === State.getState().currentColorIndex) || palette[0];
            if (fallback) {
                editorSelectedColor = fallback.index;
            }
        }

        const optionsHtml = palette.map((entry) => {
            const label = entry.name || `Color ${entry.index}`;
            return `<option value="${entry.index}">${label}</option>`;
        }).join('');

        colorSelect.innerHTML = optionsHtml;
        colorSelect.disabled = false;
        colorSelect.value = String(editorSelectedColor);
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

    function openEditor(layoutId, layout) {
        if (!layout) {
            return;
        }

        currentLayoutId = layoutId;
        currentLayout = layout;
        zoomIndex = 0;
        hoverKey = null;

        // Show editor view button and switch to editor view
        if (elements.viewButton) {
            elements.viewButton.style.display = '';
            elements.viewButton.click();
        }

        // Update title
        if (elements.title) {
            const displayName = escapeHtml(layout.displayName || layout.name || 'Layout');
            elements.title.textContent = `Editing: ${displayName}`;
        }

        // Sync color palette
        const palette = State.getState().palette || [];
        syncSelectedColor(palette);

        render();
    }

    function closeEditor() {
        currentLayoutId = null;
        currentLayout = null;
        hoverKey = null;

        // Hide editor view button and switch to layouts view
        if (elements.viewButton) {
            elements.viewButton.style.display = 'none';
        }

        // Switch to layouts view
        const layoutsButton = document.querySelector('.view-button[data-view="layouts"]');
        if (layoutsButton) {
            layoutsButton.click();
        }
    }

    function render() {
        const { section, container, help, meta } = elements;
        if (!section || !container) {
            return;
        }

        if (!currentLayoutId || !currentLayout) {
            container.innerHTML = '';
            if (help) {
                help.textContent = 'No layout loaded.';
            }
            if (meta) {
                meta.textContent = 'Layout Editor';
            }
            return;
        }

        const state = State.getState();
        const chunkGrid = state.chunkGrid;

        const chunkSize = 64;
        const viewSize = getViewSize(chunkSize);

        // Get player position from chunk grid if available
        const playerLocalX = chunkGrid && Number.isFinite(chunkGrid.playerLocalX) ? chunkGrid.playerLocalX : Math.floor(chunkSize / 2);
        const playerLocalZ = chunkGrid && Number.isFinite(chunkGrid.playerLocalZ) ? chunkGrid.playerLocalZ : Math.floor(chunkSize / 2);
        const playerChunkX = chunkGrid && Number.isFinite(chunkGrid.chunkX) ? chunkGrid.chunkX : 0;
        const playerChunkZ = chunkGrid && Number.isFinite(chunkGrid.chunkZ) ? chunkGrid.chunkZ : 0;

        const isChunkLayout = currentLayout.layoutType === 'chunk';

        const viewStartX = getViewportOrigin(playerLocalX, chunkSize, viewSize);
        const viewStartZ = getViewportOrigin(playerLocalZ, chunkSize, viewSize);

        if (help) {
            const palette = state.palette || [];
            const selected = palette.find((entry) => entry.index === editorSelectedColor);
            const colorLabel = selected ? selected.name : `Color ${editorSelectedColor}`;
            const colorCode = selected ? selected.hex : '#ffffff';
            help.innerHTML = `Editing ${isChunkLayout ? 'chunk' : 'instance'} layout tiles using <span style="color: ${colorCode}">${colorLabel}</span>. Scroll to zoom, hover to preview, click to add/remove tiles, <strong>Ctrl+Click</strong> a tile to edit its label, and <strong>Shift+Scroll</strong> over a tile to adjust its height.`;
        }

        if (meta) {
            const tileCount = currentLayout.tiles ? currentLayout.tiles.length : 0;
            let locationInfo = '';
            if (chunkGrid && chunkGrid.enabled) {
                if (isChunkLayout) {
                    locationInfo = `Chunk (${playerChunkX}, ${playerChunkZ}) • `;
                } else {
                    locationInfo = `Local (${playerLocalX}, ${playerLocalZ}) • `;
                }
            }
            const zoomFactor = chunkSize / viewSize;
            const zoomLabelValue = viewSize === chunkSize
                ? '1'
                : (Number.isInteger(zoomFactor) ? zoomFactor.toFixed(0) : zoomFactor.toFixed(1));
            const zoomLabel = `Zoom ${zoomLabelValue}×`;
            meta.textContent = `${locationInfo}${tileCount} tile${tileCount !== 1 ? 's' : ''} • ${zoomLabel}`;
        }

        container.style.gridTemplateColumns = `repeat(${viewSize}, minmax(0, 1fr))`;

        // Build tile set from layout
        const layoutTiles = currentLayout.tiles || [];
        const markedSet = new Set();
        const labelMap = new Map();

        for (const tile of layoutTiles) {
            if (typeof tile.localX !== 'number' || typeof tile.localZ !== 'number') {
                continue;
            }

            let key;
            if (isChunkLayout) {
                // For chunk layouts, filter to current chunk only
                if (tile.chunkX === playerChunkX && tile.chunkZ === playerChunkZ) {
                    key = `${tile.localX},${tile.localZ}`;
                }
            } else {
                // For instance layouts, show all tiles
                key = `${tile.localX},${tile.localZ}`;
            }

            if (key) {
                markedSet.add(key);
                if (tile.label) {
                    labelMap.set(key, tile.label);
                }
            }
        }

        let html = '';
        for (let displayZ = 0; displayZ < viewSize; displayZ++) {
            const localZ = viewStartZ + viewSize - 1 - displayZ;
            for (let offsetX = 0; offsetX < viewSize; offsetX++) {
                const localX = viewStartX + offsetX;
                const key = `${localX},${localZ}`;
                const classes = ['grid-cell'];
                const label = labelMap.get(key);

                if (markedSet.has(key)) {
                    classes.push('marked');
                    if (label) {
                        classes.push('has-label');
                    }
                }

                // Show player position if in same chunk (for chunk layouts) or always (for instance layouts)
                const showPlayer = isChunkLayout
                    ? (chunkGrid && chunkGrid.enabled && playerLocalX === localX && playerLocalZ === localZ)
                    : (chunkGrid && chunkGrid.enabled && playerLocalX === localX && playerLocalZ === localZ);

                if (showPlayer) {
                    classes.push('player');
                }

                if (hoverKey === key) {
                    classes.push('hover');
                }

                const labelAttr = label ? ` data-label="${escapeHtml(label)}" title="${escapeHtml(label)}"` : '';
                const chunkAttr = isChunkLayout ? ` data-chunk-x="${playerChunkX}" data-chunk-z="${playerChunkZ}"` : '';
                html += `<div class="${classes.join(' ')}" data-local-x="${localX}" data-local-z="${localZ}"${chunkAttr}${labelAttr}></div>`;
            }
        }

        container.innerHTML = html;
    }

    function updateLayout(layout) {
        if (currentLayoutId === layout.id) {
            currentLayout = layout;
            render();
        }
    }

    return {
        init,
        render,
        openEditor,
        closeEditor,
        updateLayout,
        syncSelectedColor,
        isEditing: () => currentLayoutId !== null,
        getCurrentLayoutId: () => currentLayoutId
    };
})();

export default LayoutEditorModule;
