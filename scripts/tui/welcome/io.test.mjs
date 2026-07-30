import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {writeAction} from './io.mjs';

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
