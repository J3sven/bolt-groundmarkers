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
        layoutNameInput: document.getElementById('layout-name'),
        closeButton: document.querySelector('.close-button')
    };

    let activeView = 'layouts';

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
                activeLayoutId: parsedData.activeLayoutId,
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
