import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const file = path.join(
  here,
  '.engine',
  'ws-scrcpy-web',
  'src',
  'server',
  'services',
  'HttpServer.ts',
);

if (!fs.existsSync(file)) {
  console.error('[cloudflare-https-patch] HttpServer.ts not found:', file);
  process.exit(1);
}

let source = fs.readFileSync(file, 'utf8');

const oldCode = `isRequestSecure(serverIsTls, req.socket?.remoteAddress, req.headers['x-forwarded-proto']),`;

const newCode = `isRequestSecure(
                serverIsTls,
                req.socket?.remoteAddress,
                req.headers['x-forwarded-proto'] ??
                    (() => {
                        const raw = req.headers['cf-visitor'];
                        const text = Array.isArray(raw) ? raw[0] : raw;
                        if (!text) return undefined;
                        try {
                            const parsed = JSON.parse(text) as { scheme?: unknown };
                            return parsed.scheme === 'https' ? 'https' : undefined;
                        } catch {
                            return undefined;
                        }
                    })(),
            ),`;

if (source.includes(newCode)) {
  console.log('[cloudflare-https-patch] already applied');
  process.exit(0);
}

if (!source.includes(oldCode)) {
  console.error('[cloudflare-https-patch] expected upstream block not found');
  process.exit(2);
}

source = source.replace(oldCode, newCode);
fs.writeFileSync(file, source, 'utf8');
console.log('[cloudflare-https-patch] applied: Cf-Visitor https forwarded to cookie policy');
