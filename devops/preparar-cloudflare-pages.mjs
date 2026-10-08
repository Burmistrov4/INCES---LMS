import { copyFile, access } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const outputDir = path.resolve(root, process.argv[2] ?? 'build/web');
const source = path.resolve(root, 'web/_headers');
const destination = path.join(outputDir, '_headers');

await access(source);
await access(outputDir);
await copyFile(source, destination);

console.log('[pages] _headers copiado a ' + destination);
