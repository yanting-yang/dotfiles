#!/usr/bin/env node

import React from 'react';
import {render} from 'ink';
import {App} from './app.mjs';
import {loadTools, plainToolSummary} from './io.mjs';
import {
    RESTORE_TERMINAL_TITLE,
    SAVE_TERMINAL_TITLE,
    WELCOME_TERMINAL_TITLE,
    terminalTitleSequence
} from './terminal.mjs';

const h = React.createElement;
const ENTER_ALT_SCREEN = '\u001B[?1049h\u001B[2J\u001B[H';
const EXIT_ALT_SCREEN = '\u001B[?1049l';

let altScreenActive = false;
let terminalTitleSaved = false;

function enterAltScreen() {
    if (process.env.WELCOME_ALT_SCREEN_ACTIVE === '1') {
        return;
    }

    process.stdout.write(ENTER_ALT_SCREEN);
    altScreenActive = true;
}

function exitAltScreen() {
    if (!altScreenActive) {
        return;
    }

    process.stdout.write(EXIT_ALT_SCREEN);
    altScreenActive = false;
}

function saveTerminalTitle() {
    if (terminalTitleSaved) {
        return;
    }

    process.stdout.write(SAVE_TERMINAL_TITLE);
    terminalTitleSaved = true;
}

function restoreTerminalTitle() {
    if (!terminalTitleSaved) {
        return;
    }

    process.stdout.write(RESTORE_TERMINAL_TITLE);
    terminalTitleSaved = false;
}

function setTerminalTitle(title) {
    process.stdout.write(terminalTitleSequence(title));
}

function cleanupTerminal() {
    exitAltScreen();
    restoreTerminalTitle();
}

function exitFromSignal(signal) {
    cleanupTerminal();
    process.exit(signal === 'SIGINT' ? 130 : 143);
}

if (!process.stdin.isTTY || !process.stdout.isTTY) {
    const data = await loadTools(process.env.WELCOME_INCLUDE_UPDATES === '1');
    console.log(plainToolSummary(data));
    process.exit(0);
}

process.once('exit', cleanupTerminal);
process.once('SIGINT', () => exitFromSignal('SIGINT'));
process.once('SIGTERM', () => exitFromSignal('SIGTERM'));

try {
    saveTerminalTitle();
    setTerminalTitle(WELCOME_TERMINAL_TITLE);
    enterAltScreen();
    const instance = render(h(App));
    await instance.waitUntilExit();
} finally {
    cleanupTerminal();
}
