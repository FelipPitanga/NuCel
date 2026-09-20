"""NuCel connector: scrcpy H.264 passthrough + persistent ADB controls. Python 3.10+."""
import base64, hashlib, hmac, json, math, re, socket, struct, subprocess, sys, threading, time
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

CONFIG = {}
GLOBAL_LOCK = threading.Lock()
LIMIT = threading.BoundedSemaphore(32)
ACTIVE_STREAMS = {}
PUSHED = set()
VIDEO_SIZES = {}
CONTROL_SHELLS = {}
STREAM_MAX_SECONDS = 45.0


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


def adb_popen(*args, stdin=None, stdout=None, stderr=None, text=False):
    return subprocess.Popen(
        [CONFIG.get('adb_path', 'adb'), *args],
        stdin=stdin, stdout=stdout, stderr=stderr, text=text,
        bufsize=0 if not text else 1,
        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0,
    )


def exact_read(sock, size):
    chunks = []
    remaining = size
    while remaining:
        data = sock.recv(remaining)
        if not data:
            raise ConnectionError('scrcpy stream closed')
        chunks.append(data)
        remaining -= len(data)
    return b''.join(chunks)


def free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


def server_path():
    configured = CONFIG.get('scrcpy_server_path')
    candidates = []
    if configured:
        candidates.append(Path(configured))
    adb_path = Path(CONFIG.get('adb_path', 'adb'))
    if adb_path.name.lower() != 'adb':
        candidates.append(adb_path.with_name('scrcpy-server'))
    candidates.extend([
        Path(__file__).resolve().parents[2] / 'scrcpy-server',
        Path(__file__).resolve().parent / 'scrcpy-server',
        Path.cwd() / 'scrcpy-server',
    ])
    for path in candidates:
        if path.exists() and path.is_file():
            return path
    raise FileNotFoundError('scrcpy-server nao encontrado ao lado do adb.exe')


def push_server(serial):
    with GLOBAL_LOCK:
        if serial in PUSHED:
            return
    path = server_path()
    adb('-s', serial, 'push', str(path), '/data/local/tmp/nucel-scrcpy-server.jar', timeout=20)
    with GLOBAL_LOCK:
        PUSHED.add(serial)


class ControlShell:
    def __init__(self, serial):
        self.serial = serial
        self.lock = threading.Lock()
        self.proc = None

    def ensure(self):
        if self.proc and self.proc.poll() is None and self.proc.stdin:
            return
        self.close()
        self.proc = adb_popen(
            '-s', self.serial, 'shell',
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, text=True,
        )
        if not self.proc.stdin:
            raise OSError('ADB shell indisponivel')

    def send(self, command):
        with self.lock:
            self.ensure()
            try:
                self.proc.stdin.write(command + '\n')
                self.proc.stdin.flush()
            except (OSError, BrokenPipeError):
                self.close()
                self.ensure()
                self.proc.stdin.write(command + '\n')
                self.proc.stdin.flush()

    def close(self):
        proc, self.proc = self.proc, None
        if proc and proc.poll() is None:
            try:
                proc.kill()
            except OSError:
                pass


def control_shell(serial):
    with GLOBAL_LOCK:
        shell = CONTROL_SHELLS.get(serial)
        if shell is None:
            shell = ControlShell(serial)
            CONTROL_SHELLS[serial] = shell
        return shell


class ScrcpyStream:
    def __init__(self, serial):
        self.serial = serial
        self.port = None
        self.server_proc = None
        self.sock = None
        self.closed = False

    def stop(self):
        self.closed = True
        sock, self.sock = self.sock, None
        if sock:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                sock.close()
            except OSError:
                pass
        proc, self.server_proc = self.server_proc, None
        if proc and proc.poll() is None:
            try:
                proc.kill()
            except OSError:
                pass
        if self.port:
            try:
                adb('-s', self.serial, 'forward', '--remove', f'tcp:{self.port}', timeout=4)
            except Exception:
                pass
            self.port = None

    def start(self):
        push_server(self.serial)
        self.port = free_port()
        adb('-s', self.serial, 'forward', f'tcp:{self.port}', 'localabstract:scrcpy', timeout=5)

        version = str(CONFIG.get('scrcpy_server_version', '4.1'))
        max_size = max(360, min(1080, int(CONFIG.get('max_size', 720))))
        max_fps = max(10, min(60, int(CONFIG.get('max_fps', 30))))
        bitrate = max(1_000_000, min(12_000_000, int(CONFIG.get('video_bitrate', 3_000_000))))

        args = [
            '-s', self.serial, 'shell',
            'CLASSPATH=/data/local/tmp/nucel-scrcpy-server.jar',
            'app_process', '/', 'com.genymobile.scrcpy.Server', version,
            'tunnel_forward=true', 'audio=false', 'control=false', 'cleanup=false',
            'send_device_meta=false', 'send_dummy_byte=false', 'send_stream_meta=false',
            'video_codec=h264', f'max_size={max_size}', f'max_fps={max_fps}',
            f'video_bit_rate={bitrate}', 'log_level=warn',
        ]
        self.server_proc = adb_popen(*args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        deadline = time.monotonic() + 5.0
        last = None
        while time.monotonic() < deadline:
            if self.server_proc.poll() is not None:
                raise OSError('scrcpy-server encerrou antes de conectar')
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2.0)
            try:
                s.connect(('127.0.0.1', self.port))
                s.settimeout(10.0)
                self.sock = s
                return
            except OSError as exc:
                last = exc
                s.close()
                time.sleep(.08)
        raise OSError(f'nao conectou ao scrcpy-server: {last}')

    def packets(self):
        if not self.sock:
            raise OSError('stream nao iniciado')
        while not self.closed:
            header = exact_read(self.sock, 12)

            if header[0] & 0x80:
                width = int.from_bytes(header[4:8], 'big')
                height = int.from_bytes(header[8:12], 'big')
                if 0 < width <= 8192 and 0 < height <= 8192:
                    VIDEO_SIZES[self.serial] = (width, height)
                    yield 1, 0, struct.pack('>II', width, height)
                continue

            pts_flags = int.from_bytes(header[:8], 'big')
            size = int.from_bytes(header[8:12], 'big')
            if size <= 0 or size > 8_000_000:
                raise ValueError('pacote de video invalido')
            data = exact_read(self.sock, size)

            is_config = bool(pts_flags & (1 << 62))
            is_key = bool(pts_flags & (1 << 61))
            pts = pts_flags & ((1 << 61) - 1)
            yield 2 if is_config else (3 if is_key else 4), pts, data


def display_size(serial):
    size = VIDEO_SIZES.get(serial)
    if size:
        return size
    out = adb('-s', serial, 'shell', 'wm', 'size', timeout=4).decode(errors='replace')
    matches = re.findall(r'(\d+)x(\d+)', out)
    if not matches:
        raise ValueError('tamanho do aparelho indisponivel')
    width, height = matches[-1]
    return int(width), int(height)


def perform(serial, body):
    typ = body.get('type')
    if typ == 'key':
        keys = {'home': 3, 'back': 4, 'recent': 187}
        key = body.get('key')
        if key not in keys:
            raise ValueError('Invalid key')
        command = f'input keyevent {keys[key]}'
    elif typ in ('tap', 'swipe'):
        width, height = display_size(serial)

        def coord(name, maximum):
            value = body.get(name)
            if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 1:
                raise ValueError('Invalid coordinate')
            return min(maximum - 1, round(value * maximum))

        x, y = coord('x', width), coord('y', height)
        if typ == 'tap':
            command = f'input tap {x} {y}'
        else:
            x2, y2 = coord('x2', width), coord('y2', height)
            duration = body.get('duration', 160)
            if type(duration) not in (int, float) or not math.isfinite(duration):
                raise ValueError('Invalid duration')
            command = f'input swipe {x} {y} {x2} {y2} {max(50, min(800, int(duration)))}'
    else:
        raise ValueError('Invalid action')
    control_shell(serial).send(command)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        self.connection.settimeout(20)

    def log_message(self, *_):
        pass

    def cors(self):
        if self.headers.get('Origin') == CONFIG['allowed_origin']:
            self.send_header('Access-Control-Allow-Origin', CONFIG['allowed_origin'])
            self.send_header('Vary', 'Origin')

    def send(self, code, body=b'', mime='application/json'):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.cors()
        self.send_header('Content-Type', mime)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_OPTIONS(self):
        if self.headers.get('Origin') != CONFIG['allowed_origin']:
            return self.send(403, {'error': 'Origin denied'})
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

    def authenticate(self):
        origin = self.headers.get('Origin', '')
        token = self.headers.get('Authorization', '')
        if not token.startswith('Bearer ') or len(token) > 20000:
            raise ValueError('Unauthorized')
        return validate_token(token[7:], origin)

    @staticmethod
    def serial_allowed(claims, serial):
        return isinstance(serial, str) and re.fullmatch(r'[\w.:-]{1,100}', serial) and serial in claims['serials']

    def video_stream(self, serial):
        stream = ScrcpyStream(serial)
        with GLOBAL_LOCK:
            old = ACTIVE_STREAMS.get(serial)
            ACTIVE_STREAMS[serial] = stream
        if old:
            old.stop()

        try:
            stream.start()
            self.send_response(200)
            self.cors()
            self.send_header('Content-Type', 'application/x-nucel-h264')
            self.send_header('Cache-Control', 'no-store, no-transform')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Connection', 'close')
            self.end_headers()

            deadline = time.monotonic() + STREAM_MAX_SECONDS
            for kind, pts, payload in stream.packets():
                if time.monotonic() >= deadline:
                    break
                self.wfile.write(bytes([kind]) + struct.pack('>QI', pts, len(payload)))
                if payload:
                    self.wfile.write(payload)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, TimeoutError, OSError, ValueError):
            pass
        finally:
            stream.stop()
            with GLOBAL_LOCK:
                if ACTIVE_STREAMS.get(serial) is stream:
                    ACTIVE_STREAMS.pop(serial, None)
            self.close_connection = True

    def handle_request(self):
        try:
            claims = self.authenticate()
        except (ValueError, KeyError, TypeError):
            return self.send(401, {'error': 'Unauthorized'})

        if not LIMIT.acquire(blocking=False):
            return self.send(429, {'error': 'Busy'})

        try:
            url = urlparse(self.path)
            if url.path == '/status' and self.command == 'GET':
                lines = adb('devices').decode(errors='replace').splitlines()[1:]
                visible = {}
                for line in lines:
                    values = line.split()
                    if len(values) >= 2 and values[0] in claims['serials']:
                        visible[values[0]] = values[1]
                return self.send(200, {'devices': visible})

            body = {}
            if self.command == 'POST':
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 4096:
                    return self.send(413, {'error': 'Invalid payload'})
                body = json.loads(self.rfile.read(size))
                if not isinstance(body, dict):
                    raise ValueError('Invalid payload')

            params = parse_qs(url.query)
            serial = body.get('serial') if self.command == 'POST' else params.get('serial', [''])[0]
            if not self.serial_allowed(claims, serial):
                return self.send(403, {'error': 'Device not allowed'})

            if url.path == '/video' and self.command == 'GET':
                return self.video_stream(serial)
            if url.path == '/action' and self.command == 'POST':
                perform(serial, body)
                return self.send(200, {'ok': True})
            return self.send(404, {'error': 'Not found'})

        except (ValueError, KeyError, TypeError):
            self.send(400, {'error': 'Invalid request'})
        except (subprocess.SubprocessError, OSError):
            self.send(503, {'error': 'Device unavailable'})
        finally:
            LIMIT.release()


if __name__ == '__main__':
    config_path = Path(__file__).with_name('config.json')
    if not config_path.exists():
        raise SystemExit('Copie config.example.json para config.json e configure sua conexao primeiro.')
    CONFIG.update(json.loads(config_path.read_text(encoding='utf-8-sig')))

    if len(CONFIG.get('secret', '')) < 60 or 'COLE_' in CONFIG.get('secret', ''):
        raise SystemExit('Cole a chave gerada no painel NuCel no campo secret.')
    if not CONFIG.get('allowed_origin', '').startswith('https://'):
        raise SystemExit('Informe o endereco HTTPS do painel em allowed_origin, sem barra no final.')

    try:
        adb('version')
        path = server_path()
    except (OSError, subprocess.SubprocessError, FileNotFoundError) as exc:
        raise SystemExit(f'ADB/scrcpy-server nao encontrado: {exc}')

    print('NuCel DIRECT pronto em 127.0.0.1:8765.')
    print(f'scrcpy-server: {path}')
    print('Video: H.264 nativo do scrcpy -> Chrome WebCodecs. Sem JPEG/PyAV.')
    print('Controle: ADB shell persistente. Mantenha esta janela e o tunel HTTPS abertos.')
    ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
