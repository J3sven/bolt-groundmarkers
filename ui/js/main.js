'use strict';

import State from './modules/state.js';
import Socket from './modules/socket.js';
import Modal from './modules/modal.js';
import Settings from './modules/settings.js';
import Layouts from './modules/layouts.js';
import ChunkGrid from './modules/chunk-grid.js';
import LayoutEditor from './modules/layout-editor.js';

(function init() {
    const dom = {
        instanceStatus: document.getElementById('instance-status'),
        tempTiles: document.getElementById('temp-tiles'),
        viewButtons: document.querySelectorAll('.view-button'),
        viewPanels: {
            layouts: document.getElementById('view-layouts'),
            chunk: document.getElementById('view-chunk'),
            editor: document.getElementById('view-editor'),
            settings: document.getElementById('view-settings')
        },
        titleBar: document.querySelector('.title-bar'),
        closeButton: document.querySelector('.close-button')
    };

    let activeView = 'layouts';

    // Setup faster scrolling for embedded browser
    function handleWheel(e) {
        // Don't intercept scrolling on grid elements (they have their own zoom behavior)
        const target = e.target;
        if (target.closest('.chunk-grid') || target.closest('.chunk-grid-wrapper')) {
            return; // Let the grid handle its own wheel events
        }

        // Apply 3x faster scrolling to body
        e.preventDefault();
        window.scrollBy(0, e.deltaY * 3);
    }

    // Apply faster scrolling to window
    window.addEventListener('wheel', handleWheel, { passive: false });

    // Setup window dragging
    if (dom.titleBar) {
        dom.titleBar.addEventListener('mousedown', (e) => {
            // Don't drag if clicking the close button
            if (e.target.classList.contains('close-button')) {
                return;
            }
            fetch('https://bolt-api/start-reposition?h=0&v=0').catch(err => console.error('Failed to start reposition:', err));
        });
    }

    // Setup resize handles
    const resizeHandles = document.querySelectorAll('.resize-handle');
    resizeHandles.forEach(handle => {
        handle.addEventListener('mousedown', (e) => {
            e.preventDefault();
            e.stopPropagation();

            const resizeType = handle.dataset.resize;
            let h = 0, v = 0;

            // Determine h and v based on resize type
            switch (resizeType) {
                case 'top':
                    h = 0; v = -1;
                    break;
                case 'bottom':
                    h = 0; v = 1;
                    break;
                case 'left':
                    h = -1; v = 0;
                    break;
                case 'right':
                    h = 1; v = 0;
                    break;
                case 'top-left':
                    h = -1; v = -1;
                    break;
                case 'top-right':
                    h = 1; v = -1;
                    break;
                case 'bottom-left':
                    h = -1; v = 1;
                    break;
                case 'bottom-right':
                    h = 1; v = 1;
                    break;
            }

            fetch(`https://bolt-api/start-reposition?h=${h}&v=${v}`).catch(err => console.error('Failed to start resize:', err));
        });
    });

    Settings.init();
    Layouts.init();
    ChunkGrid.init();
    LayoutEditor.init();

    setupViewButtons(dom.viewButtons, dom.viewPanels, () => {
        ChunkGrid.resetHover();
    });

    if (dom.closeButton) {
        dom.closeButton.addEventListener('click', () => {
            Socket.sendToLua({ action: 'close' });
        });
    }

    Layouts.refreshSaveState();

    window.addEventListener('message', handleMessage);

    Socket.sendToLua({ action: 'ready' });

    function handleMessage(event) {
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

        if (parsedData.type === 'state_update') {
            const previousState = State.getState();
            State.setState({
                inInstance: parsedData.inInstance,
                tempTileCount: parsedData.tempTileCount,
                nonInstanceTileCount: parsedData.nonInstanceTileCount || 0,
                activeLayoutIds: parsedData.activeLayoutIds || [],
                chunkGrid: parsedData.chunkGrid || null,
                palette: parsedData.palette || [],
                currentColorIndex: parsedData.currentColorIndex || 1,
                layouts: parsedData.layouts || previousState.layouts,
                lineThickness: typeof parsedData.lineThickness === 'number'
                    ? parsedData.lineThickness
                    : previousState.lineThickness,
                showTileLabels: typeof parsedData.showTileLabels === 'boolean'
                    ? parsedData.showTileLabels
                    : previousState.showTileLabels,
                showTileFill: typeof parsedData.showTileFill === 'boolean'
                    ? parsedData.showTileFill
                    : previousState.showTileFill,
                tileFillOpacity: typeof parsedData.tileFillOpacity === 'number'
                    ? parsedData.tileFillOpacity
                    : previousState.tileFillOpacity,
                hideTileConnections: typeof parsedData.hideTileConnections === 'boolean'
                    ? parsedData.hideTileConnections
                    : previousState.hideTileConnections
            });

            updateStatus(dom.instanceStatus, dom.tempTiles);
            ChunkGrid.syncSelectedColor(State.getState().palette);
            ChunkGrid.render();
            LayoutEditor.syncSelectedColor(State.getState().palette);
            LayoutEditor.render();
            Settings.render();
            Layouts.renderLayouts();
            Layouts.refreshSaveState();
        } else if (parsedData.type === 'layouts_update') {
            State.setState({
                layouts: parsedData.layouts || []
            });
            Layouts.renderLayouts();
            // Update editor if currently editing a layout
            if (LayoutEditor.isEditing()) {
                const currentLayoutId = LayoutEditor.getCurrentLayoutId();
                const updatedLayout = (parsedData.layouts || []).find(l => l.id === currentLayoutId);
                if (updatedLayout) {
                    LayoutEditor.updateLayout(updatedLayout);
                }
            }
        } else if (parsedData.type === 'import_result') {
            Layouts.handleImportResult(parsedData);
        } else if (parsedData.type === 'open_layout_editor') {
            const layout = parsedData.layout;
            if (layout) {
                LayoutEditor.openEditor(layout.id, layout);
            }
        }
    }

    function updateStatus(statusEl, tilesEl) {
        const state = State.getState();
        if (statusEl) {
            statusEl.textContent = state.inInstance ? 'In Instance' : 'Not in Instance';
            statusEl.className = 'status-value' + (state.inInstance ? '' : ' warning');
        }

        if (tilesEl) {
            tilesEl.textContent = state.tempTileCount || 0;
        }
    }

    function setupViewButtons(buttons, panels, onLeaveChunk) {
        buttons.forEach((button) => {
            button.addEventListener('click', () => {
                const target = button.dataset.view;
                if (!target || target === activeView || !panels[target]) {
                    return;
                }

                buttons.forEach((btn) => {
                    btn.classList.toggle('active', btn.dataset.view === target);
                });

                Object.entries(panels).forEach(([name, panel]) => {
                    if (panel) {
                        panel.classList.toggle('active', name === target);
                    }
                });

                if (activeView === 'chunk' && target !== 'chunk' && typeof onLeaveChunk === 'function') {
                    onLeaveChunk();
                }

                activeView = target;
            });
        });
    }
})();
