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
  'interactionHandler',
  'InteractionHandler.ts',
);

if (!fs.existsSync(file)) {
  console.error('[touch-patch] engine source not found:', file);
  process.exit(1);
}

let source = fs.readFileSync(file, 'utf8');

const oldCode = `        const rect = target.getBoundingClientRect();
        let { clientWidth, clientHeight } = target;
        let touchX = event.clientX - rect.left;
        let touchY = event.clientY - rect.top;`;

const newCode = `        const rect = target.getBoundingClientRect();
        // Pointer coordinates and getBoundingClientRect() are expressed in the
        // same visual CSS coordinate space. clientWidth/clientHeight can differ
        // when the stream is scaled by browser zoom, iframe layout or CSS.
        // Use the actual rendered rectangle so taps map to the pixels the user sees.
        let clientWidth = rect.width;
        let clientHeight = rect.height;
        let touchX = event.clientX - rect.left;
        let touchY = event.clientY - rect.top;`;

if (source.includes(newCode)) {
  console.log('[touch-patch] already applied');
  process.exit(0);
}

if (!source.includes(oldCode)) {
  console.error('[touch-patch] expected upstream block not found; refusing to patch unknown source');
  process.exit(2);
}

source = source.replace(oldCode, newCode);
fs.writeFileSync(file, source, 'utf8');
console.log('[touch-patch] applied: visual rect coordinates enabled');
