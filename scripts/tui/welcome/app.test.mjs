import test from 'node:test';
import assert from 'node:assert/strict';
import {stripVTControlCharacters} from 'node:util';
import React from 'react';
import {renderToString} from 'ink';
import {render} from 'ink-testing-library';
import {App, WelcomePanel} from './app.mjs';

const h = React.createElement;

const NORMAL_ACTION_KEYS = [
    ['arrows', 'move selection'],
    ['Enter', 'install/update selected'],
    ['d/x', 'uninstall selected'],
    ['r', 'refresh local status'],
    ['/', 'commands'],
    ['q/Esc', 'local status or exit']
];

const SLASH_ACTION_KEYS = [
    ['arrows', 'move command'],
    ['Enter', 'run highlighted command'],
    ['type', 'filter commands'],
    ['Backspace', 'edit or close'],
    ['Esc', 'close command menu']
];

function assertActionKeyColumns(frame, rows) {
    const lines = frame.split('\n');
    const positions = rows.map(([key, description]) => {
        const line = lines.find(candidate => candidate.includes('│') && candidate.includes(description));
        assert.ok(line, `missing action-key row: ${key} ${description}`);

        const descriptionStart = line.indexOf(description);
        const divider = line.lastIndexOf('│', descriptionStart);
        const keyStart = line.indexOf(key, divider + 1);
        const gapWidth = descriptionStart - keyStart - key.length;

        assert.ok(divider >= 0, `missing action-panel divider for ${key}`);
        assert.ok(keyStart > divider, `missing action key ${key}`);
        assert.ok(gapWidth >= 2, `expected a readable column gap after ${key}`);
        assert.equal(line.slice(keyStart, descriptionStart).trimEnd(), key);
        return {keyStart, descriptionStart};
    });

    assert.equal(new Set(positions.map(position => position.keyStart)).size, 1);
    assert.equal(new Set(positions.map(position => position.descriptionStart)).size, 1);
}

test('preserves the fixed action panel on narrow terminals', () => {
    for (const width of [60, 30]) {
        const frame = stripVTControlCharacters(renderToString(h(WelcomePanel, {
            inputMode: 'none',
            width,
            height: 10,
            rows: [],
            includeUpdates: false
        }), {columns: width}));
        const lines = frame.split('\n');

        assert.equal(lines.length, 10, `unexpected panel height at ${width} columns`);
        assert.match(lines[0], /^┌.*┐$/);
        assert.match(lines.at(-1), /^└.*┘$/);
        assert.match(frame, /Action keys/);
        assert.match(frame, /d\/x/);
        assert.match(frame, /q\/Esc/);
        assert.match(frame, /Status:/);
        assert.ok(lines.every(line => line.length <= width), `panel overflowed ${width} columns`);
    }
});

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
    assertActionKeyColumns(lastFrame(), NORMAL_ACTION_KEYS);
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
    assert.match(lastFrame(), /\/check\b/);
    assert.match(lastFrame(), /\/help\b/);
    assert.match(lastFrame(), /\/exit\b/);
    assert.doesNotMatch(lastFrame(), /\/updates\b/);
    assert.doesNotMatch(lastFrame(), /\/install\b/);
    assert.doesNotMatch(lastFrame(), /\/update\b/);
    assert.doesNotMatch(lastFrame(), /\/quit\b/);
    assert.doesNotMatch(lastFrame(), /Open Node versions/);
    assert.match(lastFrame(), /Check latest tool versions/);
    assert.match(lastFrame(), /arrows\s+move command/);
    assert.match(lastFrame(), /Enter\s+run highlighted command/);
    assert.match(lastFrame(), /Esc\s+close command menu/);
    assert.doesNotMatch(lastFrame(), /\/node/);
    assert.doesNotMatch(lastFrame(), /\/tools/);
    assert.doesNotMatch(lastFrame(), /\/local/);
    assert.doesNotMatch(lastFrame(), /\/all/);
    assertActionKeyColumns(lastFrame(), SLASH_ACTION_KEYS);
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

test('slash check loads remote tool versions', async () => {
    const includeUpdates = [];
    const loaders = {
        loadTools: async include => {
            includeUpdates.push(include);
            return {kind: 'tools', includeUpdates: include, rows: []};
        }
    };

    const {stdin, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action'
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('/');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 30));

    assert.equal(includeUpdates.at(-1), true);
    unmount();
});

test('arrow selection in slash menu runs highlighted help command', async () => {
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
    stdin.write('\x1B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 30));

    assert.match(lastFrame(), /\/check\s+Check latest tool versions/);
    assert.match(lastFrame(), /\/help\s+Show slash command help/);
    assert.match(lastFrame(), /\/exit\s+Exit welcome/);
    unmount();
});

test('tool selection ignores j/k and moves with arrows', async () => {
    const rows = ['gh', 'tmux'].map(command => ({
        id: command,
        command,
        path: `/usr/bin/${command}`,
        current: '2.0.0',
        latest: '2.1.0',
        status: 'update',
        installer: `/tmp/${command}.sh`,
        actionable: true,
        uninstallable: false
    }));

    const actionAfter = async inputs => {
        let action;
        const loaders = {
            loadTools: async () => ({kind: 'tools', includeUpdates: false, rows})
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
        for (const input of inputs) {
            stdin.write(input);
            await new Promise(resolve => setTimeout(resolve, 20));
        }
        stdin.write('\r');
        await new Promise(resolve => setTimeout(resolve, 30));
        unmount();
        return action;
    };

    for (const inputs of [
        ['j', '\x1B[B'],
        ['k', '\x1B[A']
    ]) {
        assert.deepEqual(await actionAfter(inputs), {
            ACTION: 'install_tool',
            COMMAND: 'tmux',
            INCLUDE_UPDATES: '0',
            VIEW: 'tools'
        });
    }
});
