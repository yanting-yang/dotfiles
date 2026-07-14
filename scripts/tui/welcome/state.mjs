export const SLASH_COMMANDS = [
    {
        name: '/nvm',
        description: 'Open Node versions',
        result: {type: 'view', view: 'nvm', message: 'Opening Node versions.'}
    },
    {
        name: '/updates',
        description: 'Check latest tool versions',
        result: {type: 'updates'}
    },
    {
        name: '/check',
        description: 'Check latest tool versions',
        result: {type: 'updates'}
    },
    {
        name: '/install',
        description: 'Install or update the selected actionable tool',
        result: {type: 'install'}
    },
    {
        name: '/update',
        description: 'Install or update the selected actionable tool',
        result: {type: 'install'}
    },
    {
        name: '/help',
        description: 'Show slash command help',
        result: {type: 'help'}
    },
    {
        name: '/quit',
        description: 'Exit welcome',
        result: {type: 'quit'}
    },
    {
        name: '/exit',
        description: 'Exit welcome',
        result: {type: 'quit'}
    }
];

export const HELP_LINES = SLASH_COMMANDS.map(command => `${command.name}  ${command.description}`);

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
    const slashCommand = `/${command}`;
    const match = SLASH_COMMANDS.find(candidate => candidate.name === slashCommand);

    if (match) {
        if (match.result.type === 'help') {
            return {type: 'help', lines: HELP_LINES};
        }

        return match.result;
    }

    return {
        type: 'message',
        tone: 'warn',
        message: `Unknown command: /${command}. Try /help.`
    };
}

export function toolAction(row, includeUpdates) {
    return {
        ACTION: 'install_tool',
        COMMAND: row.command,
        INCLUDE_UPDATES: includeUpdates ? '1' : '0',
        VIEW: 'tools'
    };
}

export function toolUninstallAction(row, includeUpdates) {
    return {
        ACTION: 'uninstall_tool',
        COMMAND: row.command,
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
