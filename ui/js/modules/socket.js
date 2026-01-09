'use strict';

const SocketModule = (() => {
    // Embedded browsers don't support window.postMessage to Lua
    // They must use fetch to bolt-api just like overlay browsers
    function sendToLua(data) {
        try {
            fetch('https://bolt-api/send-message', {
                method: 'POST',
                body: JSON.stringify(data)
            }).catch(err => console.error('Failed to send to Lua:', err));
        } catch (error) {
            console.error('Failed to send to Lua:', error);
        }
    }

    return {
        sendToLua
    };
})();

export default SocketModule;
