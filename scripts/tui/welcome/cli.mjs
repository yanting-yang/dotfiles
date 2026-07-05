#!/usr/bin/env node

import React from 'react';
import {render} from 'ink';
import {App} from './app.mjs';
import {loadTools, plainToolSummary} from './io.mjs';

const h = React.createElement;
const ENTER_ALT_SCREEN = '\u001B[?1049h\u001B[2J\u001B[H';
const EXIT_ALT_SCREEN = '\u001B[?1049l';

let altScreenActive = false;

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

function exitFromSignal(signal) {
    exitAltScreen();
    process.exit(signal === 'SIGINT' ? 130 : 143);
}

if (!process.stdin.isTTY || !process.stdout.isTTY) {
    const data = await loadTools(process.env.WELCOME_INCLUDE_UPDATES === '1');
    console.log(plainToolSummary(data));
    process.exit(0);
}

process.once('exit', exitAltScreen);
process.once('SIGINT', () => exitFromSignal('SIGINT'));
process.once('SIGTERM', () => exitFromSignal('SIGTERM'));

try {
    enterAltScreen();
    const instance = render(h(App));
    await instance.waitUntilExit();
} finally {
    exitAltScreen();
}
