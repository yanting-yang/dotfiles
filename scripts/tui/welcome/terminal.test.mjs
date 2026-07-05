import test from 'node:test';
import assert from 'node:assert/strict';
import {
    RESTORE_TERMINAL_TITLE,
    SAVE_TERMINAL_TITLE,
    WELCOME_TERMINAL_TITLE,
    sanitizeTerminalTitle,
    terminalTitleSequence
} from './terminal.mjs';

test('builds sanitized terminal title escape sequences', () => {
    assert.equal(SAVE_TERMINAL_TITLE, '\u001B[22;0t');
    assert.equal(RESTORE_TERMINAL_TITLE, '\u001B[23;0t');
    assert.equal(WELCOME_TERMINAL_TITLE, 'Welcome');
    assert.equal(sanitizeTerminalTitle('hello\u0007\u001Bworld'), 'helloworld');
    assert.equal(terminalTitleSequence('Welcome'), '\u001B]0;Welcome\u0007');
});
