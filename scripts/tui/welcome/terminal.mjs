export const SAVE_TERMINAL_TITLE = '\u001B[22;0t';
export const RESTORE_TERMINAL_TITLE = '\u001B[23;0t';
export const WELCOME_TERMINAL_TITLE = 'Welcome';

export function sanitizeTerminalTitle(title) {
    return String(title ?? '')
        .replace(/[\u0000-\u001F\u007F\u009B]/g, '')
        .slice(0, 120);
}

export function terminalTitleSequence(title) {
    return `\u001B]0;${sanitizeTerminalTitle(title)}\u0007`;
}
