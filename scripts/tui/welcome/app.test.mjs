import test from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import {render} from 'ink-testing-library';
import {App} from './app.mjs';

const h = React.createElement;

test('renders the welcome status rows', async () => {
    const tools = {
        kind: 'tools',
        includeUpdates: false,
        rows: [
            {
                id: 'gh',
                command: 'gh',
                path: '/usr/bin/gh',
                current: '2.0.0',
                latest: 'unchecked',
                status: 'installed',
                installer: '/tmp/gh.sh',
                actionable: false,
                uninstallable: false
            }
        ]
    };

    const loaders = {
        loadTools: async () => tools
    };

    const {lastFrame, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action'
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /Welcome back/);
    assert.match(lastFrame(), /gh/);
    assert.match(lastFrame(), /installed/);
    assert.match(lastFrame(), /Action keys/);
    assert.match(lastFrame(), /Enter\s+install\/update selected/);
    assert.match(lastFrame(), /d\/x\s+uninstall selected/);
    assert.match(lastFrame(), /r\s+refresh local status/);
    assert.match(lastFrame(), /q\/Esc\s+local status or exit/);
    assert.match(lastFrame(), /type \/ for commands/);
    unmount();
});

test('confirms tool uninstall action', async () => {
    let action;
    const tools = {
        kind: 'tools',
        includeUpdates: true,
        rows: [
            {
                id: 'gh',
                command: 'gh',
                path: '/home/user/.local/bin/gh -> /home/user/.local/stow/gh/bin/gh',
                current: '2.0.0',
                latest: '2.1.0',
                status: 'update',
                installer: '/tmp/gh.sh',
                actionable: true,
                uninstallable: true
            }
        ]
    };

    const loaders = {
        loadTools: async () => tools
    };

    const {lastFrame, stdin, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action',
        initialIncludeUpdates: true,
        writeActionFile: async (_file, nextAction) => {
            action = nextAction;
        }
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('d');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /uninstall selected command\? \[y\/N\]/);

    stdin.write('y');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 30));

    assert.deepEqual(action, {
        ACTION: 'uninstall_tool',
        COMMAND: 'gh',
        INCLUDE_UPDATES: '1',
        VIEW: 'tools'
    });
    unmount();
});

test('shows slash command menu with descriptions after typing slash', async () => {
    const tools = {
        kind: 'tools',
        includeUpdates: false,
        rows: []
    };

    const loaders = {
        loadTools: async () => tools
    };

    const {lastFrame, stdin, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action'
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('/');
    await new Promise(resolve => setTimeout(resolve, 20));

    assert.doesNotMatch(lastFrame(), /\/nvm/);
    assert.match(lastFrame(), /\/updates/);
    assert.doesNotMatch(lastFrame(), /Open Node versions/);
    assert.match(lastFrame(), /Check latest tool versions/);
    assert.match(lastFrame(), /arrows\s+move command/);
    assert.match(lastFrame(), /Enter\s+run highlighted command/);
    assert.match(lastFrame(), /Esc\s+close command menu/);
    assert.doesNotMatch(lastFrame(), /\/node/);
    assert.doesNotMatch(lastFrame(), /\/tools/);
    assert.doesNotMatch(lastFrame(), /\/local/);
    assert.doesNotMatch(lastFrame(), /\/all/);
    unmount();
});

test('backspace on empty slash prompt returns to action keys', async () => {
    const loaders = {
        loadTools: async () => ({kind: 'tools', includeUpdates: false, rows: []})
    };

    const {lastFrame, stdin, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action'
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('/');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /Check latest tool versions/);

    stdin.write('\x7f');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.doesNotMatch(lastFrame(), /Check latest tool versions/);
    assert.match(lastFrame(), /type \/ for commands/);
    assert.match(lastFrame(), /Enter\s+install\/update selected/);
    unmount();
});

test('arrow selection in slash menu controls enter command', async () => {
    let action;
    const loaders = {
        loadTools: async () => ({
            kind: 'tools',
            includeUpdates: false,
            rows: [
                {
                    id: 'gh',
                    command: 'gh',
                    path: '/usr/bin/gh',
                    current: '2.0.0',
                    latest: '2.1.0',
                    status: 'update',
                    installer: '/tmp/gh.sh',
                    actionable: true,
                    uninstallable: false
                }
            ]
        })
    };

    const {stdin, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action',
        writeActionFile: async (_file, nextAction) => {
            action = nextAction;
        }
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('/');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\x1B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\x1B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 30));

    assert.deepEqual(action, {
        ACTION: 'install_tool',
        COMMAND: 'gh',
        INCLUDE_UPDATES: '0',
        VIEW: 'tools'
    });
    unmount();
});
