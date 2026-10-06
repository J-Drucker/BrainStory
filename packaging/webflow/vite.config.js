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
  // Webflow canonicalizes /app/brainstory/ to /app/brainstory, so use an
  // absolute base path to keep the embedded app's relative assets in place.
  const content = name === 'index.html'
    ? strToU8(strFromU8(bytes).replace(/<base href="[^"]*">/, '<base href="/app/brainstory/">'))
    : bytes;
  writeFileSync(path, content);
}

export default defineConfig({});
