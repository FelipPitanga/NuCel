import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const file = path.join(
  here,
  '.engine',
  'ws-scrcpy-web',
  'src',
  'app',
  'public',
  'startStream.ts',
);

if (!fs.existsSync(file)) {
  console.error('[quality-patch] startStream.ts not found:', file);
  process.exit(1);
}

let source = fs.readFileSync(file, 'utf8');

const oldCode = `        const { instance, stop } = StreamClientScrcpy.start(
            params,
            undefined,
            true,
            videoSettings,`;

const newCode = `        const { instance, stop } = StreamClientScrcpy.start(
            params,
            undefined,
            false,
            videoSettings,`;

if (source.includes(newCode)) {
  console.log('[quality-patch] already applied');
  process.exit(0);
}

if (!source.includes(oldCode)) {
  console.error('[quality-patch] expected upstream startStream block not found');
  process.exit(2);
}

source = source.replace(oldCode, newCode);
fs.writeFileSync(file, source, 'utf8');
console.log('[quality-patch] applied: stream resolution no longer follows iframe size');
