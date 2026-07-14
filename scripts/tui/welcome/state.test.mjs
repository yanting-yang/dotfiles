import test from 'node:test';
import assert from 'node:assert/strict';
import {
    actionForNvmRow,
    firstCurrentNvm,
    firstActionableTool,
    moveSelection,
    normalizeSlashCommand,
    resolveSlashCommand,
    toolAction,
    toolUninstallAction,
    visibleWindowStart
} from './state.mjs';

test('selection wraps around row counts', () => {
    assert.equal(moveSelection(0, 3, -1), 2);
    assert.equal(moveSelection(2, 3, 1), 0);
    assert.equal(moveSelection(0, 0, 1), 0);
});

test('finds first actionable tool', () => {
    assert.equal(firstActionableTool([{actionable: false}, {actionable: true}]), 1);
    assert.equal(firstActionableTool([{actionable: false}]), 0);
});

test('finds current Node version', () => {
    assert.equal(firstCurrentNvm([{current: false}, {current: true}]), 1);
    assert.equal(firstCurrentNvm([{status: 'installed'}, {status: 'active'}]), 1);
    assert.equal(firstCurrentNvm([{status: 'installed'}]), 0);
});

test('calculates selected row viewport start', () => {
    assert.equal(visibleWindowStart(0, 100, 10), 0);
    assert.equal(visibleWindowStart(50, 100, 10), 45);
    assert.equal(visibleWindowStart(99, 100, 10), 90);
    assert.equal(visibleWindowStart(5, 8, 10), 0);
});

test('normalizes and resolves slash commands', () => {
    assert.equal(normalizeSlashCommand('/updates now'), 'updates');
    assert.deepEqual(resolveSlashCommand('/nvm', 'tools'), {
        type: 'view',
        view: 'nvm',
        message: 'Opening Node versions.'
    });
    assert.equal(resolveSlashCommand('/node', 'tools').type, 'message');
    assert.equal(resolveSlashCommand('/tools', 'nvm').type, 'message');
    assert.equal(resolveSlashCommand('/local', 'tools').type, 'message');
    assert.equal(resolveSlashCommand('/all', 'tools').type, 'message');
    assert.equal(resolveSlashCommand('/q', 'tools').type, 'message');
    assert.equal(resolveSlashCommand('/h', 'tools').type, 'message');
    assert.equal(resolveSlashCommand('/?', 'tools').type, 'message');
    assert.equal(resolveSlashCommand('/wat', 'tools').type, 'message');
});

test('builds action file payloads', () => {
    assert.deepEqual(toolAction({command: 'gh'}, true), {
        ACTION: 'install_tool',
        COMMAND: 'gh',
        INCLUDE_UPDATES: '1',
        VIEW: 'tools'
    });
    assert.deepEqual(toolUninstallAction({command: 'gh'}, false), {
        ACTION: 'uninstall_tool',
        COMMAND: 'gh',
        INCLUDE_UPDATES: '0',
        VIEW: 'tools'
    });
    assert.deepEqual(actionForNvmRow({version: 'v24.0.0', status: 'available'}, true), {
        ACTION: 'nvm_install_use',
        VERSION: 'v24.0.0',
        VIEW: 'nvm',
        NVM_REMOTE: '1'
    });
});
