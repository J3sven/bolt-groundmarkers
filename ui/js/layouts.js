'use strict';

(() => {
    let currentState = {
        inInstance: false,
        tempTileCount: 0,
        activeLayoutId: null,
        layouts: [],
        chunkGrid: null,
        palette: [],
        currentColorIndex: 1
    };

    const chunkGridSection = document.getElementById('chunk-grid-section');
    const chunkGridContainer = document.getElementById('chunk-grid');
    const chunkGridHelp = document.getElementById('chunk-grid-help');
    const chunkGridMeta = document.getElementById('chunk-grid-meta');
    const chunkColorSelect = document.getElementById('chunk-color-select');
    const paletteEditor = document.getElementById('palette-editor');
    const viewButtons = document.querySelectorAll('.view-button');
    const layoutNameInput = document.getElementById('layout-name');
    let chunkGridHoverKey = null;
    let chunkSelectedColorIndex = 1;
    const viewPanels = {
        layouts: document.getElementById('view-layouts'),
        chunk: document.getElementById('view-chunk'),
        palette: document.getElementById('view-palette')
    };
    let activeView = 'layouts';
    const notificationStack = document.getElementById('notification-stack');
    const modalOverlay = document.getElementById('modal-overlay');
    const modalTitle = document.getElementById('modal-title');
    const modalMessage = document.getElementById('modal-message');
    const modalTextarea = document.getElementById('modal-textarea');
    const modalPrimaryButton = document.getElementById('modal-primary-button');
    const modalSecondaryButton = document.getElementById('modal-secondary-button');
    let modalState = null;
    let lastPaletteSignature = null;

    window.addEventListener('message', (event) => {
        let data = event.data;

        if (data && data.type === 'pluginMessage' && data.content instanceof ArrayBuffer) {
            const decoder = new TextDecoder();
            const jsonString = decoder.decode(data.content);
            try {
                data = JSON.parse(jsonString);
            } catch (e) {
                console.error('Failed to parse decoded message:', jsonString, e);
                return;
            }
        }

        let parsedData = data;
        if (typeof data === 'string') {
            try {
                parsedData = JSON.parse(data);
            } catch (e) {
                console.error('Failed to parse message:', data, e);
                return;
            }
        }

        if (parsedData.type !== 'state_update' || parsedData.debug) {
            console.log('Received:', parsedData.type, parsedData);
        }

        if (parsedData.type === 'state_update') {
            currentState = { ...currentState, ...parsedData };
            currentState.chunkGrid = parsedData.chunkGrid || null;
            currentState.palette = parsedData.palette || currentState.palette;
            currentState.currentColorIndex = parsedData.currentColorIndex || currentState.currentColorIndex || 1;
            syncChunkColorSelection();
            updateUI();
        } else if (parsedData.type === 'layouts_update') {
            currentState.layouts = parsedData.layouts || [];
            updateUI();
        } else if (parsedData.type === 'import_result') {
            handleImportResult(parsedData);
        }
    });

    function showNotification(message, type = 'info', duration = 3200) {
        const fallback = () => console.log(`${type.toUpperCase()}: ${message}`);
        if (!notificationStack) {
            fallback();
            return;
        }
        const note = document.createElement('div');
        const classes = ['notification'];
        if (type && type !== 'info') {
            classes.push(type);
        }
        note.className = classes.join(' ');
        note.textContent = message;
        notificationStack.appendChild(note);
        const visibleTime = Math.max(600, duration);
        setTimeout(() => {
            note.style.opacity = '0';
            note.style.transform = 'translateY(-6px)';
        }, visibleTime - 300);
        setTimeout(() => {
            if (note.parentNode) {
                note.parentNode.removeChild(note);
            }
        }, visibleTime);
    }

    function openModal(config) {
        if (!modalOverlay || !modalTitle || !modalMessage || !modalPrimaryButton || !modalSecondaryButton) {
            return;
        }

        modalState = config || {};

        modalTitle.textContent = modalState.title || '';
        modalMessage.textContent = modalState.message || '';

        if (modalTextarea) {
            if (modalState.showTextarea) {
                modalTextarea.classList.remove('hidden');
                modalTextarea.value = modalState.textareaValue || '';
                modalTextarea.placeholder = modalState.textareaPlaceholder || '';
                modalTextarea.readOnly = !!modalState.textareaReadonly;
            } else {
                modalTextarea.classList.add('hidden');
                modalTextarea.value = '';
                modalTextarea.placeholder = '';
            }
        }

        modalPrimaryButton.textContent = modalState.primaryLabel || 'Confirm';
        modalPrimaryButton.classList.toggle('danger', modalState.primaryStyle === 'danger');

        if (modalState.hideSecondary) {
            modalSecondaryButton.classList.add('hidden');
        } else {
            modalSecondaryButton.classList.remove('hidden');
            modalSecondaryButton.textContent = modalState.secondaryLabel || 'Cancel';
        }

        modalOverlay.classList.remove('hidden');

        const focusTarget = modalState.showTextarea && modalTextarea
            ? modalTextarea
            : modalPrimaryButton;
        setTimeout(() => {
            if (focusTarget) {
                focusTarget.focus();
                if (modalState.focusEnd && focusTarget.select) {
                    focusTarget.select();
                }
            }
        }, 30);
    }

    function closeModal() {
        if (!modalOverlay) {
            return;
        }
        modalOverlay.classList.add('hidden');
        modalState = null;
        if (modalTextarea) {
            modalTextarea.value = '';
            modalTextarea.placeholder = '';
        }
    }

    if (modalPrimaryButton) {
        modalPrimaryButton.addEventListener('click', () => {
            if (modalState && typeof modalState.onPrimary === 'function') {
                modalState.onPrimary();
            } else {
                closeModal();
            }
        });
    }

    if (modalSecondaryButton) {
        modalSecondaryButton.addEventListener('click', () => {
            if (modalState && typeof modalState.onSecondary === 'function') {
                modalState.onSecondary();
            }
            closeModal();
        });
    }

    if (modalOverlay) {
        modalOverlay.addEventListener('click', (event) => {
            if (event.target === modalOverlay) {
                closeModal();
            }
        });
    }

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && modalState) {
            closeModal();
        }
    });

    function updateUI() {
        const statusEl = document.getElementById('instance-status');
        statusEl.textContent = currentState.inInstance ? 'In Instance' : 'Not in Instance';
        statusEl.className = 'status-value' + (currentState.inInstance ? '' : ' warning');

        document.getElementById('temp-tiles').textContent = currentState.tempTileCount || 0;

        const activeLayout = currentState.layouts.find((l) => l.id === currentState.activeLayoutId);
        document.getElementById('active-layout').textContent = activeLayout
            ? (activeLayout.displayName || activeLayout.name || 'Layout')
            : 'None';

        const saveButton = document.getElementById('save-button');
        if (saveButton && layoutNameInput) {
            saveButton.disabled = !currentState.inInstance || currentState.tempTileCount === 0 || !layoutNameInput.value.trim();
        }

        if (!currentState.inInstance) {
            document.getElementById('save-help').textContent = 'Enter an instance and mark some tiles to save a layout.';
        } else if (currentState.tempTileCount === 0) {
            document.getElementById('save-help').textContent = 'Mark some tiles (Alt+MiddleClick) before saving.';
        } else {
            document.getElementById('save-help').textContent = `You have ${currentState.tempTileCount} temporary tile(s) ready to save.`;
        }

        updateChunkGrid();
        updateChunkColorSelect();
        renderPaletteEditor();
        updateLayoutsList();
    }

    function updateLayoutsList() {
        const listContainer = document.getElementById('layout-list');
        if (!listContainer) {
            return;
        }

        if (currentState.layouts.length === 0) {
            listContainer.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">📍</div>
                    <p>No saved layouts yet</p>
                </div>
            `;
            return;
        }

        listContainer.innerHTML = currentState.layouts.map((layout) => {
            const isActive = layout.id === currentState.activeLayoutId;
            const tileCount = layout.tiles ? layout.tiles.length : 0;
            const displayName = layout.displayName || layout.name || 'Layout';
            const safeDisplayName = escapeHtml(displayName);

            return `
                <div class="layout-item ${isActive ? 'active' : ''}" data-id="${layout.id}">
                    <div class="layout-header">
                        <div class="layout-meta">
                            <div class="layout-name">${safeDisplayName}</div>
                            <div class="layout-info">
                                ${tileCount} tile${tileCount !== 1 ? 's' : ''}
                            </div>
                        </div>
                        <div class="layout-controls">
                            <label class="toggle-switch">
                                <input type="checkbox" ${isActive ? 'checked' : ''} onchange="toggleLayout('${layout.id}', this)">
                                <span class="toggle-track"></span>
                            </label>
                            <button type="button" class="icon-button" title="Copy layout JSON" aria-label="Copy layout JSON" onclick="exportLayout('${layout.id}')">
                                <img src="svg/copy.svg" alt="">
                            </button>
                            <button type="button" class="icon-button danger" title="Delete layout" aria-label="Delete layout" onclick="requestDeleteLayout('${layout.id}')">
                                <img src="svg/delete.svg" alt="">
                            </button>
                        </div>
                    </div>
                </div>
            `;
        }).join('');
    }

    function syncChunkColorSelection() {
        const palette = currentState.palette || [];
        if (palette.length === 0) {
            chunkSelectedColorIndex = 1;
            return;
        }

        const hasSelection = palette.some((entry) => entry.index === chunkSelectedColorIndex);
        if (!hasSelection) {
            const fallback = palette.find((entry) => entry.index === currentState.currentColorIndex) || palette[0];
            chunkSelectedColorIndex = fallback.index;
        }
    }

    function getSelectedChunkColorName() {
        const palette = currentState.palette || [];
        const found = palette.find((entry) => entry.index === chunkSelectedColorIndex);
        return found ? found.name : `Color ${chunkSelectedColorIndex}`;
    }

    function getSelectedChunkColorCode() {
        const palette = currentState.palette || [];
        const found = palette.find((entry) => entry.index === chunkSelectedColorIndex);
        return found ? found.hex : '#ffffff';
    }

    function updateChunkColorSelect() {
        if (!chunkColorSelect) {
            return;
        }

        const palette = currentState.palette || [];
        if (palette.length === 0) {
            chunkColorSelect.innerHTML = '<option>No colors available</option>';
            chunkColorSelect.disabled = true;
            return;
        }

        const optionsHtml = palette.map((entry) => {
            const label = escapeHtml(entry.name || `Color ${entry.index}`);
            return `<option value="${entry.index}">${label}</option>`;
        }).join('');

        chunkColorSelect.innerHTML = optionsHtml;
        chunkColorSelect.disabled = false;
        chunkColorSelect.value = String(chunkSelectedColorIndex);
    }

    function getPaletteSignature(palette) {
        if (!palette || palette.length === 0) {
            return 'empty';
        }
        return palette.map((entry) => `${entry.index}:${entry.name || ''}:${entry.hex || ''}`).join('|');
    }

    function renderPaletteEditor() {
        if (!paletteEditor) {
            return;
        }

        const palette = currentState.palette || [];
        if (palette.length === 0) {
            paletteEditor.innerHTML = '<p class="palette-empty">Palette unavailable.</p>';
            lastPaletteSignature = 'empty';
            return;
        }

        const signature = getPaletteSignature(palette);
        if (signature === lastPaletteSignature && paletteEditor.childElementCount > 0) {
            return;
        }
        lastPaletteSignature = signature;

        paletteEditor.innerHTML = palette.map((entry) => {
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

        paletteEditor.querySelectorAll('.palette-save').forEach((button) => {
            button.addEventListener('click', () => {
                savePaletteEntry(Number(button.dataset.index));
            });
        });
    }

    function isChunkGridInteractive() {
        return currentState.chunkGrid && currentState.chunkGrid.enabled;
    }

    function resetChunkGridHover(shouldNotify) {
        const hadHover = !!chunkGridHoverKey;
        if (chunkGridContainer) {
            const active = chunkGridContainer.querySelector('.grid-cell.hover');
            if (active) {
                active.classList.remove('hover');
            }
        }
        if (shouldNotify && hadHover) {
            sendToLua({ action: 'hover_chunk_tile', clear: true });
        }
        chunkGridHoverKey = null;
    }

    function savePaletteEntry(index) {
        if (!paletteEditor) {
            return;
        }

        const row = paletteEditor.querySelector(`.palette-row[data-index="${index}"]`);
        if (!row) {
            return;
        }

        const nameInput = row.querySelector('.palette-name-input');
        const colorInput = row.querySelector('.palette-color-input');
        if (!colorInput || !colorInput.value) {
            showNotification('Pick a color before saving.', 'warning');
            return;
        }

        const hex = colorInput.value.trim();
        if (!/^#[0-9a-fA-F]{6}$/.test(hex)) {
            showNotification('Provide a valid hex color (e.g., #00d4ff).', 'error');
            return;
        }

        sendToLua({
            action: 'update_palette_color',
            index,
            name: nameInput ? nameInput.value.trim() : '',
            color: hex
        });

        showNotification('Palette color updated.', 'success');
    }

    function updateChunkGrid() {
        if (!chunkGridSection || !chunkGridContainer) {
            return;
        }

        const gridData = currentState.chunkGrid;

        if (!gridData || typeof gridData.chunkX === 'undefined' || typeof gridData.chunkZ === 'undefined') {
            chunkGridSection.classList.add('chunk-grid-disabled');
            chunkGridContainer.innerHTML = '';
            if (chunkGridMeta) {
                chunkGridMeta.textContent = 'Chunk (--, --)';
            }
            if (chunkGridHelp) {
                chunkGridHelp.textContent = 'Chunk information unavailable.';
            }
            resetChunkGridHover(true);
            return;
        }

        const enabled = !!gridData.enabled;
        chunkGridSection.classList.toggle('chunk-grid-disabled', !enabled);

        if (chunkGridHelp) {
            if (enabled) {
                const modeLabel = gridData.mode === 'instance' ? 'Instance temporary tiles' : 'Tile markers';
                const colorLabel = getSelectedChunkColorName();
                const colorCode = getSelectedChunkColorCode();
                chunkGridHelp.innerHTML = `Editing ${modeLabel} using <span style="color: ${colorCode}">${colorLabel}</span>. Hover to preview tiles, click to mark/unmark, and scroll over a marked tile to adjust its height. Orange shows where you stand.`;
            } else {
                chunkGridHelp.textContent = 'Chunk information unavailable.';
            }
        }

        if (chunkGridMeta) {
            const chunkLabel = `Chunk (${gridData.chunkX}, ${gridData.chunkZ})`;
            let localLabel = 'Local (--, --)';
            if (typeof gridData.playerLocalX === 'number' && typeof gridData.playerLocalZ === 'number') {
                localLabel = `Local (${gridData.playerLocalX}, ${gridData.playerLocalZ})`;
            }
            const modeLabel = gridData.mode === 'instance' ? 'Instance Tiles' : 'World Markers';
            chunkGridMeta.textContent = `${chunkLabel} • ${localLabel} • ${modeLabel}`;
        }

        if (!enabled) {
            chunkGridContainer.innerHTML = '';
            resetChunkGridHover(true);
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
                if (chunkGridHoverKey === key) {
                    classes.push('hover');
                }
                html += `<div class="${classes.join(' ')}" data-local-x="${localX}" data-local-z="${localZ}"></div>`;
            }
        }

        chunkGridContainer.innerHTML = html;
    }

    function handleChunkGridHover(event) {
        if (!isChunkGridInteractive()) {
            return;
        }

        const cell = event.target.closest('.grid-cell');
        if (!cell || !chunkGridContainer.contains(cell)) {
            return;
        }

        const key = `${cell.dataset.localX},${cell.dataset.localZ}`;
        if (key === chunkGridHoverKey) {
            return;
        }

        const active = chunkGridContainer.querySelector('.grid-cell.hover');
        if (active) {
            active.classList.remove('hover');
        }

        chunkGridHoverKey = key;
        cell.classList.add('hover');

        sendToLua({
            action: 'hover_chunk_tile',
            localX: Number(cell.dataset.localX),
            localZ: Number(cell.dataset.localZ)
        });
    }

    function handleChunkGridLeave() {
        if (!chunkGridHoverKey) {
            return;
        }
        resetChunkGridHover(true);
    }

    function handleChunkGridClick(event) {
        if (!isChunkGridInteractive()) {
            return;
        }

        const cell = event.target.closest('.grid-cell');
        if (!cell || !chunkGridContainer.contains(cell)) {
            return;
        }

        sendToLua({
            action: 'toggle_chunk_tile',
            localX: Number(cell.dataset.localX),
            localZ: Number(cell.dataset.localZ),
            scope: currentState.chunkGrid ? currentState.chunkGrid.mode : null,
            colorIndex: chunkSelectedColorIndex
        });
    }

    function handleChunkGridWheel(event) {
        if (!isChunkGridInteractive()) {
            return;
        }

        const cell = event.target.closest('.grid-cell');
        if (!cell || !chunkGridContainer.contains(cell)) {
            return;
        }

        if (!cell.classList.contains('marked')) {
            return;
        }

        const delta = Math.sign(event.deltaY || 0);
        if (!delta) {
            return;
        }

        event.preventDefault();

        const direction = delta > 0 ? -1 : 1;
        const directionLabel = direction < 0 ? 'down' : 'up';

        sendToLua({
            action: 'adjust_chunk_tile_height',
            localX: Number(cell.dataset.localX),
            localZ: Number(cell.dataset.localZ),
            direction,
            directionLabel,
            scope: currentState.chunkGrid ? currentState.chunkGrid.mode : null
        });
    }

    function saveLayout() {
        const name = layoutNameInput ? layoutNameInput.value.trim() : '';
        if (!name) {
            showNotification('Enter a layout name first.', 'warning');
            return;
        }

        if (!currentState.inInstance) {
            showNotification('Enter an instance before saving layouts.', 'warning');
            return;
        }

        if (currentState.tempTileCount === 0) {
            showNotification('Mark some tiles before saving.', 'warning');
            return;
        }

        sendToLua({ action: 'save_layout', name });
        layoutNameInput.value = '';
        showNotification(`Saving layout "${name}"...`, 'info');
    }

    function activateLayout(layoutId) {
        if (currentState.activeLayoutId === layoutId) {
            return;
        }

        currentState.activeLayoutId = layoutId;
        updateUI();

        sendToLua({
            action: 'activate_layout',
            layoutId
        });
    }

    function deactivateLayout() {
        if (!currentState.activeLayoutId) {
            return false;
        }

        currentState.activeLayoutId = null;
        updateUI();

        sendToLua({ action: 'deactivate_layout' });
        return true;
    }

    function toggleLayout(layoutId, checkboxEl) {
        if (checkboxEl.checked) {
            activateLayout(layoutId);
        } else if (currentState.activeLayoutId === layoutId) {
            deactivateLayout();
        }
    }

    function requestDeleteLayout(layoutId) {
        const target = currentState.layouts.find((layout) => layout.id === layoutId);
        const nameLabel = target ? (target.displayName || target.name || 'this layout') : 'this layout';
        openModal({
            title: 'Delete Layout',
            message: `Delete "${nameLabel}"? This cannot be undone.`,
            primaryLabel: 'Delete',
            primaryStyle: 'danger',
            secondaryLabel: 'Cancel',
            onPrimary: () => {
                closeModal();
                sendToLua({
                    action: 'delete_layout',
                    layoutId
                });
                showNotification(`Deleting "${nameLabel}"...`, 'warning');
            }
        });
    }

    function normalizeImportedTiles(rawTiles) {
        if (!Array.isArray(rawTiles)) {
            return [];
        }

        return rawTiles
            .map((tile) => ({
                localX: Number(tile.localX),
                localZ: Number(tile.localZ),
                worldY: Number(tile.worldY),
                colorIndex: Number(tile.colorIndex)
            }))
            .filter((tile) => Number.isFinite(tile.localX) && Number.isFinite(tile.localZ))
            .map((tile) => ({
                localX: Math.max(0, Math.min(63, Math.floor(tile.localX))),
                localZ: Math.max(0, Math.min(63, Math.floor(tile.localZ))),
                worldY: Number.isFinite(tile.worldY) ? tile.worldY : 0,
                colorIndex: Number.isFinite(tile.colorIndex) ? Math.max(1, Math.floor(tile.colorIndex)) : 1
            }));
    }

    function openImportModal() {
        openModal({
            title: 'Import Layout',
            message: 'Paste layout JSON below to add it to your list.',
            showTextarea: true,
            textareaValue: '',
            textareaPlaceholder: '{ "version": 1, "name": "Example", "tiles": [...] }',
            textareaReadonly: false,
            primaryLabel: 'Import',
            secondaryLabel: 'Cancel',
            onPrimary: () => {
                if (!modalTextarea) {
                    return;
                }
                const input = modalTextarea.value.trim();
                if (!input) {
                    showNotification('Paste layout JSON first.', 'warning');
                    return;
                }

                let parsed;
                try {
                    parsed = JSON.parse(input);
                } catch (error) {
                    showNotification('Invalid layout JSON.', 'error');
                    return;
                }

                const tiles = normalizeImportedTiles(parsed.tiles);
                if (tiles.length === 0) {
                    showNotification('No valid tiles were found in that layout.', 'error');
                    return;
                }

                closeModal();

                sendToLua({
                    action: 'import_layout',
                    layout: {
                        name: typeof parsed.name === 'string' ? parsed.name : '',
                        displayName: typeof parsed.displayName === 'string'
                            ? parsed.displayName
                            : (typeof parsed.prettyName === 'string' ? parsed.prettyName : ''),
                        tiles
                    }
                });

                showNotification('Importing layout...', 'info');
            }
        });
    }

    function openExportModal(jsonString) {
        openModal({
            title: 'Export Layout',
            message: 'Copy the JSON below to share this layout.',
            showTextarea: true,
            textareaValue: jsonString,
            textareaReadonly: true,
            focusEnd: true,
            primaryLabel: 'Copy JSON',
            secondaryLabel: 'Close',
            onPrimary: () => {
                if (!modalTextarea) {
                    return;
                }
                modalTextarea.focus();
                modalTextarea.select();
                try {
                    const copied = document.execCommand('copy');
                    if (copied) {
                        showNotification('Copied JSON to clipboard.', 'success');
                        closeModal();
                        return;
                    }
                } catch (error) {
                    // Ignore
                }
                showNotification('Press Ctrl+C / Cmd+C to copy.', 'warning');
            }
        });
    }

    async function exportLayout(layoutId) {
        const layout = currentState.layouts.find((entry) => entry.id === layoutId);
        if (!layout) {
            showNotification('Layout not found.', 'error');
            return;
        }

        const exportPayload = {
            version: 1,
            name: layout.name || '',
            displayName: layout.displayName || layout.name || '',
            tiles: Array.isArray(layout.tiles) ? layout.tiles : []
        };

        const jsonString = JSON.stringify(exportPayload);
        const label = exportPayload.displayName || exportPayload.name || 'Layout';

        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(jsonString);
                showNotification(`Copied "${label}" to your clipboard.`, 'success');
                return;
            }
            throw new Error('Clipboard API unavailable');
        } catch (error) {
            openExportModal(jsonString);
        }
    }

    function handleImportResult(payload) {
        const type = payload.success ? 'success' : 'error';
        const message = payload.message || (payload.success ? 'Layout imported.' : 'Failed to import layout.');
        showNotification(message, type);
    }

    function switchView(targetView) {
        if (!targetView || targetView === activeView || !viewPanels[targetView]) {
            return;
        }

        viewButtons.forEach((button) => {
            button.classList.toggle('active', button.dataset.view === targetView);
        });

        Object.entries(viewPanels).forEach(([name, panel]) => {
            if (panel) {
                panel.classList.toggle('active', name === targetView);
            }
        });

        activeView = targetView;

        if (activeView !== 'chunk') {
            resetChunkGridHover(true);
        }
    }

    function closeWindow() {
        sendToLua({ action: 'close' });
    }

    function sendToLua(data) {
        fetch('https://bolt-api/send-message', {
            method: 'POST',
            body: JSON.stringify(data)
        }).then(() => {
            console.log('Sent to Lua:', data);
        }).catch((error) => {
            console.error('Failed to send to Lua:', error);
        });
    }

    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    if (chunkGridContainer) {
        chunkGridContainer.addEventListener('mouseover', handleChunkGridHover);
        chunkGridContainer.addEventListener('mouseleave', handleChunkGridLeave);
        chunkGridContainer.addEventListener('click', handleChunkGridClick);
        chunkGridContainer.addEventListener('wheel', handleChunkGridWheel, { passive: false });
    }

    if (chunkColorSelect) {
        chunkColorSelect.addEventListener('change', () => {
            const parsed = Number(chunkColorSelect.value);
            if (!Number.isNaN(parsed)) {
                chunkSelectedColorIndex = parsed;
                updateChunkGrid();
            }
        });
    }

    viewButtons.forEach((button) => {
        button.addEventListener('click', () => {
            const target = button.dataset.view;
            switchView(target);
        });
    });

    if (layoutNameInput) {
        layoutNameInput.addEventListener('input', () => {
            updateUI();
        });
    }

    window.saveLayout = saveLayout;
    window.toggleLayout = toggleLayout;
    window.exportLayout = exportLayout;
    window.requestDeleteLayout = requestDeleteLayout;
    window.openImportModal = openImportModal;
    window.closeModal = closeModal;
    window.closeWindow = closeWindow;

    sendToLua({ action: 'ready' });
})();
