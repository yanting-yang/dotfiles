import {execFile, spawn} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dotfilesDir = process.env.WELCOME_DOTFILES_DIR ?? path.resolve(__dirname, '../../..');
const statusScript = path.join(dotfilesDir, 'scripts/tui/welcome/status.sh');
const MAX_STATUS_OUTPUT_BYTES = 1024 * 1024 * 8;

function execJson(script, args) {
    return new Promise((resolve, reject) => {
        execFile('bash', [script, ...args], {
            cwd: dotfilesDir,
            env: process.env,
            maxBuffer: 1024 * 1024 * 8
        }, (error, stdout, stderr) => {
            if (error) {
                error.message = [error.message, stderr.trim()].filter(Boolean).join('\n');
                reject(error);
                return;
            }

            try {
                resolve(JSON.parse(stdout));
            } catch (parseError) {
                parseError.message = `Could not parse status JSON: ${parseError.message}\n${stdout}`;
                reject(parseError);
            }
        });
    });
}

function streamError(message, stderr) {
    return new Error([message, stderr.trim()].filter(Boolean).join('\n'));
}

function execJsonStream(script, args, onRow) {
    return new Promise((resolve, reject) => {
        const child = spawn('bash', [script, ...args], {
            cwd: dotfilesDir,
            env: process.env,
            stdio: ['ignore', 'pipe', 'pipe']
        });
        const rows = [];
        const rowIdentities = new Set();
        let stdoutBuffer = '';
        let stderr = '';
        let outputBytes = 0;
        let complete = false;
        let streamFailure;
        let settled = false;

        const failStream = error => {
            if (streamFailure) {
                return;
            }
            streamFailure = error;
            child.kill();
        };

        const parseLine = value => {
            const line = value.trim();
            if (!line || streamFailure) {
                return;
            }

            try {
                const event = JSON.parse(line);
                if (event.kind === 'tool-row' && event.row && typeof event.row === 'object' && !Array.isArray(event.row)) {
                    if (complete) {
                        throw new Error('Received a tool row after the completion event');
                    }
                    const identity = event.row.id ?? event.row.command;
                    if (typeof identity !== 'string' || !identity) {
                        throw new Error('Received a tool row without an identity');
                    }
                    if (rowIdentities.has(identity)) {
                        throw new Error(`Received duplicate tool row: ${identity}`);
                    }
                    rowIdentities.add(identity);
                    rows.push(event.row);
                    onRow(event.row);
                    return;
                }
                if (event.kind === 'tools-complete' && event.includeUpdates === true) {
                    if (complete) {
                        throw new Error('Received duplicate completion events');
                    }
                    complete = true;
                    return;
                }
                throw new Error(`Unknown status stream event: ${event.kind ?? 'missing kind'}`);
            } catch (error) {
                failStream(new Error(`Could not parse status stream: ${error.message}`));
            }
        };

        child.stdout.setEncoding('utf8');
        child.stdout.on('data', chunk => {
            outputBytes += Buffer.byteLength(chunk);
            if (outputBytes > MAX_STATUS_OUTPUT_BYTES) {
                failStream(new Error('Status stream exceeded the 8 MiB output limit'));
                return;
            }
            stdoutBuffer += chunk;
            let newline = stdoutBuffer.indexOf('\n');
            while (newline >= 0) {
                parseLine(stdoutBuffer.slice(0, newline));
                stdoutBuffer = stdoutBuffer.slice(newline + 1);
                newline = stdoutBuffer.indexOf('\n');
            }
        });

        child.stderr.setEncoding('utf8');
        child.stderr.on('data', chunk => {
            outputBytes += Buffer.byteLength(chunk);
            if (outputBytes > MAX_STATUS_OUTPUT_BYTES) {
                failStream(new Error('Status stream exceeded the 8 MiB output limit'));
                return;
            }
            stderr += chunk;
        });

        child.once('error', error => {
            if (settled) {
                return;
            }
            settled = true;
            reject(error);
        });

        child.once('close', (code, signal) => {
            if (settled) {
                return;
            }
            settled = true;
            parseLine(stdoutBuffer);

            if (streamFailure) {
                reject(streamError(streamFailure.message, stderr));
                return;
            }
            if (code !== 0) {
                const exit = signal ? `signal ${signal}` : `exit code ${code}`;
                reject(streamError(`Status stream failed with ${exit}`, stderr));
                return;
            }
            if (!complete) {
                reject(streamError('Status stream ended before completion', stderr));
                return;
            }

            resolve({kind: 'tools', includeUpdates: true, rows});
        });
    });
}

export function loadToolsFromScript(script, includeUpdates = false, onRow) {
    if (includeUpdates && typeof onRow === 'function') {
        return execJsonStream(script, ['tools', '--updates', '--stream'], onRow);
    }

    return execJson(script, ['tools', includeUpdates ? '--updates' : '--local']);
}

export function loadTools(includeUpdates = false, onRow) {
    return loadToolsFromScript(statusScript, includeUpdates, onRow);
}

export async function readResultMessage(resultFile) {
    if (!resultFile || !existsSync(resultFile)) {
        return '';
    }

    return (await readFile(resultFile, 'utf8')).trim();
}

function cleanValue(value) {
    return String(value ?? '').replace(/[\r\n]/g, ' ').trim();
}

export async function writeAction(actionFile, action) {
    if (!actionFile) {
        throw new Error('WELCOME_ACTION_FILE is not set');
    }

    const body = Object.entries(action)
        .map(([key, value]) => `${key}=${cleanValue(value)}`)
        .join('\n');

    await writeFile(actionFile, `${body}\n`, {mode: 0o600});
}

export function plainToolSummary(data) {
    const rows = data.rows ?? [];
    const lines = [];
    lines.push(`Welcome (${data.includeUpdates ? 'remote checked' : 'local only'})`);
    lines.push('command  status     current     latest      path');
    for (const row of rows) {
        lines.push([
            row.command.padEnd(8),
            row.status.padEnd(10),
            row.current.padEnd(11),
            row.latest.padEnd(11),
            row.path
        ].join(''));
    }
    return lines.join('\n');
}
