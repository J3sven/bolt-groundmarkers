'use strict';

import State from './state.js';
import Socket from './socket.js';
import Notifications from './notify.js';
import Modal from './modal.js';
import { escapeHtml, clamp } from './utils.js';

const LayoutsModule = (() => {
    const listElement = document.getElementById('layout-list');
    const layoutNameInput = document.getElementById('layout-name');
    const saveButton = document.getElementById('save-button');
    const importButton = document.getElementById('import-layout-button');
    const activeLayoutLabel = document.getElementById('active-layout');
    const saveHelp = document.getElementById('save-help');

    function init() {
        if (listElement) {
            listElement.addEventListener('change', handleToggleChange);
            listElement.addEventListener('click', handleActionClick);
        }

        if (layoutNameInput) {
            layoutNameInput.addEventListener('input', refreshSaveState);
        }

        if (saveButton) {
            saveButton.addEventListener('click', saveLayout);
        }

        if (importButton) {
            importButton.addEventListener('click', openImportModal);
        }
    }

    function refreshSaveState() {
        if (!layoutNameInput || !saveButton || !saveHelp) {
            return;
        }

        const state = State.getState();
        const name = layoutNameInput.value.trim();

        if (!state.inInstance) {
            saveHelp.textContent = 'Enter an instance and mark some tiles to save a layout.';
        } else if (state.tempTileCount === 0) {
            saveHelp.textContent = 'Mark some tiles (Alt+MiddleClick) before saving.';
        } else {
            saveHelp.textContent = `You have ${state.tempTileCount} temporary tile(s) ready to save.`;
        }

        saveButton.disabled = !state.inInstance || state.tempTileCount === 0 || !name;
    }

    function saveLayout() {
        if (!layoutNameInput) {
            return;
        }
        const name = layoutNameInput.value.trim();
        if (!name) {
            Notifications.showNotification('Enter a layout name first.', 'warning');
            return;
        }

        const state = State.getState();
        if (!state.inInstance) {
            Notifications.showNotification('Enter an instance before saving layouts.', 'warning');
            return;
        }

        if (state.tempTileCount === 0) {
            Notifications.showNotification('Mark some tiles before saving.', 'warning');
            return;
        }

        Socket.sendToLua({ action: 'save_layout', name });
        layoutNameInput.value = '';
        refreshSaveState();
        Notifications.showNotification(`Saving layout "${name}"...`, 'info');
    }

    function renderLayouts() {
        const state = State.getState();
        if (activeLayoutLabel) {
            const activeLayout = state.layouts.find((layout) => layout.id === state.activeLayoutId);
            activeLayoutLabel.textContent = activeLayout
                ? (activeLayout.displayName || activeLayout.name || 'Layout')
                : 'None';
        }

        if (!listElement) {
            return;
        }

        if (state.layouts.length === 0) {
            listElement.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">📍</div>
                    <p>No saved layouts yet</p>
                </div>
            `;
            return;
        }

        listElement.innerHTML = state.layouts.map((layout) => {
            const isActive = layout.id === state.activeLayoutId;
            const tileCount = layout.tiles ? layout.tiles.length : 0;
            const displayName = escapeHtml(layout.displayName || layout.name || 'Layout');

            return `
                <div class="layout-item ${isActive ? 'active' : ''}" data-id="${layout.id}">
                    <div class="layout-header">
                        <div class="layout-meta">
                            <div class="layout-name">${displayName}</div>
                            <div class="layout-info">
                                ${tileCount} tile${tileCount !== 1 ? 's' : ''}
                            </div>
                        </div>
                        <div class="layout-controls">
                            <label class="toggle-switch">
                                <input type="checkbox" data-layout-id="${layout.id}" ${isActive ? 'checked' : ''}>
                                <span class="toggle-track"></span>
                                <span class="toggle-label">${isActive ? 'Active' : 'Inactive'}</span>
                            </label>
                            <button type="button" class="icon-button" data-action="export" data-layout-id="${layout.id}" title="Copy layout JSON" aria-label="Copy layout JSON">
                                <img src="svg/copy.svg" alt="">
                            </button>
                            <button type="button" class="icon-button danger" data-action="delete" data-layout-id="${layout.id}" title="Delete layout" aria-label="Delete layout">
                                <img src="svg/delete.svg" alt="">
                            </button>
                        </div>
                    </div>
                </div>
            `;
        }).join('');
    }

    function handleToggleChange(event) {
        const checkbox = event.target.closest('input[type="checkbox"][data-layout-id]');
        if (!checkbox) {
            return;
        }

        const layoutId = checkbox.dataset.layoutId;
        if (!layoutId) {
            return;
        }

        if (checkbox.checked) {
            Socket.sendToLua({
                action: 'activate_layout',
                layoutId
            });
        } else {
            if (State.getState().activeLayoutId === layoutId) {
                Socket.sendToLua({ action: 'deactivate_layout' });
            } else {
                checkbox.checked = true;
            }
        }
    }

    function handleActionClick(event) {
        const actionButton = event.target.closest('button[data-action]');
        if (!actionButton) {
            return;
        }

        const layoutId = actionButton.dataset.layoutId;
        if (!layoutId) {
            return;
        }

        const action = actionButton.dataset.action;
        if (action === 'export') {
            exportLayout(layoutId);
        } else if (action === 'delete') {
            requestDeleteLayout(layoutId);
        }
    }

    async function exportLayout(layoutId) {
        const layout = State.getState().layouts.find((entry) => entry.id === layoutId);
        if (!layout) {
            Notifications.showNotification('Layout not found.', 'error');
            return;
        }

        const payload = {
            version: 1,
            name: layout.name || '',
            displayName: layout.displayName || layout.name || '',
            tiles: Array.isArray(layout.tiles) ? layout.tiles : []
        };

        const jsonString = JSON.stringify(payload);
        const label = payload.displayName || payload.name || 'Layout';

        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(jsonString);
                Notifications.showNotification(`Copied "${label}" to your clipboard.`, 'success');
                return;
            }
            throw new Error('Clipboard unavailable');
        } catch (error) {
            openExportModal(jsonString);
        }
    }

    function openExportModal(jsonString) {
        Modal.open({
            title: 'Export Layout',
            message: 'Copy the JSON below to share this layout.',
            showTextarea: true,
            textareaValue: jsonString,
            textareaReadonly: true,
            focusEnd: true,
            primaryLabel: 'Copy JSON',
            secondaryLabel: 'Close',
            onPrimary: () => {
                const textarea = Modal.textarea;
                if (!textarea) {
                    return;
                }
                textarea.focus();
                textarea.select();
                try {
                    const copied = document.execCommand('copy');
                    if (copied) {
                        Notifications.showNotification('Copied JSON to clipboard.', 'success');
                        Modal.close();
                        return;
                    }
                } catch (error) {
                    // Ignore
                }
                Notifications.showNotification('Press Ctrl+C / Cmd+C to copy.', 'warning');
            }
        });
    }

    function openImportModal() {
        Modal.open({
            title: 'Import Layout',
            message: 'Paste layout JSON below to add it to your list.',
            showTextarea: true,
            textareaValue: '',
            textareaPlaceholder: '{ "version": 1, "name": "Example", "tiles": [...] }',
            textareaReadonly: false,
            primaryLabel: 'Import',
            secondaryLabel: 'Cancel',
            onPrimary: () => {
                const textarea = Modal.textarea;
                if (!textarea) {
                    return;
                }

                const input = textarea.value.trim();
                if (!input) {
                    Notifications.showNotification('Paste layout JSON first.', 'warning');
                    return;
                }

                let parsed;
                try {
                    parsed = JSON.parse(input);
                } catch (error) {
                    Notifications.showNotification('Invalid layout JSON.', 'error');
                    return;
                }

                const tiles = normalizeImportedTiles(parsed.tiles);
                if (tiles.length === 0) {
                    Notifications.showNotification('No valid tiles were found in that layout.', 'error');
                    return;
                }

                Modal.close();

                Socket.sendToLua({
                    action: 'import_layout',
                    layout: {
                        name: typeof parsed.name === 'string' ? parsed.name : '',
                        displayName: typeof parsed.displayName === 'string'
                            ? parsed.displayName
                            : (typeof parsed.prettyName === 'string' ? parsed.prettyName : ''),
                        tiles
                    }
                });

                Notifications.showNotification('Importing layout...', 'info');
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
                localX: clamp(tile.localX, 0, 63),
                localZ: clamp(tile.localZ, 0, 63),
                worldY: Number.isFinite(tile.worldY) ? tile.worldY : 0,
                colorIndex: Number.isFinite(tile.colorIndex) ? clamp(Math.floor(tile.colorIndex), 1, 99) : 1
            }));
    }

    function requestDeleteLayout(layoutId) {
        const layout = State.getState().layouts.find((entry) => entry.id === layoutId);
        const nameLabel = layout ? (layout.displayName || layout.name || 'this layout') : 'this layout';

        Modal.open({
            title: 'Delete Layout',
            message: `Delete "${nameLabel}"? This cannot be undone.`,
            primaryLabel: 'Delete',
            primaryStyle: 'danger',
            secondaryLabel: 'Cancel',
            onPrimary: () => {
                Modal.close();
                Socket.sendToLua({
                    action: 'delete_layout',
                    layoutId
                });
                Notifications.showNotification(`Deleting "${nameLabel}"...`, 'warning');
            }
        });
    }

    function handleImportResult(payload) {
        const type = payload.success ? 'success' : 'error';
        const message = payload.message || (payload.success ? 'Layout imported.' : 'Failed to import layout.');
        Notifications.showNotification(message, type);
    }

    return {
        init,
        renderLayouts,
        refreshSaveState,
        handleImportResult,
        saveLayout,
        openImportModal
    };
})();

export default LayoutsModule;
