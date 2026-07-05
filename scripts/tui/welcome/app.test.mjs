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
                actionable: false
            }
        ]
    };

    const loaders = {
        loadTools: async () => tools,
        loadNvm: async () => ({kind: 'nvm', ok: true, current: 'none', remoteLoaded: false, rows: []})
    };

    const {lastFrame, unmount} = render(h(App, {
        loaders,
        resultFile: '',
        actionFile: '/tmp/unused-action'
    }));

    await new Promise(resolve => setTimeout(resolve, 20));
    assert.match(lastFrame(), /Welcome/);
    assert.match(lastFrame(), /gh/);
    assert.match(lastFrame(), /installed/);
    unmount();
});
