"""NuCel connector: low-latency Android streaming + scoped remote control. Python 3.10+."""
import base64, hashlib, hmac, io, json, math, re, struct, subprocess, sys, threading, time
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import av
from av.error import FFmpegError
from PIL import Image

CONFIG = {}
GLOBAL_LOCK = threading.Lock()
LIMIT = threading.BoundedSemaphore(32)

# Fallback still-image cache used by /frame and by tests.
FRAMES = {}
LOCKS = {}

# Continuous H.264 -> JPEG stream sessions, one per active Android device.
STREAMS = {}

DEFAULT_STREAM_FPS = 10.0
DEFAULT_FRAME_WIDTH = 420
DEFAULT_JPEG_QUALITY = 55
DEFAULT_VIDEO_BITRATE = 3_000_000
STREAM_IDLE_SECONDS = 8.0
STREAM_HTTP_SECONDS = 45.0


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


def popen_adb(*args):
    return subprocess.Popen(
        [CONFIG.get('adb_path', 'adb'), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0,
    )


def device_lock(serial):
    with GLOBAL_LOCK:
        return LOCKS.setdefault(serial, threading.Lock())


def still_frame(serial):
    with device_lock(serial):
        previous = FRAMES.get(serial)
        if previous and time.monotonic() - previous[0] < .35:
            return previous[1], previous[2]
        raw = adb('-s', serial, 'exec-out', 'screencap', '-p')
        with Image.open(io.BytesIO(raw)) as im:
            size = im.size
            im = im.convert('RGB')
            im.thumbnail((420, 1000))
            output = io.BytesIO()
            im.save(output, 'JPEG', quality=55)
        data = output.getvalue()
        FRAMES[serial] = (time.monotonic(), data, size)
        return data, size


def parse_wm_size(serial):
    try:
        out = adb('-s', serial, 'shell', 'wm', 'size', timeout=4).decode(errors='replace')
        values = re.findall(r'(\d+)x(\d+)', out)
        if values:
            w, h = values[-1]
            return int(w), int(h)
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    return None


class VideoSession:
    def __init__(self, serial):
        self.serial = serial
        self.cond = threading.Condition()
        self.thread = None
        self.process = None
        self.latest = None
        self.seq = 0
        self.size = None
        self.active_until = 0.0
        self.last_error = None

    def settings(self):
        try:
            fps = max(4.0, min(15.0, float(CONFIG.get('target_fps', DEFAULT_STREAM_FPS))))
            width = max(280, min(720, int(CONFIG.get('frame_width', DEFAULT_FRAME_WIDTH))))
            quality = max(35, min(80, int(CONFIG.get('jpeg_quality', DEFAULT_JPEG_QUALITY))))
            bitrate = max(1_000_000, min(8_000_000, int(CONFIG.get('video_bitrate', DEFAULT_VIDEO_BITRATE))))
        except (TypeError, ValueError):
            fps, width, quality, bitrate = (
                DEFAULT_STREAM_FPS,
                DEFAULT_FRAME_WIDTH,
                DEFAULT_JPEG_QUALITY,
                DEFAULT_VIDEO_BITRATE,
            )
        return fps, width, quality, bitrate

    def touch(self):
        self.active_until = time.monotonic() + STREAM_IDLE_SECONDS
        with GLOBAL_LOCK:
            if self.thread and self.thread.is_alive():
                return
            self.thread = threading.Thread(
                target=self.run,
                daemon=True,
                name=f'nucel-video-{self.serial}',
            )
            self.thread.start()

    def publish(self, data, size):
        with self.cond:
            # Avoid retransmitting an identical screen.
            if self.latest == data:
                self.cond.notify_all()
                return
            self.latest = data
            self.size = size
            self.seq += 1
            self.last_error = None
            self.cond.notify_all()

    def wait_after(self, seq, timeout=1.5):
        self.touch()
        deadline = time.monotonic() + timeout
        with self.cond:
            while self.seq <= seq and time.monotonic() < deadline:
                self.cond.wait(deadline - time.monotonic())
            return self.seq, self.latest, self.size

    def terminate_process(self):
        p = self.process
        self.process = None
        if p and p.poll() is None:
            try:
                p.kill()
            except OSError:
                pass

    def run(self):
        fps, width, quality, bitrate = self.settings()
        frame_interval = 1.0 / fps

        try:
            while time.monotonic() < self.active_until:
                self.terminate_process()
                process = popen_adb(
                    '-s', self.serial, 'exec-out',
                    'screenrecord',
                    '--output-format=h264',
                    '--bit-rate', str(bitrate),
                    '-'
                )
                self.process = process
                last_emit = 0.0

                try:
                    if not process.stdout:
                        raise OSError('No video stdout')
                    container = av.open(process.stdout, mode='r', format='h264')

                    for packet_frame in container.decode(video=0):
                        if time.monotonic() >= self.active_until:
                            break
                        now = time.monotonic()
                        if now - last_emit < frame_interval:
                            continue
                        last_emit = now

                        img = packet_frame.to_image().convert('RGB')
                        full_size = img.size
                        if img.width > width:
                            new_h = max(1, round(img.height * width / img.width))
                            img = img.resize((width, new_h), Image.Resampling.BILINEAR)
                        output = io.BytesIO()
                        img.save(output, 'JPEG', quality=quality, optimize=False)
                        self.publish(output.getvalue(), full_size)

                except (FFmpegError, OSError, subprocess.SubprocessError, ValueError) as exc:
                    self.last_error = str(exc)
                finally:
                    try:
                        container.close()
                    except Exception:
                        pass
                    self.terminate_process()

                # Android screenrecord can exit after a device-defined time limit.
                # Restart seamlessly while the browser still has this screen open.
                if time.monotonic() < self.active_until:
                    time.sleep(.15)
        finally:
            self.terminate_process()
            with GLOBAL_LOCK:
                current = STREAMS.get(self.serial)
                if current is self:
                    # Keep the latest frame around briefly, but allow a new
                    # process to start cleanly the next time the screen opens.
                    self.thread = None


def video_session(serial):
    with GLOBAL_LOCK:
        session = STREAMS.get(serial)
        if session is None:
            session = VideoSession(serial)
            STREAMS[serial] = session
        return session


def device_size(serial):
    session = STREAMS.get(serial)
    if session and session.size:
        return session.size
    size = parse_wm_size(serial)
    if size:
        return size
    return still_frame(serial)[1]


def perform(serial, body):
    typ = body.get('type')
    if typ == 'key':
        keys = {'home': '3', 'back': '4', 'recent': '187'}
        if body.get('key') not in keys:
            raise ValueError('Invalid key')
        args = ['keyevent', keys[body['key']]]
    elif typ in ('tap', 'swipe'):
        width, height = device_size(serial)

        def coord(key, maximum):
            value = body.get(key)
            if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 1:
                raise ValueError('Invalid coordinate')
            return str(min(maximum - 1, round(value * maximum)))

        args = [typ, coord('x', width), coord('y', height)]
        if typ == 'swipe':
            duration = body.get('duration', 220)
            if type(duration) not in (int, float) or not math.isfinite(duration):
                raise ValueError('Invalid duration')
            args += [
                coord('x2', width),
                coord('y2', height),
                str(max(80, min(1000, int(duration)))),
            ]
    else:
        raise ValueError('Invalid action')

    # Do not serialize input with screen capture. This is deliberate: a tap
    # should reach Android immediately even if a video frame is being decoded.
    adb('-s', serial, 'shell', 'input', *args, timeout=5)

    session = STREAMS.get(serial)
    if session:
        session.active_until = time.monotonic() + STREAM_IDLE_SECONDS


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        self.connection.settimeout(20)

    def log_message(self, *_):
        pass  # Never log tokens, screen contents, or serial numbers.

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

    def validate_serial(self, claims, serial):
        return (
            isinstance(serial, str)
            and re.fullmatch(r'[\w.:-]{1,100}', serial)
            and serial in claims['serials']
        )

    def stream_video(self, serial):
        session = video_session(serial)
        session.touch()

        self.send_response(200)
        self.cors()
        self.send_header('Content-Type', 'application/x-nucel-jpeg-stream')
        self.send_header('Cache-Control', 'no-store, no-transform')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Connection', 'close')
        self.end_headers()

        seq = 0
        deadline = time.monotonic() + STREAM_HTTP_SECONDS
        last_heartbeat = time.monotonic()

        try:
            while time.monotonic() < deadline:
                session.active_until = time.monotonic() + STREAM_IDLE_SECONDS
                next_seq, data, _ = session.wait_after(seq, timeout=1.0)

                if data is not None and next_seq > seq:
                    packet = struct.pack('>I', len(data)) + data
                    self.wfile.write(packet)
                    self.wfile.flush()
                    seq = next_seq
                    last_heartbeat = time.monotonic()
                elif time.monotonic() - last_heartbeat > 2.0:
                    # Zero-length heartbeat keeps proxies/tunnels from treating
                    # an unchanged Android screen as an idle connection.
                    self.wfile.write(struct.pack('>I', 0))
                    self.wfile.flush()
                    last_heartbeat = time.monotonic()
        except (BrokenPipeError, ConnectionResetError, TimeoutError, OSError):
            pass
        finally:
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
            if not self.validate_serial(claims, serial):
                return self.send(403, {'error': 'Device not allowed'})

            if url.path == '/stream' and self.command == 'GET':
                return self.stream_video(serial)

            # /frame remains as a safe fallback and for diagnostics.
            if url.path == '/frame' and self.command == 'GET':
                return self.send(200, still_frame(serial)[0], 'image/jpeg')

            if url.path == '/action' and self.command == 'POST':
                perform(serial, body)
                return self.send(200, {'ok': True})

            return self.send(404, {'error': 'Not found'})

        except (ValueError, KeyError, TypeError):
            self.send(400, {'error': 'Invalid request'})
        except (subprocess.SubprocessError, OSError, FFmpegError):
            self.send(503, {'error': 'Device unavailable'})
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

    print(
        'NuCel STREAM pronto em 127.0.0.1:8765 | '
        f'alvo {CONFIG.get("target_fps", DEFAULT_STREAM_FPS)} FPS | '
        'video continuo H.264 -> JPEG.'
    )
    print('Mantenha esta janela aberta e o tunel HTTPS apontando para http://127.0.0.1:8765.')
    ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
