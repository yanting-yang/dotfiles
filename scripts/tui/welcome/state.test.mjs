import test from 'node:test';
import assert from 'node:assert/strict';
import {
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

test('calculates selected row viewport start', () => {
    assert.equal(visibleWindowStart(0, 100, 10), 0);
    assert.equal(visibleWindowStart(50, 100, 10), 45);
    assert.equal(visibleWindowStart(99, 100, 10), 90);
    assert.equal(visibleWindowStart(5, 8, 10), 0);
});

test('normalizes and resolves slash commands', () => {
    assert.equal(normalizeSlashCommand('/updates now'), 'updates');
    assert.equal(resolveSlashCommand('/nvm').type, 'message');
    assert.equal(resolveSlashCommand('/node').type, 'message');
    assert.equal(resolveSlashCommand('/tools').type, 'message');
    assert.equal(resolveSlashCommand('/local').type, 'message');
    assert.equal(resolveSlashCommand('/all').type, 'message');
    assert.equal(resolveSlashCommand('/q').type, 'message');
    assert.equal(resolveSlashCommand('/h').type, 'message');
    assert.equal(resolveSlashCommand('/?').type, 'message');
    assert.equal(resolveSlashCommand('/wat').type, 'message');
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
});
