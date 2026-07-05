export const HELP_LINES = [
    '/nvm or /node opens Node versions.',
    '/tools returns to managed tools.',
    '/updates checks latest tool versions.',
    '/local returns to fast local status.',
    '/install runs the selected actionable row.',
    '/all runs every actionable row.',
    '/quit exits welcome.'
];

export function clampSelection(selected, count) {
    if (count <= 0) {
        return 0;
    }
    if (selected < 0) {
        return count - 1;
    }
    if (selected >= count) {
        return 0;
    }
    return selected;
}

export function moveSelection(selected, count, delta) {
    if (count <= 0) {
        return 0;
    }
    return (selected + count + delta) % count;
}

export function firstActionableTool(rows = []) {
    const index = rows.findIndex(row => row.actionable);
    return index >= 0 ? index : 0;
}

export function firstCurrentNvm(rows = []) {
    const index = rows.findIndex(row => row.current || row.status === 'active');
    return index >= 0 ? index : 0;
}

export function visibleWindowStart(selected, count, visibleCount) {
    if (count <= visibleCount || visibleCount <= 0) {
        return 0;
    }

    const halfWindow = Math.floor(visibleCount / 2);
    const centered = selected - halfWindow;
    return Math.min(Math.max(centered, 0), count - visibleCount);
}

export function normalizeSlashCommand(input) {
    const trimmed = input.trim().replace(/^\/+/, '');
    const [command = 'help'] = trimmed.split(/\s+/);
    return command.toLowerCase();
}

export function resolveSlashCommand(input, view) {
    const command = normalizeSlashCommand(input);

    switch (command) {
        case 'nvm':
        case 'node':
            return {type: 'view', view: 'nvm', message: 'Opening Node versions.'};
        case 'tools':
            return {type: 'view', view: 'tools', message: 'Back to managed tools.'};
        case 'updates':
        case 'check':
            return {type: 'updates'};
        case 'local':
            return {type: 'local'};
        case 'install':
        case 'update':
            return {type: 'install'};
        case 'all':
            return {type: 'install_all'};
        case 'help':
        case 'h':
        case '?':
            return {type: 'help', lines: HELP_LINES};
        case 'q':
        case 'quit':
        case 'exit':
            return {type: 'quit'};
        default:
            return {
                type: 'message',
                tone: 'warn',
                message: `Unknown command: /${command}. Try /help.`
            };
    }
}

export function toolAction(row, includeUpdates) {
    return {
        ACTION: 'install_tool',
        COMMAND: row.command,
        INCLUDE_UPDATES: includeUpdates ? '1' : '0',
        VIEW: 'tools'
    };
}

export function allToolsAction(includeUpdates) {
    return {
        ACTION: 'install_all',
        INCLUDE_UPDATES: includeUpdates ? '1' : '0',
        VIEW: 'tools'
    };
}

export function nvmAction(action, version, includeRemote) {
    return {
        ACTION: action,
        VERSION: version,
        VIEW: 'nvm',
        NVM_REMOTE: includeRemote ? '1' : '0'
    };
}

export function actionForNvmRow(row, includeRemote) {
    if (!row) {
        return null;
    }

    if (row.status === 'available') {
        return nvmAction('nvm_install_use', row.version, includeRemote);
    }

    return nvmAction('nvm_use', row.version, includeRemote);
}
