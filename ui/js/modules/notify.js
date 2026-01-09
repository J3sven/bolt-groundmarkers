'use strict';

const NotificationModule = (() => {
    const stack = document.getElementById('notification-stack');

    function showNotification(message, type = 'info', duration = 3200) {
        const fallback = () => console.log(`${type.toUpperCase()}: ${message}`);
        if (!stack) {
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
        stack.appendChild(note);

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

    return {
        showNotification
    };
})();

export default NotificationModule;
