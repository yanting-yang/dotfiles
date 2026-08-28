import test from 'node:test';
import assert from 'node:assert/strict';
import {stripVTControlCharacters} from 'node:util';
import React from 'react';
import {renderToString} from 'ink';
import {render} from 'ink-testing-library';
import {App, transcriptLineCount, WelcomePanel} from './app.mjs';

const h = React.createElement;

const NORMAL_ACTION_KEYS = [
    ['arrows', 'move selection'],
    ['Enter', 'choose selected action'],
    ['/', 'commands']
];

const TOOL_ACTION_KEYS = [
    ['arrows', 'move action'],
    ['Enter', 'run highlighted action'],
    ['Esc', 'close action menu']
];

const TOOL_UNINSTALL_KEYS = [
    ['y + Enter', 'confirm uninstall'],
    ['Enter', 'cancel uninstall'],
    ['Esc', 'cancel uninstall']
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
        const line = lines.find(candidate => {
            const descriptionStart = candidate.indexOf(description);
            const divider = candidate.lastIndexOf('│', descriptionStart);
            const keyStart = candidate.indexOf(key, divider + 1);

            return descriptionStart >= 0
                && divider >= 0
                && keyStart > divider
                && keyStart + key.length <= descriptionStart;
        });
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

test('counts explicit transcript lines when sizing the tool table', () => {
    assert.equal(transcriptLineCount([
        {text: 'one'},
        {text: 'two\nthree\nfour'}
    ]), 4);
});

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
        assert.doesNotMatch(frame, /d\/x/);
        assert.match(frame, /Enter/);
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
    assert.match(lastFrame(), /Enter\s+choose selected action/);
    assert.doesNotMatch(lastFrame(), /d\/x/);
    assert.doesNotMatch(lastFrame(), /install\/update selected/);
    assert.doesNotMatch(lastFrame(), /refresh local status/);
    assert.doesNotMatch(lastFrame(), /q\/Esc/);
    assert.doesNotMatch(lastFrame(), /q quit/);
    assert.match(lastFrame(), /type \/ for commands/);
    assertActionKeyColumns(lastFrame(), NORMAL_ACTION_KEYS);
    unmount();
});

test('renders catppuccin as a tmux child in the tool table', async () => {
    const tools = {
        kind: 'tools',
        includeUpdates: true,
        rows: [
            {
                id: 'tmux',
                command: 'tmux',
                path: '/usr/bin/tmux',
                current: '3.5a',
                latest: '3.5a',
                status: 'current',
                installer: '/tmp/tmux.sh',
                actionable: false,
                uninstallable: false
            },
            {
                id: 'cat-tmux',
                command: 'cat-tmux',
                path: '/home/user/.config/tmux/plugins/catppuccin/tmux',
                current: '2.3.0',
                latest: '2.3.0',
                status: 'current',
                installer: '/tmp/catppuccin-tmux.sh',
                actionable: false,
                uninstallable: false
            }
        ]
    };

    const {lastFrame, unmount} = render(h(App, {
        loaders: {loadTools: async () => tools},
        resultFile: '',
        actionFile: '/tmp/unused-action'
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    const frame = lastFrame();
    assert.match(frame, /^\s*>?\s*tmux\b/m);
    assert.match(frame, /└── catppuccin\.tmux/);
    assert.doesNotMatch(frame, /\bcat-tmux\b/);
    unmount();
});

test('renders the LaTeX managed-tool name', async () => {
    const tools = {
        kind: 'tools',
        includeUpdates: false,
        rows: [{
            id: 'latex',
            command: 'latex',
            path: 'not installed',
            current: 'unknown',
            latest: 'unchecked',
            status: 'missing',
            installer: '/tmp/latex.sh',
            actionable: true,
            uninstallable: false
        }]
    };

    const {lastFrame, unmount} = render(h(App, {
        loaders: {loadTools: async () => tools},
        resultFile: '',
        actionFile: '/tmp/unused-action'
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /LaTeX/);
    assert.doesNotMatch(lastFrame(), /^\s*>?\s*latex\b/m);
    unmount();
});

test('renders node as an nvm child in the tool table', async () => {
    const tools = {
        kind: 'tools',
        includeUpdates: true,
        rows: [
            {
                id: 'nvm',
                command: 'nvm',
                path: '/home/user/.config/nvm/nvm.sh (shell function)',
                current: '0.40.3',
                latest: '0.40.3',
                status: 'current',
                installer: '/tmp/nvm.sh',
                actionable: false,
                uninstallable: false
            },
            {
                id: 'node',
                command: 'node',
                path: '/home/user/.config/nvm/versions/node/v24.1.0/bin/node',
                current: '24.1.0',
                latest: '24.2.0',
                status: 'update',
                installer: '',
                actionable: true,
                uninstallable: false
            }
        ]
    };

    const {lastFrame, unmount} = render(h(App, {
        loaders: {loadTools: async () => tools},
        resultFile: '',
        actionFile: '/tmp/unused-action'
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    const frame = lastFrame();
    assert.match(frame, /^\s*>?\s*nvm\b/m);
    assert.match(frame, /└── node\b/);
    unmount();
});

test('shows only the actions available for the selected tool', async () => {
    const cases = [
        {
            row: {
                id: 'code',
                command: 'code',
                path: 'not installed',
                current: 'unknown',
                latest: 'unchecked',
                status: 'missing',
                installer: '/tmp/code.sh',
                actionable: true,
                uninstallable: false
            },
            expected: 'Install code',
            absent: ['Update code', 'Uninstall code']
        },
        {
            row: {
                id: 'node',
                command: 'node',
                path: '/home/user/.config/nvm/versions/node/v24.2.0/bin/node',
                current: '24.2.0',
                latest: '24.3.0',
                status: 'update',
                installer: '',
                actionable: true,
                uninstallable: false
            },
            expected: 'Update node',
            absent: ['Install node', 'Uninstall node']
        },
        {
            row: {
                id: 'tmux',
                command: 'tmux',
                path: '/home/user/.local/bin/tmux',
                current: '3.5a',
                latest: 'unchecked',
                status: 'installed',
                installer: '/tmp/tmux.sh',
                actionable: false,
                uninstallable: true
            },
            expected: 'Uninstall tmux',
            absent: ['Install tmux', 'Update tmux']
        },
        {
            row: {
                id: 'latex',
                command: 'latex',
                path: 'not installed',
                current: 'unknown',
                latest: 'unchecked',
                status: 'missing',
                installer: '/tmp/latex.sh',
                actionable: true,
                uninstallable: false
            },
            expected: 'Install LaTeX \\(TeX Live; full default ~10 GB\\)',
            absent: ['Update LaTeX', 'Uninstall LaTeX']
        }
    ];

    for (const {row, expected, absent} of cases) {
        const loaders = {
            loadTools: async () => ({kind: 'tools', includeUpdates: false, rows: [row]})
        };
        const {lastFrame, stdin, unmount} = render(h(App, {
            loaders,
            resultFile: '',
            actionFile: '/tmp/unused-action'
        }));

        await new Promise(resolve => setTimeout(resolve, 20));
        stdin.write('\r');
        await new Promise(resolve => setTimeout(resolve, 20));

        assert.match(lastFrame(), new RegExp(expected));
        for (const label of absent) {
            assert.doesNotMatch(lastFrame(), new RegExp(label));
        }
        assert.match(lastFrame(), new RegExp(`choose action for ${row.command}`));
        assertActionKeyColumns(lastFrame(), TOOL_ACTION_KEYS);
        unmount();
    }
});

test('runs the selected install and update actions', async () => {
    const rows = [
        {
            id: 'code',
            command: 'code',
            path: 'not installed',
            current: 'unknown',
            latest: 'unchecked',
            status: 'missing',
            installer: '/tmp/code.sh',
            actionable: true,
            uninstallable: false
        },
        {
            id: 'node',
            command: 'node',
            path: '/home/user/.config/nvm/versions/node/v24.2.0/bin/node',
            current: '24.2.0',
            latest: '24.3.0',
            status: 'update',
            installer: '',
            actionable: true,
            uninstallable: false
        }
    ];

    for (const row of rows) {
        let action;
        const loaders = {
            loadTools: async () => ({kind: 'tools', includeUpdates: true, rows: [row]})
        };
        const {stdin, unmount} = render(h(App, {
            loaders,
            resultFile: '',
            actionFile: '/tmp/unused-action',
            initialIncludeUpdates: true,
            writeActionFile: async (_file, nextAction) => {
                action = nextAction;
            }
        }));

        await new Promise(resolve => setTimeout(resolve, 20));
        stdin.write('\r');
        await new Promise(resolve => setTimeout(resolve, 20));
        assert.equal(action, undefined);
        stdin.write('\r');
        await new Promise(resolve => setTimeout(resolve, 30));

        assert.deepEqual(action, {
            ACTION: 'install_tool',
            COMMAND: row.command,
            INCLUDE_UPDATES: '1',
            VIEW: 'tools'
        });
        unmount();
    }
});

test('warns when the selected tool has no available actions', async () => {
    let actionWrites = 0;
    const loaders = {
        loadTools: async () => ({
            kind: 'tools',
            includeUpdates: false,
            rows: [{
                id: 'gh',
                command: 'gh',
                path: '/usr/bin/gh',
                current: '2.0.0',
                latest: 'unchecked',
                status: 'installed',
                installer: '/tmp/gh.sh',
                actionable: false,
                uninstallable: false
            }]
        })
    };
    const {lastFrame, stdin, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action',
        writeActionFile: async () => {
            actionWrites += 1;
        }
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));

    assert.match(lastFrame(), /gh has no available actions/);
    assert.doesNotMatch(lastFrame(), /choose action for gh/);
    assert.equal(actionWrites, 0);
    unmount();
});

test('selects uninstall with arrows and confirms it explicitly', async () => {
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
    stdin.write('x');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.doesNotMatch(lastFrame(), /choose action for gh/);
    assert.doesNotMatch(lastFrame(), /uninstall selected command\? \[y\/N\]/);
    assert.equal(action, undefined);

    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /Update gh/);
    assert.match(lastFrame(), /Uninstall gh/);
    assert.doesNotMatch(lastFrame(), /Install gh/);
    assertActionKeyColumns(lastFrame(), TOOL_ACTION_KEYS);

    stdin.write('\x1B');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.doesNotMatch(lastFrame(), /choose action for gh/);
    assert.equal(action, undefined);

    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\x7f');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /choose action for gh/);
    assert.doesNotMatch(lastFrame(), /Backspace\s+close action menu/);
    assert.equal(action, undefined);

    stdin.write('\x1B');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.doesNotMatch(lastFrame(), /choose action for gh/);
    assert.equal(action, undefined);

    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\x1B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /uninstall selected command\? \[y\/N\]/);
    assertActionKeyColumns(lastFrame(), TOOL_UNINSTALL_KEYS);
    assert.equal(action, undefined);

    stdin.write('\x1B');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.doesNotMatch(lastFrame(), /uninstall selected command\? \[y\/N\]/);
    assert.equal(action, undefined);

    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\x1B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /uninstall selected command\? \[y\/N\]/);

    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /Skipped uninstall/);
    assert.equal(action, undefined);

    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\x1B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
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

test('backspace and Escape close the slash prompt', async () => {
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
    assert.match(lastFrame(), /Enter\s+choose selected action/);

    stdin.write('/');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\x1B');
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.doesNotMatch(lastFrame(), /Check latest tool versions/);
    assert.match(lastFrame(), /type \/ for commands/);
    unmount();
});

test('slash check updates the current table without adding a back level', async () => {
    const includeUpdates = [];
    const localRows = [
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
        },
        {
            id: 'nvim',
            command: 'nvim',
            path: '/usr/bin/nvim',
            current: '0.10.0',
            latest: 'unchecked',
            status: 'installed',
            installer: '/tmp/nvim.sh',
            actionable: false,
            uninstallable: false
        }
    ];
    const checkedRows = [
        {
            ...localRows[0],
            latest: '2.1.0',
            status: 'update',
            actionable: true
        },
        {
            ...localRows[1],
            latest: '0.11.0',
            status: 'update',
            actionable: true
        }
    ];
    let resolveRemote;
    let remoteOnRow;
    let remoteSettled = false;
    let actionWrites = 0;
    const remoteLoad = new Promise(resolve => {
        resolveRemote = resolve;
    });
    remoteLoad.then(() => {
        remoteSettled = true;
    });
    const loaders = {
        loadTools: async (include, onRow) => {
            includeUpdates.push(include);
            if (!include) {
                return {
                    kind: 'tools',
                    includeUpdates: false,
                    rows: localRows
                };
            }

            remoteOnRow = onRow;
            return remoteLoad;
        }
    };
    const remoteResult = {
        kind: 'tools',
        includeUpdates: true,
        rows: checkedRows
    };

    const {lastFrame, stdin, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action',
        writeActionFile: async () => {
            actionWrites += 1;
        }
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    assert.deepEqual(includeUpdates, [false]);
    stdin.write('/');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));

    assert.deepEqual(includeUpdates, [false, true]);
    assert.equal(typeof remoteOnRow, 'function');
    assert.equal(remoteSettled, false);

    remoteOnRow(checkedRows[0]);
    await new Promise(resolve => setTimeout(resolve, 20));

    let frame = stripVTControlCharacters(lastFrame());
    assert.match(frame, /gh\s+update\s+2\.0\.0\s+2\.1\.0/);
    assert.match(frame, /nvim\s+installed\s+0\.10\.0\s+unchecked/);
    assert.match(frame, /Checking latest tool versions\.\.\./);
    assert.doesNotMatch(frame, /Latest tool versions loaded\./);
    assert.doesNotMatch(frame, /Back to local welcome/);
    assert.equal(remoteSettled, false);

    remoteOnRow(checkedRows[1]);
    await new Promise(resolve => setTimeout(resolve, 20));

    frame = stripVTControlCharacters(lastFrame());
    assert.match(frame, /gh\s+update\s+2\.0\.0\s+2\.1\.0/);
    assert.match(frame, /nvim\s+update\s+0\.10\.0\s+0\.11\.0/);
    assert.match(frame, /Checking latest tool versions\.\.\./);
    assert.doesNotMatch(frame, /Latest tool versions loaded\./);
    assert.equal(remoteSettled, false);

    resolveRemote(remoteResult);
    await new Promise(resolve => setTimeout(resolve, 30));

    frame = stripVTControlCharacters(lastFrame());
    assert.equal(remoteSettled, true);
    assert.match(frame, /gh\s+update\s+2\.0\.0\s+2\.1\.0/);
    assert.match(frame, /nvim\s+update\s+0\.10\.0\s+0\.11\.0/);
    assert.doesNotMatch(frame, /Checking latest tool versions\.\.\./);
    assert.match(frame, /Latest tool versions loaded\./);
    assert.match(frame, /remote checked/);
    assert.doesNotMatch(frame, /Back to local welcome/);

    stdin.write('q');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\x1B');
    await new Promise(resolve => setTimeout(resolve, 20));

    assert.deepEqual(includeUpdates, [false, true]);
    frame = stripVTControlCharacters(lastFrame());
    assert.match(frame, /2\.1\.0/);
    assert.match(frame, /remote checked/);

    stdin.write('r');
    await new Promise(resolve => setTimeout(resolve, 30));
    assert.deepEqual(includeUpdates, [false, true]);
    frame = stripVTControlCharacters(lastFrame());
    assert.match(frame, /2\.1\.0/);
    assert.match(frame, /remote checked/);
    assert.equal(actionWrites, 0);
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

test('slash exit ends the session without writing an action', async () => {
    let loads = 0;
    let actionWrites = 0;
    const loaders = {
        loadTools: async () => {
            loads += 1;
            return {kind: 'tools', includeUpdates: false, rows: []};
        }
    };

    const {stdin, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action',
        writeActionFile: async () => {
            actionWrites += 1;
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

    stdin.write('/');
    await new Promise(resolve => setTimeout(resolve, 20));
    stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 30));
    assert.equal(loads, 1);
    assert.equal(actionWrites, 0);
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
        await new Promise(resolve => setTimeout(resolve, 20));
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
