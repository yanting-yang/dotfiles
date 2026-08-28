export const SLASH_COMMANDS = [
    {
        name: '/check',
        description: 'Check latest tool versions',
        result: {type: 'check'}
    },
    {
        name: '/help',
        description: 'Show slash command help',
        result: {type: 'help'}
    },
    {
        name: '/exit',
        description: 'Exit welcome',
        result: {type: 'exit'}
    }
];

export const HELP_LINES = SLASH_COMMANDS.map(command => `${command.name}  ${command.description}`);

const TOOL_DISPLAY_NAMES = {
    latex: 'LaTeX'
};

export function toolDisplayName(command) {
    return TOOL_DISPLAY_NAMES[command] ?? command;
}

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

export function firstToolWithAction(rows = []) {
    const actionable = rows.findIndex(row => row.actionable);
    if (actionable >= 0) {
        return actionable;
    }

    const index = rows.findIndex(row => row.uninstallable);
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

export function resolveSlashCommand(input) {
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

export function toolActionOptions(row) {
    if (!row) {
        return [];
    }

    const options = [];
    const command = row.command ?? 'selected tool';
    const displayName = toolDisplayName(command);

    if (row.actionable) {
        const type = row.status === 'missing' || row.path === 'not installed'
            ? 'install'
            : 'update';
        const detail = command === 'latex' ? ' (TeX Live; full default ~10 GB)' : '';
        options.push({
            type,
            label: `${type === 'install' ? 'Install' : 'Update'} ${displayName}${detail}`
        });
    }
    if (row.uninstallable) {
        options.push({type: 'uninstall', label: `Uninstall ${displayName}`});
    }

    return options;
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
