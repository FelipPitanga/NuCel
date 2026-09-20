"""NuCel connector: low-latency, scoped Android control. Python 3.10+."""
import base64, hashlib, hmac, io, json, math, re, subprocess, sys, threading, time
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from PIL import Image

CONFIG = {}
FRAMES = {}          # serial -> {data, size, seq, ts}
CAPTURE_THREADS = {} # serial -> Thread
ACTIVE_UNTIL = {}    # serial -> monotonic deadline
CONDITIONS = {}      # serial -> Condition
GLOBAL_LOCK = threading.Lock()
LIMIT = threading.BoundedSemaphore(32)

DEFAULT_FPS = 5.0
DEFAULT_FRAME_WIDTH = 420
DEFAULT_JPEG_QUALITY = 55
IDLE_SECONDS = 4.0

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

def adb(*args, timeout=10):
    return subprocess.run(
        [CONFIG.get('adb_path', 'adb'), *args],
        capture_output=True,
        check=True,
        timeout=timeout,
        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0,
    ).stdout

def condition(serial):
    with GLOBAL_LOCK:
        return CONDITIONS.setdefault(serial, threading.Condition())

def capture_settings():
    fps = CONFIG.get('target_fps', DEFAULT_FPS)
    width = CONFIG.get('frame_width', DEFAULT_FRAME_WIDTH)
    quality = CONFIG.get('jpeg_quality', DEFAULT_JPEG_QUALITY)
    try:
        fps = max(1.0, min(8.0, float(fps)))
        width = max(240, min(720, int(width)))
        quality = max(35, min(80, int(quality)))
    except (TypeError, ValueError):
        fps, width, quality = DEFAULT_FPS, DEFAULT_FRAME_WIDTH, DEFAULT_JPEG_QUALITY
    return fps, width, quality

def encode_frame(raw):
    _, width, quality = capture_settings()
    with Image.open(io.BytesIO(raw)) as im:
        size = im.size
        im = im.convert('RGB')
        if im.width > width:
            height = max(1, round(im.height * width / im.width))
            im = im.resize((width, height), Image.Resampling.BILINEAR)
        output = io.BytesIO()
        im.save(output, 'JPEG', quality=quality)
    return output.getvalue(), size

def capture_once(serial):
    raw = adb('-s', serial, 'exec-out', 'screencap', '-p')
    return encode_frame(raw)

def publish_frame(serial, data, size):
    cond = condition(serial)
    with cond:
        previous = FRAMES.get(serial)
        # JPEG output is deterministic for the same screenshot. If nothing
        # changed, keep the same sequence so the browser does not re-download it.
        if previous and previous['data'] == data:
            previous['ts'] = time.monotonic()
            cond.notify_all()
            return previous['seq']
        seq = (previous['seq'] + 1) if previous else 1
        FRAMES[serial] = {'data': data, 'size': size, 'seq': seq, 'ts': time.monotonic()}
        cond.notify_all()
        return seq

def capture_worker(serial):
    fps, _, _ = capture_settings()
    interval = 1.0 / fps
    try:
        while time.monotonic() < ACTIVE_UNTIL.get(serial, 0):
            started = time.monotonic()
            try:
                data, size = capture_once(serial)
                publish_frame(serial, data, size)
            except (subprocess.SubprocessError, OSError, ValueError):
                # Keep the last good frame. A transient ADB hiccup should not
                # blank the screen in the browser.
                pass
            wait = interval - (time.monotonic() - started)
            if wait > 0:
                time.sleep(wait)
    finally:
        with GLOBAL_LOCK:
            current = CAPTURE_THREADS.get(serial)
            if current is threading.current_thread():
                CAPTURE_THREADS.pop(serial, None)

def ensure_capture(serial):
    ACTIVE_UNTIL[serial] = time.monotonic() + IDLE_SECONDS
    with GLOBAL_LOCK:
        thread = CAPTURE_THREADS.get(serial)
        if thread and thread.is_alive():
            return
        thread = threading.Thread(target=capture_worker, args=(serial,), daemon=True, name=f'nucel-{serial}')
        CAPTURE_THREADS[serial] = thread
        thread.start()

def wait_frame(serial, after=0, timeout=1.25):
    ensure_capture(serial)
    cond = condition(serial)
    deadline = time.monotonic() + timeout
    with cond:
        while True:
            current = FRAMES.get(serial)
            if current and current['seq'] > after:
                return current
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return current
            cond.wait(remaining)

def ensure_size(serial):
    current = FRAMES.get(serial)
    if current:
        return current['size']
    # First interaction can theoretically arrive before the first browser frame.
    data, size = capture_once(serial)
    publish_frame(serial, data, size)
    return size

def perform(serial, body):
    typ = body.get('type')
    if typ == 'key':
        keys = {'home':'3', 'back':'4', 'recent':'187'}
        if body.get('key') not in keys:
            raise ValueError('Invalid key')
        args = ['keyevent', keys[body['key']]]
    elif typ in ('tap', 'swipe'):
        width, height = ensure_size(serial)
        def coord(key, maximum):
            value = body.get(key)
            if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 1:
                raise ValueError('Invalid coordinate')
            return str(min(maximum - 1, round(value * maximum)))
        args = [typ, coord('x', width), coord('y', height)]
        if typ == 'swipe':
            duration = body.get('duration', 260)
            if type(duration) not in (int, float) or not math.isfinite(duration):
                raise ValueError('Invalid duration')
            args += [coord('x2', width), coord('y2', height), str(max(100, min(1200, int(duration))))]
    else:
        raise ValueError('Invalid action')

    # Input is intentionally independent from the capture loop. Waiting for a
    # screenshot before sending a tap was the biggest source of perceived lag.
    adb('-s', serial, 'shell', 'input', *args, timeout=5)
    ACTIVE_UNTIL[serial] = time.monotonic() + IDLE_SECONDS

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        self.connection.settimeout(15)

    def log_message(self, *_):
        pass  # Never log auth tokens, screen contents, or device IDs.

    def cors(self):
        if self.headers.get('Origin') == CONFIG['allowed_origin']:
            self.send_header('Access-Control-Allow-Origin', CONFIG['allowed_origin'])
            self.send_header('Access-Control-Expose-Headers', 'X-NuCel-Frame')
            self.send_header('Vary', 'Origin')

    def send(self, code, body=b'', mime='application/json', extra=None):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.cors()
        self.send_header('Content-Type', mime)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Length', str(len(body)))
        if extra:
            for key, value in extra.items():
                self.send_header(key, str(value))
        self.end_headers()
        if body:
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
        self.send_header('Content-Length', '0')
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

            params = parse_qs(url.query)
            serial = body.get('serial') if self.command == 'POST' else params.get('serial', [''])[0]
            if not isinstance(serial, str) or not re.fullmatch(r'[\w.:-]{1,100}', serial) or serial not in claims['serials']:
                return self.send(403, {'error':'Device not allowed'})

            if url.path == '/frame' and self.command == 'GET':
                try:
                    after = max(0, int(params.get('after', ['0'])[0]))
                except ValueError:
                    after = 0
                current = wait_frame(serial, after)
                if not current:
                    return self.send(503, {'error':'Device unavailable'})
                if current['seq'] <= after:
                    return self.send(204, b'', 'application/octet-stream', {'X-NuCel-Frame': current['seq']})
                return self.send(200, current['data'], 'image/jpeg', {'X-NuCel-Frame': current['seq']})

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

    fps, width, quality = capture_settings()
    print(f'NuCel pronto em 127.0.0.1:8765 | captura alvo: {fps:g} FPS, largura {width}px, JPEG {quality}.')
    print('Mantenha esta janela aberta e o tunel HTTPS apontando para http://127.0.0.1:8765.')
    ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
