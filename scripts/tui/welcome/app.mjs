import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Box, Text, useApp, useInput, useStdout} from 'ink';
import {
    HELP_LINES,
    firstToolWithAction,
    moveSelection,
    resolveSlashCommand,
    SLASH_COMMANDS,
    toolAction,
    toolActionOptions,
    toolDisplayName,
    toolUninstallAction,
    visibleWindowStart
} from './state.mjs';
import {loadTools, readResultMessage, writeAction} from './io.mjs';

const h = React.createElement;

function statusColor(status) {
    switch (status) {
        case 'missing':
            return 'red';
        case 'update':
        case 'check':
            return 'yellow';
        case 'current':
        case 'installed':
            return 'green';
        default:
            return undefined;
    }
}

const TOOL_LABELS = {
    node: '└── node',
    'cat-tmux': '└── catppuccin.tmux'
};

function toolLabel(row) {
    return TOOL_LABELS[row.command] ?? toolDisplayName(row.command);
}

function truncate(value, width) {
    const text = String(value ?? '');
    if (text.length <= width) {
        return text;
    }
    if (width <= 3) {
        return text.slice(0, width);
    }
    return `${text.slice(0, width - 3)}...`;
}

function Message({entry}) {
    const color = entry.tone === 'warn'
        ? 'yellow'
        : entry.tone === 'error'
            ? 'red'
            : entry.role === 'you'
                ? 'cyan'
                : 'green';
    const label = entry.role === 'you' ? 'you' : 'welcome';

    return h(Box, null,
        h(Text, {color, bold: entry.role === 'you'}, `${label}> `),
        h(Text, {color}, entry.text)
    );
}

function statusCounts(rows) {
    return rows.reduce((counts, row) => {
        counts[row.status] = (counts[row.status] ?? 0) + 1;
        return counts;
    }, {});
}

export function transcriptLineCount(entries = []) {
    return entries.reduce((count, entry) => {
        const text = String(entry?.text ?? '');
        return count + text.split('\n').length;
    }, 0);
}

function replaceToolRow(rows, row) {
    const identity = row.id ?? row.command;
    const index = rows.findIndex(candidate => (candidate.id ?? candidate.command) === identity);

    if (index < 0) {
        return [...rows, row];
    }

    const nextRows = [...rows];
    nextRows[index] = row;
    return nextRows;
}

function actionKeyRows(mode) {
    if (mode === 'slash') {
        return [
            {key: 'arrows', description: 'move command'},
            {key: 'Enter', description: 'run highlighted command'},
            {key: 'type', description: 'filter commands'},
            {key: 'Backspace', description: 'edit or close'},
            {key: 'Esc', description: 'close command menu'}
        ];
    }

    if (mode === 'tool-action') {
        return [
            {key: 'arrows', description: 'move action'},
            {key: 'Enter', description: 'run highlighted action'},
            {key: 'Esc', description: 'close action menu'}
        ];
    }

    if (mode === 'tool-uninstall') {
        return [
            {key: 'y + Enter', description: 'confirm uninstall'},
            {key: 'Enter', description: 'cancel uninstall'},
            {key: 'Esc', description: 'cancel uninstall'}
        ];
    }

    return [
        {key: 'arrows', description: 'move selection'},
        {key: 'Enter', description: 'choose selected action'},
        {key: '/', description: 'commands'}
    ];
}

function slashCommandMatches(filter) {
    const normalized = filter.trim().replace(/^\/+/, '').toLowerCase();
    const commands = SLASH_COMMANDS.filter(command => {
        if (!normalized) {
            return true;
        }

        return command.name.slice(1).startsWith(normalized)
            || command.description.toLowerCase().includes(normalized);
    });

    if (!normalized) {
        return commands;
    }

    return commands.sort((left, right) => {
        const leftExact = left.name.slice(1) === normalized ? 1 : 0;
        const rightExact = right.name.slice(1) === normalized ? 1 : 0;
        return rightExact - leftExact;
    });
}

export function WelcomePanel({inputMode, width, height, rows, includeUpdates}) {
    const username = process.env.USER ?? 'friend';
    const cwd = process.cwd().replace(process.env.HOME ?? '', '~');
    const preferredLeftWidth = Math.max(28, Math.min(48, Math.floor(width * 0.28)));
    const leftWidth = Math.min(preferredLeftWidth, Math.max(10, width - 28));
    const counts = statusCounts(rows);
    const summary = includeUpdates ? 'remote checked' : 'local only';
    const actions = actionKeyRows(inputMode);
    const actionKeyWidth = Math.max(...actions.map(action => action.key.length));

    return h(Box, {
        borderStyle: 'single',
        borderColor: 'red',
        height,
        width,
        flexShrink: 0
    },
        h(Box, {width: leftWidth, flexDirection: 'column', alignItems: 'center', paddingX: 1},
            h(Text, {bold: true, wrap: 'truncate-end'}, `Welcome back ${username}!`),
            h(Text, {color: 'gray', wrap: 'truncate-end'}, `Tools ${rows.length}  updates ${counts.update ?? 0}  missing ${counts.missing ?? 0}`),
            h(Text, {color: 'gray', wrap: 'truncate-end'}, truncate(cwd, Math.max(10, leftWidth - 4)))
        ),
        h(Box, {width: 1, flexDirection: 'column', flexShrink: 0},
            ...Array.from({length: Math.max(1, height - 2)}, (_, index) => h(Text, {key: index, color: 'red'}, '│'))
        ),
        h(Box, {flexGrow: 1, flexDirection: 'column', paddingX: 1},
            h(Text, {bold: true, color: 'red', wrap: 'truncate-end'}, 'Action keys'),
            ...actions.map(action => h(Text, {
                key: action.key,
                wrap: 'truncate-end'
            }, `${action.key.padEnd(actionKeyWidth)}  ${action.description}`)),
            h(Text, {color: 'gray', wrap: 'truncate-end'}, `Status: Managed tools · ${summary}`)
        )
    );
}

function ToolRows({rows, selected, width, visibleRows, showRange = true}) {
    const commandWidth = Math.max(7, ...rows.map(row => toolLabel(row).length)) + 2;
    const pathWidth = Math.max(18, width - 44 - commandWidth);
    const start = visibleWindowStart(selected, rows.length, visibleRows);
    const end = Math.min(start + visibleRows, rows.length);
    const shownRows = rows.slice(start, end);

    return h(Box, {flexDirection: 'column'},
        h(Text, {bold: true}, `${' '.padEnd(2)}${'command'.padEnd(commandWidth)}${'status'.padEnd(10)}${'current'.padEnd(11)}${'latest'.padEnd(11)}path`),
        ...shownRows.map((row, offset) => {
            const index = start + offset;
            const isSelected = index === selected;
            const marker = isSelected ? '>' : ' ';
            const prefix = `${marker} ${toolLabel(row).padEnd(commandWidth)}`;
            const versionText = `${String(row.current).padEnd(11)}${String(row.latest).padEnd(11)}`;

            return h(Box, {key: row.command},
                h(Text, {inverse: isSelected}, prefix),
                h(Text, {inverse: isSelected, color: statusColor(row.status)}, row.status.padEnd(10)),
                h(Text, {inverse: isSelected}, versionText),
                h(Text, {inverse: isSelected, color: row.path === 'not installed' ? 'red' : undefined}, truncate(row.path, pathWidth))
            );
        }),
        showRange && rows.length > visibleRows
            ? h(Text, {color: 'gray'}, `showing ${start + 1}-${end} of ${rows.length}`)
            : null
    );
}

function Prompt({mode, text, command}) {
    if (mode === 'slash') {
        return h(Text, {color: 'cyan'}, `/${text}`);
    }
    if (mode === 'tool-action') {
        return h(Text, {color: 'cyan'}, `choose action for ${command ?? 'selected tool'}`);
    }
    if (mode === 'tool-uninstall') {
        return h(Text, {color: 'yellow'}, `uninstall selected command? [y/N] ${text}`);
    }

    return h(Text, {color: 'gray'}, 'arrows move  Enter actions  / commands');
}

function CommandMenu({commands, selected, maxRows}) {
    if (commands.length === 0) {
        return h(Box, {flexDirection: 'column', flexShrink: 0},
            h(Text, {color: 'gray'}, 'No matching slash commands')
        );
    }

    const start = visibleWindowStart(selected, commands.length, maxRows);
    const end = Math.min(start + maxRows, commands.length);
    const shown = commands.slice(start, end);

    return h(Box, {flexDirection: 'column', flexShrink: 0},
        ...shown.map((command, offset) => {
            const index = start + offset;
            const isSelected = index === selected;

            return h(Box, {key: command.name},
                h(Text, {inverse: isSelected, color: isSelected ? 'cyan' : 'gray'}, command.name.padEnd(12)),
                h(Text, {inverse: isSelected, color: isSelected ? 'white' : 'gray'}, command.description)
            );
        })
    );
}

function ToolActionMenu({actions, selected, maxRows}) {
    const start = visibleWindowStart(selected, actions.length, maxRows);
    const end = Math.min(start + maxRows, actions.length);
    const shown = actions.slice(start, end);

    return h(Box, {flexDirection: 'column', flexShrink: 0},
        ...shown.map((action, offset) => {
            const index = start + offset;
            const isSelected = index === selected;

            return h(Text, {
                key: action.type,
                inverse: isSelected,
                color: isSelected ? 'cyan' : 'gray'
            }, action.label);
        })
    );
}

function InputBar({mode, text, command}) {
    return h(Box, {
        borderStyle: 'single',
        borderColor: 'gray',
        paddingX: 1,
        height: 3,
        flexShrink: 0
    },
        h(Text, {bold: true, color: mode === 'none' ? 'gray' : 'cyan'}, '› '),
        mode === 'none'
            ? h(Text, {color: 'gray'}, 'type / for commands')
            : h(Prompt, {mode, text, command})
    );
}

function useInitialMessages(resultFile) {
    const [messages, setMessages] = useState([
        {role: 'welcome', tone: 'info', text: 'Local status loaded. Remote checks stay behind explicit commands.'}
    ]);

    useEffect(() => {
        let alive = true;
        readResultMessage(resultFile).then(result => {
            if (!alive || !result) {
                return;
            }
            setMessages(current => [
                ...current,
                {role: 'welcome', tone: 'info', text: result}
            ]);
        }).catch(error => {
            if (alive) {
                setMessages(current => [
                    ...current,
                    {role: 'welcome', tone: 'error', text: error.message}
                ]);
            }
        });

        return () => {
            alive = false;
        };
    }, [resultFile]);

    return [messages, setMessages];
}

export function App({
    actionFile = process.env.WELCOME_ACTION_FILE,
    resultFile = process.env.WELCOME_RESULT_FILE,
    initialIncludeUpdates = process.env.WELCOME_INCLUDE_UPDATES === '1',
    loaders = {loadTools},
    writeActionFile = writeAction
} = {}) {
    const {exit} = useApp();
    const {stdout} = useStdout();
    const width = stdout?.columns ?? 100;
    const height = stdout?.rows ?? process.stdout.rows ?? 30;
    const [toolRows, setToolRows] = useState([]);
    const [toolSelected, setToolSelected] = useState(0);
    const [includeUpdates, setIncludeUpdates] = useState(initialIncludeUpdates);
    const [busy, setBusy] = useState('');
    const [inputMode, setInputMode] = useState('none');
    const [inputText, setInputText] = useState('');
    const [commandSelected, setCommandSelected] = useState(0);
    const [toolActionSelected, setToolActionSelected] = useState(0);
    const [messages, setMessages] = useInitialMessages(resultFile);
    const headerHeight = height >= 16 ? 10 : Math.max(7, height - 6);
    const selectedTool = toolRows[toolSelected];
    const selectedToolActions = useMemo(() => toolActionOptions(selectedTool), [selectedTool]);
    const slashCommands = useMemo(() => slashCommandMatches(inputText), [inputText]);
    const commandMenuVisible = inputMode === 'slash';
    const toolActionMenuVisible = inputMode === 'tool-action';
    const menuVisible = commandMenuVisible || toolActionMenuVisible;
    const menuItemCount = commandMenuVisible
        ? slashCommands.length
        : selectedToolActions.length;
    const menuMaxRows = menuVisible
        ? Math.max(1, Math.min(menuItemCount, height - headerHeight - 6))
        : 0;

    const appendMessage = useCallback((text, tone = 'info', role = 'welcome') => {
        setMessages(current => [...current.slice(-7), {role, tone, text}]);
    }, []);

    useEffect(() => {
        setCommandSelected(current => slashCommands.length === 0
            ? 0
            : Math.min(current, slashCommands.length - 1)
        );
    }, [slashCommands.length]);

    useEffect(() => {
        setToolActionSelected(current => selectedToolActions.length === 0
            ? 0
            : Math.min(current, selectedToolActions.length - 1)
        );
    }, [selectedToolActions.length]);

    const refreshTools = useCallback(async (updates = includeUpdates, message = '') => {
        setBusy(updates ? 'Checking latest tool versions...' : 'Refreshing local tool status...');
        try {
            const onRow = updates
                ? row => setToolRows(current => replaceToolRow(current, row))
                : undefined;
            const data = await loaders.loadTools(updates, onRow);
            setToolRows(data.rows ?? []);
            setIncludeUpdates(Boolean(data.includeUpdates));
            setToolSelected(firstToolWithAction(data.rows ?? []));
            if (message) {
                appendMessage(message);
            }
        } catch (error) {
            appendMessage(error.message, 'error');
        } finally {
            setBusy('');
        }
    }, [appendMessage, includeUpdates, loaders]);

    useEffect(() => {
        refreshTools(initialIncludeUpdates);
    }, []);

    const requestAction = useCallback(async action => {
        await writeActionFile(actionFile, action);
        exit();
    }, [actionFile, exit, writeActionFile]);

    const openToolActionMenu = useCallback(() => {
        if (!selectedTool) {
            appendMessage('No managed tool is selected.', 'warn');
            return;
        }
        if (selectedToolActions.length === 0) {
            appendMessage(`${selectedTool.command} has no available actions.`, 'warn');
            return;
        }
        setInputMode('tool-action');
        setInputText('');
        setToolActionSelected(0);
    }, [appendMessage, selectedTool, selectedToolActions.length]);

    const handleSlash = useCallback(commandText => {
        const result = resolveSlashCommand(commandText);
        appendMessage(`/${commandText.trim().replace(/^\/+/, '') || 'help'}`, 'info', 'you');

        switch (result.type) {
            case 'check':
                refreshTools(true, 'Latest tool versions loaded.');
                break;
            case 'help':
                for (const line of HELP_LINES) {
                    appendMessage(line);
                }
                break;
            case 'exit':
                exit();
                break;
            case 'message':
                appendMessage(result.message, result.tone);
                break;
            default:
                appendMessage('Command did nothing.', 'warn');
                break;
        }
    }, [appendMessage, exit, refreshTools]);

    const handleInputSubmit = useCallback(() => {
        if (inputMode === 'slash') {
            const command = slashCommands[commandSelected]?.name ?? inputText;
            setInputMode('none');
            setInputText('');
            setCommandSelected(0);
            handleSlash(command);
            return;
        }

        if (inputMode === 'tool-action') {
            const action = selectedToolActions[toolActionSelected];

            if (!selectedTool || !action) {
                setInputMode('none');
                setInputText('');
                setToolActionSelected(0);
                appendMessage('No managed tool action is selected.', 'warn');
                return;
            }

            setToolActionSelected(0);
            if (action.type === 'uninstall') {
                setInputMode('tool-uninstall');
                setInputText('');
                return;
            }

            setInputMode('none');
            setInputText('');
            requestAction(toolAction(selectedTool, includeUpdates));
            return;
        }

        if (inputMode === 'tool-uninstall') {
            const answer = inputText.trim().toLowerCase();
            setInputMode('none');
            setInputText('');
            setCommandSelected(0);
            if (answer === 'y' || answer === 'yes') {
                if (!selectedTool) {
                    appendMessage('No managed tool is selected.', 'warn');
                    return;
                }
                requestAction(toolUninstallAction(selectedTool, includeUpdates));
            } else {
                appendMessage('Skipped uninstall.');
            }
        }
    }, [appendMessage, commandSelected, handleSlash, includeUpdates, inputMode, inputText, requestAction, selectedTool, selectedToolActions, slashCommands, toolActionSelected]);

    useInput((input, key) => {
        if (busy) {
            return;
        }

        if (inputMode !== 'none') {
            if (key.escape) {
                setInputMode('none');
                setInputText('');
                setCommandSelected(0);
                setToolActionSelected(0);
                return;
            }
            if (inputMode === 'slash' && key.upArrow) {
                setCommandSelected(current => moveSelection(current, slashCommands.length, -1));
                return;
            }
            if (inputMode === 'slash' && key.downArrow) {
                setCommandSelected(current => moveSelection(current, slashCommands.length, 1));
                return;
            }
            if (inputMode === 'tool-action' && key.upArrow) {
                setToolActionSelected(current => moveSelection(current, selectedToolActions.length, -1));
                return;
            }
            if (inputMode === 'tool-action' && key.downArrow) {
                setToolActionSelected(current => moveSelection(current, selectedToolActions.length, 1));
                return;
            }
            if (key.return) {
                handleInputSubmit();
                return;
            }
            if (key.backspace || key.delete) {
                if (inputMode === 'slash' && inputText.length === 0) {
                    setInputMode('none');
                    setCommandSelected(0);
                    return;
                }
                setInputText(current => current.slice(0, -1));
                setCommandSelected(0);
                return;
            }
            if (inputMode === 'tool-action') {
                return;
            }
            if (input && !key.ctrl && !key.meta) {
                setInputText(current => `${current}${input}`);
                setCommandSelected(0);
            }
            return;
        }

        if (input === '/') {
            setInputMode('slash');
            setInputText('');
            setCommandSelected(0);
            return;
        }

        if (key.upArrow) {
            setToolSelected(current => moveSelection(current, toolRows.length, -1));
            return;
        }

        if (key.downArrow) {
            setToolSelected(current => moveSelection(current, toolRows.length, 1));
            return;
        }

        if (key.return) {
            openToolActionMenu();
            return;
        }
    });

    const menuHeight = menuVisible ? menuMaxRows : 0;
    const mainHeight = Math.max(3, height - headerHeight - menuHeight - 3);
    const transcriptLimit = menuVisible
        ? 0
        : Math.max(1, Math.min(6, Math.floor(mainHeight / 3)));
    const transcript = useMemo(
        () => transcriptLimit > 0 ? messages.slice(-transcriptLimit) : [],
        [messages, transcriptLimit]
    );
    const transcriptLines = transcriptLineCount(transcript);
    const extraStatusLines = busy ? 1 : 0;
    const visibleRows = Math.max(1, mainHeight - transcriptLines - extraStatusLines - 2);

    return h(Box, {flexDirection: 'column', height, width},
        h(WelcomePanel, {
            inputMode,
            width,
            height: headerHeight,
            rows: toolRows,
            includeUpdates
        }),
        h(Box, {height: mainHeight, flexDirection: 'column', flexGrow: 1},
            h(ToolRows, {rows: toolRows, selected: toolSelected, width, visibleRows, showRange: !menuVisible}),
            busy
                ? h(Text, {color: 'gray'}, busy)
                : null,
            h(Box, {marginTop: 1, flexDirection: 'column'},
                ...transcript.map((entry, index) => h(Message, {key: `${entry.role}-${index}-${entry.text}`, entry}))
            )
        ),
        commandMenuVisible
            ? h(CommandMenu, {commands: slashCommands, selected: commandSelected, maxRows: menuMaxRows})
            : toolActionMenuVisible
                ? h(ToolActionMenu, {actions: selectedToolActions, selected: toolActionSelected, maxRows: menuMaxRows})
                : null,
        h(InputBar, {mode: inputMode, text: inputText, command: selectedTool?.command})
    );
}
