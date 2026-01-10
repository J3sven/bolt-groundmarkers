'use strict';

import State from './state.js';
import Socket from './socket.js';
import Notifications from './notify.js';
import Modal from './modal.js';
import { escapeHtml, clamp } from './utils.js';

const LayoutsModule = (() => {
    const listElement = document.getElementById('layout-list');
    const saveButton = document.getElementById('save-button');
    const importButton = document.getElementById('import-layout-button');
    const activeLayoutLabel = document.getElementById('active-layout');
    const saveHelp = document.getElementById('save-help');
    const saveTitle = document.getElementById('save-title');

    function init() {
        if (listElement) {
            listElement.addEventListener('change', handleToggleChange);
            listElement.addEventListener('click', handleActionClick);
        }

        if (saveButton) {
            saveButton.addEventListener('click', handleSaveClick);
        }

        if (importButton) {
            importButton.addEventListener('click', openImportModal);
        }
    }

    function refreshSaveState() {
        if (!saveButton || !saveHelp) {
            return;
        }

        const state = State.getState();

        // Update based on whether in instance or not
        if (state.inInstance) {
            // Instance mode
            if (saveTitle) {
                saveTitle.textContent = 'Save Instance Layout';
            }

            if (state.tempTileCount === 0) {
                saveHelp.textContent = 'Mark some tiles (Alt+MiddleClick) before saving.';
            } else {
                saveHelp.textContent = `You have ${state.tempTileCount} temporary tile(s) ready to save.`;
            }

            saveButton.disabled = state.tempTileCount === 0;
        } else {
            // Non-instance mode
            if (saveTitle) {
                saveTitle.textContent = 'Save Chunk Layout';
            }

            const nonInstanceTileCount = state.nonInstanceTileCount || 0;

            if (nonInstanceTileCount === 0) {
                saveHelp.textContent = 'Mark some tiles (Alt+MiddleClick) to save as a chunk layout.';
            } else {
                saveHelp.textContent = `You have ${nonInstanceTileCount} unsaved tile(s) ready to save.`;
            }

            saveButton.disabled = nonInstanceTileCount === 0;
        }
    }

    function handleSaveClick() {
        const state = State.getState();

        if (state.inInstance) {
            saveLayout();
        } else {
            saveChunkLayout();
        }
    }

    function saveLayout() {
        const state = State.getState();
        if (!state.inInstance) {
            Notifications.showNotification('Enter an instance before saving layouts.', 'warning');
            return;
        }

        if (state.tempTileCount === 0) {
            Notifications.showNotification('Mark some tiles before saving.', 'warning');
            return;
        }

        // Open overlay for text input
        Socket.sendToLua({ action: 'open_save_overlay' });
    }

    function saveChunkLayout() {
        const state = State.getState();
        if (state.inInstance) {
            Notifications.showNotification('Exit the instance before saving chunk layouts.', 'warning');
            return;
        }

        const nonInstanceTileCount = state.nonInstanceTileCount || 0;
        if (nonInstanceTileCount === 0) {
            Notifications.showNotification('Mark some tiles before saving.', 'warning');
            return;
        }

        // Open overlay for text input
        Socket.sendToLua({ action: 'open_save_chunk_overlay' });
    }

    function renderLayouts() {
        const state = State.getState();
        if (activeLayoutLabel) {
            const activeCount = (state.activeLayoutIds || []).length;
            activeLayoutLabel.textContent = activeCount > 0 ? `${activeCount} active` : 'None';
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
            const isActive = (state.activeLayoutIds || []).includes(layout.id);
            const tileCount = layout.tiles ? layout.tiles.length : 0;
            const displayName = escapeHtml(layout.displayName || layout.name || 'Layout');

            // Determine layout type from the layoutType property
            const isChunkLayout = layout.layoutType === 'chunk';
            const layoutTypeLabel = isChunkLayout ? 'Chunk' : 'Instance';
            const layoutTypeClass = isChunkLayout ? 'layout-type-chunk' : 'layout-type-instance';

            return `
                <div class="layout-item ${isActive ? 'active' : ''} ${layoutTypeClass}" data-id="${layout.id}">
                    <div class="layout-header">
                        <div class="layout-meta">
                            <div class="layout-info">
                                <span class="layout-type-badge">${layoutTypeLabel}</span> ${tileCount} tile${tileCount !== 1 ? 's' : ''}
                            </div>
                            <div class="layout-name">
                                ${displayName}
                            </div>
                        </div>
                        <div class="layout-controls">
                            <label class="toggle-switch">
                                <input type="checkbox" data-layout-id="${layout.id}" ${isActive ? 'checked' : ''}>
                                <span class="toggle-track"></span>
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
            Socket.sendToLua({
                action: 'deactivate_layout',
                layoutId
            });
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

    function exportLayout(layoutId) {
        // Open overlay for export with text display
        Socket.sendToLua({ action: 'open_export_overlay', layoutId: layoutId });
    }

    function openImportModal() {
        // Open overlay for text input
        Socket.sendToLua({ action: 'open_import_overlay' });
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
