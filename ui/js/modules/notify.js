'use strict';

const NotificationModule = (() => {
    const stack = document.getElementById('notification-stack');
    let activeNotification = null;
    let hideTimeout = null;
    let removeTimeout = null;

    function fallbackLog(message, type) {
        console.log(`${type.toUpperCase()}: ${message}`);
    }

    function clearTimers() {
        if (hideTimeout) {
            clearTimeout(hideTimeout);
            hideTimeout = null;
        }
        if (removeTimeout) {
            clearTimeout(removeTimeout);
            removeTimeout = null;
        }
    }

    function scheduleRemoval(note, duration) {
        const visibleTime = Math.max(600, duration);

        hideTimeout = setTimeout(() => {
            note.style.opacity = '0';
            note.style.transform = 'translateY(-6px)';
        }, visibleTime - 300);

        removeTimeout = setTimeout(() => {
            if (note.parentNode) {
                note.parentNode.removeChild(note);
            }
            activeNotification = null;
            hideTimeout = null;
            removeTimeout = null;
        }, visibleTime);
    }

    function showNotification(message, type = 'info', duration = 3200) {
        if (!stack) {
            fallbackLog(message, type);
            return;
        }

        if (!activeNotification) {
            const note = document.createElement('div');
            note.className = buildClassList(type);
            note.textContent = message;
            stack.appendChild(note);

            activeNotification = note;
            scheduleRemoval(note, duration);
            return;
        }

        clearTimers();
        activeNotification.className = buildClassList(type);
        activeNotification.textContent = message;
        activeNotification.style.opacity = '1';
        activeNotification.style.transform = 'translateY(0)';

        scheduleRemoval(activeNotification, duration);
    }

    function buildClassList(type) {
        const classes = ['notification'];
        if (type && type !== 'info') {
            classes.push(type);
        }
        return classes.join(' ');
    }

    return {
        showNotification
    };
})();

export default NotificationModule;
