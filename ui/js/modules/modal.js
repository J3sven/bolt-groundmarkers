'use strict';

const ModalModule = (() => {
    const overlay = document.getElementById('modal-overlay');
    const titleEl = document.getElementById('modal-title');
    const messageEl = document.getElementById('modal-message');
    const textareaEl = document.getElementById('modal-textarea');
    const primaryButton = document.getElementById('modal-primary-button');
    const secondaryButton = document.getElementById('modal-secondary-button');
    const closeButton = document.querySelector('.modal-close');
    let modalState = null;

    function open(config) {
        if (!overlay || !titleEl || !messageEl || !primaryButton || !secondaryButton) {
            return;
        }

        modalState = config || {};
        titleEl.textContent = modalState.title || '';
        messageEl.textContent = modalState.message || '';

        if (textareaEl) {
            if (modalState.showTextarea) {
                textareaEl.classList.remove('hidden');
                textareaEl.value = modalState.textareaValue || '';
                textareaEl.placeholder = modalState.textareaPlaceholder || '';
                textareaEl.readOnly = !!modalState.textareaReadonly;
            } else {
                textareaEl.classList.add('hidden');
                textareaEl.value = '';
                textareaEl.placeholder = '';
            }
        }

        primaryButton.textContent = modalState.primaryLabel || 'Confirm';
        primaryButton.classList.toggle('danger', modalState.primaryStyle === 'danger');

        if (modalState.hideSecondary) {
            secondaryButton.classList.add('hidden');
        } else {
            secondaryButton.classList.remove('hidden');
            secondaryButton.textContent = modalState.secondaryLabel || 'Cancel';
        }

        overlay.classList.remove('hidden');

        const focusTarget = modalState.showTextarea && textareaEl ? textareaEl : primaryButton;
        setTimeout(() => {
            if (focusTarget) {
                focusTarget.focus();
                if (modalState.focusEnd && focusTarget.select) {
                    focusTarget.select();
                }
            }
        }, 30);
    }

    function close() {
        if (!overlay) {
            return;
        }
        overlay.classList.add('hidden');
        modalState = null;
        if (textareaEl) {
            textareaEl.value = '';
            textareaEl.placeholder = '';
        }
    }

    if (primaryButton) {
        primaryButton.addEventListener('click', () => {
            if (modalState && typeof modalState.onPrimary === 'function') {
                modalState.onPrimary();
            } else {
                close();
            }
        });
    }

    if (secondaryButton) {
        secondaryButton.addEventListener('click', () => {
            if (modalState && typeof modalState.onSecondary === 'function') {
                modalState.onSecondary();
            }
            close();
        });
    }

    if (overlay) {
        overlay.addEventListener('click', (event) => {
            if (event.target === overlay) {
                close();
            }
        });
    }

    if (closeButton) {
        closeButton.addEventListener('click', close);
    }

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && modalState) {
            close();
        }
    });

    return {
        open,
        close,
        get textarea() {
            return textareaEl;
        }
    };
})();

export default ModalModule;
