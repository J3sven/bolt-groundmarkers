'use strict';

const SocketModule = (() => {
    function sendToLua(data) {
        return fetch('https://bolt-api/send-message', {
            method: 'POST',
            body: JSON.stringify(data)
        }).catch((error) => {
            console.error('Failed to send to Lua:', error);
        });
    }

    return {
        sendToLua
    };
})();

export default SocketModule;
