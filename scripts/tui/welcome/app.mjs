import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Box, Text, useApp, useInput, useStdout} from 'ink';
import {
    HELP_LINES,
    actionForNvmRow,
    firstActionableTool,
    firstCurrentNvm,
    moveSelection,
    nvmAction,
    resolveSlashCommand,
    SLASH_COMMANDS,
    toolAction,
    visibleWindowStart
} from './state.mjs';
import {loadNvm, loadTools, readResultMessage, writeAction} from './io.mjs';

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
        case 'active':
            return 'green';
        case 'available':
            return 'cyan';
        default:
            return undefined;
    }
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

function WelcomePanel({view, width, height, rows, includeUpdates, nvmCurrent, nvmRemote}) {
    const username = process.env.USER ?? 'friend';
    const cwd = process.cwd().replace(process.env.HOME ?? '', '~');
    const leftWidth = Math.max(28, Math.min(48, Math.floor(width * 0.28)));
    const counts = statusCounts(rows);
    const summary = view === 'nvm'
        ? `${nvmRemote ? 'remote loaded' : 'local only'}`
        : includeUpdates ? 'remote checked' : 'local only';

    return h(Box, {
        borderStyle: 'single',
        borderColor: 'red',
        height,
        width,
        flexShrink: 0
    },
        h(Box, {width: leftWidth, flexDirection: 'column', alignItems: 'center', paddingX: 1},
            h(Text, {bold: true}, `Welcome back ${username}!`),
            h(Text, {color: 'red'}, '   .----.   '),
            h(Text, {color: 'red'}, '  /|    |\\  '),
            h(Text, {color: 'red'}, '  \\|____|/  '),
            h(Text, {color: 'gray'}, view === 'nvm'
                ? `Node ${nvmCurrent}`
                : `Tools ${rows.length}  updates ${counts.update ?? 0}  missing ${counts.missing ?? 0}`
            ),
            h(Text, {color: 'gray'}, truncate(cwd, Math.max(10, leftWidth - 4)))
        ),
        h(Box, {width: 1, flexDirection: 'column', flexShrink: 0},
            ...Array.from({length: Math.max(1, height - 2)}, (_, index) => h(Text, {key: index, color: 'red'}, '│'))
        ),
        h(Box, {flexGrow: 1, flexDirection: 'column', paddingX: 1},
            h(Text, {bold: true, color: 'red'}, 'Tips for getting started'),
            h(Text, null, 'Type / to open the command menu'),
            h(Text, null, view === 'nvm' ? 'Press r to load remote Node versions' : 'Run /updates before installing newer tools'),
            h(Text, {color: 'gray'}, 'Enter runs the selected row; q backs out or exits'),
            h(Text, {color: 'red'}, '─'.repeat(Math.max(1, width - leftWidth - 8))),
            h(Text, {bold: true, color: 'red'}, 'Status'),
            h(Text, null, view === 'nvm'
                ? `Node screen · ${summary}`
                : `Managed tools · ${summary}`
            )
        )
    );
}

function ToolRows({rows, selected, width, visibleRows, showRange = true}) {
    const pathWidth = Math.max(18, width - 52);
    const start = visibleWindowStart(selected, rows.length, visibleRows);
    const end = Math.min(start + visibleRows, rows.length);
    const shownRows = rows.slice(start, end);

    return h(Box, {flexDirection: 'column'},
        h(Text, {bold: true}, `${' '.padEnd(2)}${'command'.padEnd(8)}${'status'.padEnd(10)}${'current'.padEnd(11)}${'latest'.padEnd(11)}path`),
        ...shownRows.map((row, offset) => {
            const index = start + offset;
            const isSelected = index === selected;
            const marker = isSelected ? '>' : ' ';
            const prefix = `${marker} ${row.command.padEnd(8)}`;
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

function NvmRows({rows, selected, width, visibleRows, showRange = true}) {
    const pathWidth = Math.max(12, width - 44);
    const start = visibleWindowStart(selected, rows.length, visibleRows);
    const end = Math.min(start + visibleRows, rows.length);
    const shownRows = rows.slice(start, end);

    if (rows.length === 0) {
        return h(Text, {color: 'yellow'}, 'No Node versions were found.');
    }

    return h(Box, {flexDirection: 'column'},
        h(Text, {bold: true}, `${' '.padEnd(2)}${'version'.padEnd(14)}${'status'.padEnd(11)}${'lts'.padEnd(13)}path`),
        ...shownRows.map((row, offset) => {
            const index = start + offset;
            const isSelected = index === selected;
            const marker = isSelected ? '>' : ' ';

            return h(Box, {key: row.version},
                h(Text, {inverse: isSelected}, `${marker} ${row.version.padEnd(14)}`),
                h(Text, {inverse: isSelected, color: statusColor(row.status)}, row.status.padEnd(11)),
                h(Text, {inverse: isSelected, color: row.lts === '-' ? undefined : 'yellow'}, row.lts.padEnd(13)),
                h(Text, {inverse: isSelected}, truncate(row.path, pathWidth))
            );
        }),
        showRange && rows.length > visibleRows
            ? h(Text, {color: 'gray'}, `showing ${start + 1}-${end} of ${rows.length}`)
            : null
    );
}

function Prompt({mode, text, view}) {
    if (mode === 'slash') {
        return h(Text, {color: 'cyan'}, `/${text}`);
    }
    if (mode === 'nvm-install') {
        return h(Text, {color: 'cyan'}, `install node [lts/*]: ${text}`);
    }
    if (mode === 'nvm-uninstall') {
        return h(Text, {color: 'yellow'}, `uninstall selected? [y/N] ${text}`);
    }

    return h(Text, {color: 'gray'}, view === 'nvm'
        ? 'j/k move  Enter use/install  i install  d uninstall  r remote  / command  q back'
        : 'j/k move  Enter install/update  / command  r local refresh  q quit'
    );
}

function CommandMenu({filter, maxRows}) {
    const normalized = filter.trim().toLowerCase();
    const commands = SLASH_COMMANDS.filter(command => {
        if (!normalized) {
            return true;
        }

        return command.name.slice(1).startsWith(normalized)
            || command.description.toLowerCase().includes(normalized);
    });
    const shown = commands.slice(0, maxRows);

    if (shown.length === 0) {
        return h(Box, {flexDirection: 'column', flexShrink: 0},
            h(Text, {color: 'gray'}, 'No matching slash commands')
        );
    }

    return h(Box, {flexDirection: 'column', flexShrink: 0},
        ...shown.map((command, index) => h(Box, {key: command.name},
            h(Text, {color: index === 0 ? 'cyan' : 'gray'}, command.name.padEnd(12)),
            h(Text, {color: index === 0 ? 'white' : 'gray'}, command.description)
        ))
    );
}

function InputBar({mode, text, view}) {
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
            : h(Prompt, {mode, text, view})
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
    initialView = process.env.WELCOME_INITIAL_VIEW === 'nvm' ? 'nvm' : 'tools',
    initialIncludeUpdates = process.env.WELCOME_INCLUDE_UPDATES === '1',
    initialNvmRemote = process.env.WELCOME_NVM_REMOTE === '1',
    loaders = {loadTools, loadNvm},
    writeActionFile = writeAction
} = {}) {
    const {exit} = useApp();
    const {stdout} = useStdout();
    const width = stdout?.columns ?? 100;
    const height = stdout?.rows ?? process.stdout.rows ?? 30;
    const [view, setView] = useState(initialView);
    const [toolRows, setToolRows] = useState([]);
    const [nvmRows, setNvmRows] = useState([]);
    const [toolSelected, setToolSelected] = useState(0);
    const [nvmSelected, setNvmSelected] = useState(0);
    const [includeUpdates, setIncludeUpdates] = useState(initialIncludeUpdates);
    const [nvmRemote, setNvmRemote] = useState(initialNvmRemote);
    const [nvmCurrent, setNvmCurrent] = useState('none');
    const [nvmError, setNvmError] = useState('');
    const [busy, setBusy] = useState('');
    const [inputMode, setInputMode] = useState('none');
    const [inputText, setInputText] = useState('');
    const [messages, setMessages] = useInitialMessages(resultFile);

    const appendMessage = useCallback((text, tone = 'info', role = 'welcome') => {
        setMessages(current => [...current.slice(-7), {role, tone, text}]);
    }, []);

    const refreshTools = useCallback(async (updates = includeUpdates, message = '') => {
        setBusy(updates ? 'Checking latest tool versions...' : 'Refreshing local tool status...');
        try {
            const data = await loaders.loadTools(updates);
            setToolRows(data.rows ?? []);
            setIncludeUpdates(Boolean(data.includeUpdates));
            setToolSelected(firstActionableTool(data.rows ?? []));
            if (message) {
                appendMessage(message);
            }
        } catch (error) {
            appendMessage(error.message, 'error');
        } finally {
            setBusy('');
        }
    }, [appendMessage, includeUpdates, loaders]);

    const refreshNvm = useCallback(async (remote = nvmRemote, message = '') => {
        setBusy(remote ? 'Loading nvm remote versions...' : 'Refreshing local Node versions...');
        try {
            const data = await loaders.loadNvm(remote);
            setNvmRows(data.rows ?? []);
            setNvmRemote(Boolean(data.remoteLoaded));
            setNvmCurrent(data.current ?? 'none');
            setNvmError(data.error ?? '');
            setNvmSelected(firstCurrentNvm(data.rows ?? []));
            if (message) {
                appendMessage(message);
            }
        } catch (error) {
            appendMessage(error.message, 'error');
        } finally {
            setBusy('');
        }
    }, [appendMessage, loaders, nvmRemote]);

    useEffect(() => {
        refreshTools(initialIncludeUpdates);
    }, []);

    useEffect(() => {
        if (view === 'nvm' && nvmRows.length === 0 && !busy) {
            refreshNvm(initialNvmRemote);
        }
    }, [view]);

    const requestAction = useCallback(async action => {
        await writeActionFile(actionFile, action);
        exit();
    }, [actionFile, exit, writeActionFile]);

    const selectedTool = toolRows[toolSelected];
    const selectedNvm = nvmRows[nvmSelected];

    const submitToolInstall = useCallback(() => {
        if (!selectedTool) {
            appendMessage('No managed tool is selected.', 'warn');
            return;
        }
        if (!selectedTool.actionable) {
            appendMessage(`${selectedTool.command} has no install action right now.`, 'warn');
            return;
        }
        requestAction(toolAction(selectedTool, includeUpdates));
    }, [appendMessage, includeUpdates, requestAction, selectedTool]);

    const handleSlash = useCallback(commandText => {
        const result = resolveSlashCommand(commandText, view);
        appendMessage(`/${commandText.trim().replace(/^\/+/, '') || 'help'}`, 'info', 'you');

        switch (result.type) {
            case 'view':
                setView(result.view);
                appendMessage(result.message);
                break;
            case 'updates':
                setView('tools');
                refreshTools(true, 'Latest tool versions loaded.');
                break;
            case 'install':
                submitToolInstall();
                break;
            case 'help':
                for (const line of HELP_LINES) {
                    appendMessage(line);
                }
                break;
            case 'quit':
                exit();
                break;
            case 'message':
                appendMessage(result.message, result.tone);
                break;
            default:
                appendMessage('Command did nothing.', 'warn');
                break;
        }
    }, [appendMessage, exit, refreshTools, submitToolInstall, view]);

    const handleInputSubmit = useCallback(() => {
        if (inputMode === 'slash') {
            const command = inputText;
            setInputMode('none');
            setInputText('');
            handleSlash(command);
            return;
        }

        if (inputMode === 'nvm-install') {
            const version = inputText.trim() || 'lts/*';
            setInputMode('none');
            setInputText('');
            requestAction(nvmAction('nvm_install_use', version, nvmRemote));
            return;
        }

        if (inputMode === 'nvm-uninstall') {
            const answer = inputText.trim().toLowerCase();
            setInputMode('none');
            setInputText('');
            if (answer === 'y' || answer === 'yes') {
                requestAction(nvmAction('nvm_uninstall', selectedNvm.version, nvmRemote));
            } else {
                appendMessage('Skipped uninstall.');
            }
        }
    }, [appendMessage, handleSlash, inputMode, inputText, nvmRemote, requestAction, selectedNvm]);

    useInput((input, key) => {
        if (busy) {
            return;
        }

        if (inputMode !== 'none') {
            if (key.escape) {
                setInputMode('none');
                setInputText('');
                return;
            }
            if (key.return) {
                handleInputSubmit();
                return;
            }
            if (key.backspace || key.delete) {
                setInputText(current => current.slice(0, -1));
                return;
            }
            if (input && !key.ctrl && !key.meta) {
                setInputText(current => `${current}${input}`);
            }
            return;
        }

        if (input === '/') {
            setInputMode('slash');
            setInputText('');
            return;
        }

        if (key.upArrow || input === 'k' || input === 'K') {
            if (view === 'nvm') {
                setNvmSelected(current => moveSelection(current, nvmRows.length, -1));
            } else {
                setToolSelected(current => moveSelection(current, toolRows.length, -1));
            }
            return;
        }

        if (key.downArrow || input === 'j' || input === 'J') {
            if (view === 'nvm') {
                setNvmSelected(current => moveSelection(current, nvmRows.length, 1));
            } else {
                setToolSelected(current => moveSelection(current, toolRows.length, 1));
            }
            return;
        }

        if (key.return) {
            if (view === 'nvm') {
                const action = actionForNvmRow(selectedNvm, nvmRemote);
                if (action) {
                    requestAction(action);
                } else {
                    appendMessage('No Node version is selected.', 'warn');
                }
            } else {
                submitToolInstall();
            }
            return;
        }

        if (input === 'r' || input === 'R') {
            if (view === 'nvm') {
                refreshNvm(true, 'Remote Node versions loaded.');
            } else {
                refreshTools(false, 'Local tool status refreshed.');
            }
            return;
        }

        if (view === 'nvm' && (input === 'i' || input === 'I')) {
            setInputMode('nvm-install');
            setInputText('');
            return;
        }

        if (view === 'nvm' && (input === 'd' || input === 'D' || input === 'x' || input === 'X')) {
            if (!selectedNvm || selectedNvm.status === 'available') {
                appendMessage('Selected Node version is not installed.', 'warn');
                return;
            }
            setInputMode('nvm-uninstall');
            setInputText('');
            return;
        }

        if (input === 'q' || input === 'Q' || key.escape) {
            if (view === 'nvm') {
                setView('tools');
                appendMessage('Back to managed tools.');
            } else if (includeUpdates) {
                refreshTools(false, 'Back to local welcome.');
            } else {
                exit();
            }
        }
    });

    const headerHeight = height >= 24 ? 10 : Math.max(7, Math.floor(height * 0.35));
    const commandMenuVisible = inputMode === 'slash';
    const commandMenuMaxRows = commandMenuVisible
        ? Math.max(1, Math.min(SLASH_COMMANDS.length, height - headerHeight - 6))
        : 0;
    const commandMenuHeight = commandMenuVisible ? commandMenuMaxRows : 0;
    const mainHeight = Math.max(3, height - headerHeight - commandMenuHeight - 3);
    const transcriptLimit = commandMenuVisible
        ? 0
        : Math.max(1, Math.min(6, Math.floor(mainHeight / 3)));
    const transcript = useMemo(
        () => transcriptLimit > 0 ? messages.slice(-transcriptLimit) : [],
        [messages, transcriptLimit]
    );
    const extraStatusLines = (nvmError && view === 'nvm' ? 1 : 0) + (busy ? 1 : 0);
    const visibleRows = Math.max(1, mainHeight - transcript.length - extraStatusLines - 2);

    return h(Box, {flexDirection: 'column', height, width},
        h(WelcomePanel, {
            view,
            width,
            height: headerHeight,
            rows: view === 'nvm' ? nvmRows : toolRows,
            includeUpdates,
            nvmCurrent,
            nvmRemote
        }),
        h(Box, {height: mainHeight, flexDirection: 'column', flexGrow: 1},
            view === 'nvm'
                ? h(NvmRows, {rows: nvmRows, selected: nvmSelected, width, visibleRows, showRange: !commandMenuVisible})
                : h(ToolRows, {rows: toolRows, selected: toolSelected, width, visibleRows, showRange: !commandMenuVisible}),
            nvmError && view === 'nvm'
                ? h(Text, {color: 'yellow'}, nvmError)
                : null,
            busy
                ? h(Text, {color: 'gray'}, busy)
                : null,
            h(Box, {marginTop: 1, flexDirection: 'column'},
                ...transcript.map((entry, index) => h(Message, {key: `${entry.role}-${index}-${entry.text}`, entry}))
            )
        ),
        inputMode === 'slash'
            ? h(CommandMenu, {filter: inputText, maxRows: commandMenuMaxRows})
            : null,
        h(InputBar, {mode: inputMode, text: inputText, view})
    );
}
