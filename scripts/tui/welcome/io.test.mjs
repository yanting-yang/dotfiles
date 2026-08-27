import test from 'node:test';
import assert from 'node:assert/strict';
import {access, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {loadToolsFromScript, writeAction} from './io.mjs';

async function waitForFile(file) {
    for (let attempt = 0; attempt < 200; attempt += 1) {
        try {
            await access(file);
            return;
        } catch {
            await new Promise(resolve => setTimeout(resolve, 5));
        }
    }

    throw new Error(`Timed out waiting for ${file}`);
}

test('writes KEY=VALUE action files without sourcing semantics', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'welcome-action-'));
    const actionFile = path.join(dir, 'action.env');

    await writeAction(actionFile, {
        ACTION: 'install_tool',
        COMMAND: 'gh',
        NOTE: 'hello\nworld'
    });

    assert.equal(await readFile(actionFile, 'utf8'), 'ACTION=install_tool\nCOMMAND=gh\nNOTE=hello world\n');
    await rm(dir, {recursive: true, force: true});
});

test('streams complete tool rows before the status process exits', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'welcome-status-stream-'));
    const script = path.join(dir, 'status.sh');
    const firstGate = path.join(dir, 'first-gate');
    const secondGate = path.join(dir, 'second-gate');
    const partialReady = path.join(dir, 'partial-ready');
    const gh = {
        id: 'gh',
        command: 'gh',
        path: '/usr/bin/gh',
        current: '2.0.0',
        latest: '2.1.0',
        status: 'update',
        installer: '/tmp/gh.sh',
        actionable: true,
        uninstallable: false
    };
    const nvim = {
        id: 'nvim',
        command: 'nvim',
        path: '/usr/bin/nvim',
        current: '0.9.0',
        latest: '0.10.0',
        status: 'update',
        installer: '/tmp/nvim.sh',
        actionable: true,
        uninstallable: false
    };

    await writeFile(script, `#!/usr/bin/env bash
set -eu
script_dir=$(cd "$(dirname "$0")" && pwd)
printf '%s\\n' '${JSON.stringify({kind: 'tool-row', row: gh})}'
while [ ! -e "$script_dir/first-gate" ]; do sleep 0.01; done
printf '%s' '{"kind":"tool-row","row":{"id":"nvim","command":"nvim","path":"/usr/bin/nvim","current":"0.9.0","latest":"'
: >"$script_dir/partial-ready"
while [ ! -e "$script_dir/second-gate" ]; do sleep 0.01; done
printf '%s\\n' '0.10.0","status":"update","installer":"/tmp/nvim.sh","actionable":true,"uninstallable":false}}'
printf '%s\\n' '{"kind":"tools-complete","includeUpdates":true}'
`);

    const observed = [];
    let firstRowSeen;
    const firstRowPromise = new Promise(resolve => {
        firstRowSeen = resolve;
    });
    let settled = false;
    const loadPromise = loadToolsFromScript(script, true, row => {
        observed.push(row);
        if (observed.length === 1) {
            firstRowSeen();
        }
    });
    loadPromise.then(
        () => {
            settled = true;
        },
        () => {
            settled = true;
        }
    );

    try {
        await Promise.race([
            firstRowPromise,
            loadPromise.then(
                () => assert.fail('status stream completed before the first row was observed'),
                error => {
                    throw error;
                }
            )
        ]);
        assert.deepEqual(observed, [gh]);
        assert.equal(settled, false);

        await writeFile(firstGate, '');
        await waitForFile(partialReady);
        assert.deepEqual(observed, [gh]);
        assert.equal(settled, false);

        await writeFile(secondGate, '');
        const data = await loadPromise;
        assert.deepEqual(observed, [gh, nvim]);
        assert.deepEqual(data, {
            kind: 'tools',
            includeUpdates: true,
            rows: [gh, nvim]
        });
    } finally {
        await writeFile(firstGate, '').catch(() => {});
        await writeFile(secondGate, '').catch(() => {});
        await loadPromise.catch(() => {});
        await rm(dir, {recursive: true, force: true});
    }
});

test('keeps one-shot update output when no progress callback is requested', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'welcome-status-json-'));
    const script = path.join(dir, 'status.sh');
    const expected = {kind: 'tools', includeUpdates: true, rows: []};

    await writeFile(script, `printf '%s\\n' '${JSON.stringify(expected)}'\n`);
    try {
        assert.deepEqual(await loadToolsFromScript(script, true), expected);
    } finally {
        await rm(dir, {recursive: true, force: true});
    }
});
