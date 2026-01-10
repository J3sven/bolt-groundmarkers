'use strict';

import State from './modules/state.js';
import Socket from './modules/socket.js';
import Modal from './modules/modal.js';
import Palette from './modules/palette.js';
import Layouts from './modules/layouts.js';
import ChunkGrid from './modules/chunk-grid.js';

(function init() {
    const dom = {
        instanceStatus: document.getElementById('instance-status'),
        tempTiles: document.getElementById('temp-tiles'),
        viewButtons: document.querySelectorAll('.view-button'),
        viewPanels: {
            layouts: document.getElementById('view-layouts'),
            chunk: document.getElementById('view-chunk'),
            palette: document.getElementById('view-palette')
        },
        titleBar: document.querySelector('.title-bar'),
        closeButton: document.querySelector('.close-button')
    };

    let activeView = 'layouts';

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

    Palette.init();
    Layouts.init();
    ChunkGrid.init();

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
            State.setState({
                inInstance: parsedData.inInstance,
                tempTileCount: parsedData.tempTileCount,
                nonInstanceTileCount: parsedData.nonInstanceTileCount || 0,
                activeLayoutIds: parsedData.activeLayoutIds || [],
                chunkGrid: parsedData.chunkGrid || null,
                palette: parsedData.palette || [],
                currentColorIndex: parsedData.currentColorIndex || 1,
                layouts: parsedData.layouts || State.getState().layouts
            });

            updateStatus(dom.instanceStatus, dom.tempTiles);
            ChunkGrid.syncSelectedColor(State.getState().palette);
            ChunkGrid.render();
            Palette.render();
            Layouts.renderLayouts();
            Layouts.refreshSaveState();
        } else if (parsedData.type === 'layouts_update') {
            State.setState({
                layouts: parsedData.layouts || []
            });
            Layouts.renderLayouts();
        } else if (parsedData.type === 'import_result') {
            Layouts.handleImportResult(parsedData);
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
