'use strict';

const StateModule = (() => {
    const currentState = {
        inInstance: false,
        tempTileCount: 0,
        nonInstanceTileCount: 0,
        activeLayoutIds: [],
        layouts: [],
        chunkGrid: null,
        palette: [],
        currentColorIndex: 1,
        lineThickness: 4,
        showTileLabels: true
    };

    let chunkSelectedColorIndex = 1;
    let chunkGridHoverKey = null;

    function setState(partial) {
        Object.assign(currentState, partial);
    }

    function getState() {
        return currentState;
    }

    function setChunkSelectedColor(index) {
        chunkSelectedColorIndex = index;
    }

    function getChunkSelectedColor() {
        return chunkSelectedColorIndex;
    }

    function setChunkGridHoverKey(key) {
        chunkGridHoverKey = key;
    }

    function getChunkGridHoverKey() {
        return chunkGridHoverKey;
    }

    return {
        setState,
        getState,
        setChunkSelectedColor,
        getChunkSelectedColor,
        setChunkGridHoverKey,
        getChunkGridHoverKey
    };
})();

export default StateModule;
