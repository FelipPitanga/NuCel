"""NuCel connector: scoped, signed access to local Android devices. Python 3.10+."""
import base64, hashlib, hmac, io, json, math, re, subprocess, sys, threading, time
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from PIL import Image

CONFIG = {}
LOCKS, FRAMES = {}, {}
GLOBAL_LOCK = threading.Lock()
LIMIT = threading.BoundedSemaphore(8)

def decode(value):
    return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))

def validate_token(token, origin, now=None):
    payload, sig = token.split('.')
    expected = hmac.new(CONFIG['secret'].encode(), payload.encode(), hashlib.sha256).digest()
    if not hmac.compare_digest(expected, decode(sig)):
        raise ValueError('Invalid signature')
    data = json.loads(decode(payload))
    now = time.time() if now is None else now
    if not isinstance(data.get('exp'), (int, float)) or not now < data['exp'] <= now + 65:
        raise ValueError('Expired token')
    if data.get('origin') != origin or origin != CONFIG['allowed_origin']:
        raise ValueError('Invalid origin')
    if not isinstance(data.get('serials'), list) or len(data['serials']) > 500:
        raise ValueError('Invalid devices')
    return data

def adb(*args):
    return subprocess.run([CONFIG.get('adb_path', 'adb'), *args], capture_output=True, check=True,
                          timeout=10, creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0).stdout

def device_lock(serial):
    with GLOBAL_LOCK:
        return LOCKS.setdefault(serial, threading.Lock())

def frame(serial):
    with device_lock(serial):
        previous = FRAMES.get(serial)
        if previous and time.monotonic() - previous[0] < .75:
            return previous[1], previous[2]
        raw = adb('-s', serial, 'exec-out', 'screencap', '-p')
        with Image.open(io.BytesIO(raw)) as im:
            size = im.size
            im = im.convert('RGB')
            im.thumbnail((450, 1000))
            output = io.BytesIO()
            im.save(output, 'JPEG', quality=65)
        data = output.getvalue()
        FRAMES[serial] = (time.monotonic(), data, size)
        return data, size

def perform(serial, body):
    typ = body.get('type')
    if typ == 'key':
        keys = {'home':'3', 'back':'4', 'recent':'187'}
        if body.get('key') not in keys:
            raise ValueError('Invalid key')
        args = ['keyevent', keys[body['key']]]
    elif typ in ('tap', 'swipe'):
        _, (width, height) = frame(serial)
        def coord(key, maximum):
            v = body.get(key)
            if type(v) not in (int, float) or not math.isfinite(v) or not 0 <= v <= 1:
                raise ValueError('Invalid coordinate')
            return str(min(maximum - 1, round(v * maximum)))
        args = [typ, coord('x', width), coord('y', height)]
        if typ == 'swipe':
            duration = body.get('duration', 300)
            if type(duration) not in (int, float) or not math.isfinite(duration):
                raise ValueError('Invalid duration')
            args += [coord('x2', width), coord('y2', height), str(max(150, min(1500, int(duration))))]
    else:
        raise ValueError('Invalid action')
    with device_lock(serial):
        adb('-s', serial, 'shell', 'input', *args)
        FRAMES.pop(serial, None)

class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(15)
    def log_message(self, *_):
        pass  # Do not log credentials, screen contents, or device IDs.
    def send(self, code, body, mime='application/json'):
        body = json.dumps(body).encode() if not isinstance(body, bytes) else body
        self.send_response(code)
        if self.headers.get('Origin') == CONFIG['allowed_origin']:
            self.send_header('Access-Control-Allow-Origin', CONFIG['allowed_origin'])
            self.send_header('Vary', 'Origin')
        self.send_header('Content-Type', mime)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_OPTIONS(self):
        if self.headers.get('Origin') != CONFIG['allowed_origin']:
            return self.send(403, {'error':'Origin denied'})
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', CONFIG['allowed_origin'])
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Max-Age', '600')
        self.send_header('Vary', 'Origin')
        self.end_headers()
    def do_GET(self):
        self.handle_request()
    def do_POST(self):
        self.handle_request()
    def handle_request(self):
        try:
            origin = self.headers.get('Origin', '')
            token = self.headers.get('Authorization', '')
            if not token.startswith('Bearer ') or len(token) > 20000:
                return self.send(401, {'error':'Unauthorized'})
            claims = validate_token(token[7:], origin)
        except (ValueError, KeyError, TypeError):
            return self.send(401, {'error':'Unauthorized'})
        if not LIMIT.acquire(blocking=False):
            return self.send(429, {'error':'Busy'})
        try:
            url = urlparse(self.path)
            if url.path == '/status' and self.command == 'GET':
                lines = adb('devices').decode(errors='replace').splitlines()[1:]
                visible = {}
                for line in lines:
                    values = line.split()
                    if len(values) >= 2 and values[0] in claims['serials']:
                        visible[values[0]] = values[1]
                return self.send(200, {'devices':visible})
            body = {}
            if self.command == 'POST':
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 4096:
                    return self.send(413, {'error':'Invalid payload'})
                body = json.loads(self.rfile.read(size))
                if not isinstance(body, dict):
                    raise ValueError('Invalid payload')
            serial = body.get('serial') if self.command == 'POST' else parse_qs(url.query).get('serial', [''])[0]
            if not isinstance(serial, str) or not re.fullmatch(r'[\w.:-]{1,100}', serial) or serial not in claims['serials']:
                return self.send(403, {'error':'Device not allowed'})
            if url.path == '/frame' and self.command == 'GET':
                return self.send(200, frame(serial)[0], 'image/jpeg')
            if url.path == '/action' and self.command == 'POST':
                perform(serial, body)
                return self.send(200, {'ok':True})
            return self.send(404, {'error':'Not found'})
        except (ValueError, KeyError, TypeError):
            self.send(400, {'error':'Invalid request'})
        except (subprocess.SubprocessError, OSError):
            self.send(503, {'error':'Device unavailable'})
        finally:
            LIMIT.release()

if __name__ == '__main__':
    path = Path(__file__).with_name('config.json')
    if not path.exists():
        raise SystemExit('Copie config.example.json para config.json e configure sua conexao primeiro.')
    CONFIG.update(json.loads(path.read_text(encoding='utf-8-sig')))
    if len(CONFIG.get('secret', '')) < 60 or 'COLE_' in CONFIG.get('secret', ''):
        raise SystemExit('Cole a chave gerada no painel NuCel no campo secret.')
    if not CONFIG.get('allowed_origin', '').startswith('https://'):
        raise SystemExit('Informe o endereco HTTPS do seu painel em allowed_origin, sem barra no final.')
    try:
        adb('version')
    except (OSError, subprocess.SubprocessError):
        raise SystemExit('ADB nao encontrado. Confira adb_path no config.json.')
    print('NuCel pronto em 127.0.0.1:8765. Mantenha esta janela aberta.')
    print('Inicie seu tunel HTTPS apontando para http://127.0.0.1:8765.')
    ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
