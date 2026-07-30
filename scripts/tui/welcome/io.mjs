import {execFile} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dotfilesDir = process.env.WELCOME_DOTFILES_DIR ?? path.resolve(__dirname, '../../..');
const statusScript = path.join(dotfilesDir, 'scripts/tui/welcome/status.sh');

function execJson(args) {
    return new Promise((resolve, reject) => {
        execFile('bash', [statusScript, ...args], {
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

export function loadTools(includeUpdates = false) {
    return execJson(['tools', includeUpdates ? '--updates' : '--local']);
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
