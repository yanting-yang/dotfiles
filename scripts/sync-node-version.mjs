import {readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);

if (args.length > 1 || (args.length === 1 && args[0] !== '--check')) {
    console.error('Usage: node scripts/sync-node-version.mjs [--check]');
    process.exit(2);
}

const checkOnly = args[0] === '--check';
const major = (await readFile(path.join(rootDir, '.nvmrc'), 'utf8')).trim();

if (!/^[1-9]\d*$/.test(major)) {
    throw new Error('.nvmrc must contain one numeric Node major version');
}

const engine = `${major}.x`;
const targets = [
    {
        name: 'package.json',
        readEngine: data => data.engines?.node,
        writeEngine: data => {
            data.engines ??= {};
            data.engines.node = engine;
        }
    },
    {
        name: 'package-lock.json',
        readEngine: data => data.packages?.['']?.engines?.node,
        writeEngine: data => {
            const rootPackage = data.packages?.[''];

            if (!rootPackage) {
                throw new Error('package-lock.json is missing its root package');
            }

            rootPackage.engines ??= {};
            rootPackage.engines.node = engine;
        }
    }
];

const mismatches = [];

for (const target of targets) {
    const file = path.join(rootDir, target.name);
    const data = JSON.parse(await readFile(file, 'utf8'));
    const current = target.readEngine(data);

    if (current === engine) {
        continue;
    }
    if (checkOnly) {
        mismatches.push(`${target.name}: expected ${engine}, found ${current ?? 'missing'}`);
        continue;
    }

    target.writeEngine(data);
    await writeFile(file, `${JSON.stringify(data, null, 2)}\n`);
}

if (mismatches.length > 0) {
    console.error(`Node engine metadata does not match .nvmrc:\n${mismatches.join('\n')}`);
    process.exit(1);
}

if (!checkOnly) {
    console.log(`Synchronized Node engine metadata to ${engine}`);
}
