import test from 'node:test';
import assert from 'node:assert/strict';
import {
    firstToolWithAction,
    moveSelection,
    normalizeSlashCommand,
    resolveSlashCommand,
    SLASH_COMMANDS,
    toolAction,
    toolActionOptions,
    toolUninstallAction,
    visibleWindowStart
} from './state.mjs';

test('selection wraps around row counts', () => {
    assert.equal(moveSelection(0, 3, -1), 2);
    assert.equal(moveSelection(2, 3, 1), 0);
    assert.equal(moveSelection(0, 0, 1), 0);
});

test('finds first tool with an available action', () => {
    assert.equal(firstToolWithAction([
        {actionable: false, uninstallable: false},
        {actionable: false, uninstallable: true}
    ]), 1);
    assert.equal(firstToolWithAction([{actionable: false, uninstallable: false}]), 0);
});

test('calculates selected row viewport start', () => {
    assert.equal(visibleWindowStart(0, 100, 10), 0);
    assert.equal(visibleWindowStart(50, 100, 10), 45);
    assert.equal(visibleWindowStart(99, 100, 10), 90);
    assert.equal(visibleWindowStart(5, 8, 10), 0);
});

test('normalizes and resolves slash commands', () => {
    assert.equal(normalizeSlashCommand('/check now'), 'check');
    assert.deepEqual(SLASH_COMMANDS.map(command => command.name), [
        '/check',
        '/help',
        '/exit'
    ]);
    assert.equal(resolveSlashCommand('/check').type, 'check');
    assert.equal(resolveSlashCommand('/help').type, 'help');
    assert.equal(resolveSlashCommand('/exit').type, 'exit');
    assert.equal(resolveSlashCommand('/updates').type, 'message');
    assert.equal(resolveSlashCommand('/install').type, 'message');
    assert.equal(resolveSlashCommand('/update').type, 'message');
    assert.equal(resolveSlashCommand('/quit').type, 'message');
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

test('builds only available tool action options', () => {
    assert.deepEqual(toolActionOptions({
        command: 'gh',
        path: 'not installed',
        status: 'missing',
        actionable: true,
        uninstallable: false
    }), [
        {type: 'install', label: 'Install gh'}
    ]);
    assert.deepEqual(toolActionOptions({
        command: 'gh',
        path: '/home/user/.local/bin/gh',
        status: 'update',
        actionable: true,
        uninstallable: true
    }), [
        {type: 'update', label: 'Update gh'},
        {type: 'uninstall', label: 'Uninstall gh'}
    ]);
    assert.deepEqual(toolActionOptions({
        command: 'gh',
        status: 'current',
        actionable: false,
        uninstallable: true
    }), [
        {type: 'uninstall', label: 'Uninstall gh'}
    ]);
    assert.deepEqual(toolActionOptions({command: 'gh'}), []);
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
