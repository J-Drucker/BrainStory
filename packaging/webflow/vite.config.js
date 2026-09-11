import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { unzipSync, strFromU8, strToU8 } from 'fflate';
import { defineConfig } from 'vite';

const root = dirname(fileURLToPath(import.meta.url));
const destination = resolve(root, 'public/brainstory');
const files = unzipSync(readFileSync(resolve(root, 'brainstory-web.zip')));
for (const [name, bytes] of Object.entries(files)) {
  if (name.endsWith('/')) continue;
  const path = resolve(destination, name);
  if (!path.startsWith(destination + sep)) throw new Error('Invalid release archive path');
  mkdirSync(dirname(path), { recursive: true });
  // The embedded application resolves assets within its own directory at any mount path.
  const content = name === 'index.html'
    ? strToU8(strFromU8(bytes).replace(/<base href="[^"]*">/, '<base href="./">'))
    : bytes;
  writeFileSync(path, content);
}

export default defineConfig({});
