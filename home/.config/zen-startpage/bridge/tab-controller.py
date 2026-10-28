#!/usr/bin/python3
"""Native host: activate existing pinned tabs through signed BroTab.

Firefox owns this process. No tab content is read; no tab is opened or closed.
The browser-chrome Home command is separate and requires no HTTP request.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import base64
import hmac
import json
import queue
import struct
import sys
import threading
import time

PORT = 8767
CONFIG = Path.home() / 'Library/Application Support/ZenCalendarBridge/config.json'


def site(value):
    try:
        url = urlsplit(value)
        if url.scheme not in ('http', 'https') or not url.hostname or url.username or url.password:
            return None
        return (url.hostname.lower().removeprefix('www.'), url.port)
    except (ValueError, TypeError):
        return None


class Native:
    def __init__(self):
        self.responses = queue.Queue()
        self.lock = threading.Lock()

    def command(self, message, accept):
        raw = json.dumps(message, separators=(',', ':')).encode()
        sys.stdout.buffer.write(struct.pack('<I', len(raw)) + raw)
        sys.stdout.buffer.flush()
        deadline = time.monotonic() + 2
        while True:
            response = self.responses.get(timeout=max(.001, deadline - time.monotonic()))
            if accept(response):
                return response
            if time.monotonic() >= deadline:
                raise queue.Empty()

    def activate(self, url):
        target = site(url)
        if target is None:
            return False
        query = base64.b64encode(json.dumps({'pinned': True, 'hidden': False, 'lastFocusedWindow': True}).encode()).decode()
        with self.lock:
            lines = self.command({'name': 'query_tabs', 'query_info': query},
                                 lambda value: isinstance(value, list) and all(isinstance(line, str) and '\t' in line for line in value))
            candidates = []
            for line in lines:
                identifier = line.split('\t', 1)[0]
                address = line.rsplit('\t', 1)[-1]
                parts = identifier.split('.')
                if len(parts) == 2 and all(part.isdecimal() for part in parts) and site(address) == target:
                    candidates.append((identifier, address))
            if not candidates:
                return False
            # BroTab preserves the browser's index order; Essentials precede workspace pins.
            identifier, _ = candidates[0]
            tab_id = int(identifier.split('.')[1])
            self.command({'name': 'update_tabs', 'updates': [{'tab_id': tab_id, 'properties': {'active': True}}]},
                         lambda value: value == [identifier])
        return True


def handler(native, token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def send_json(self, code, body):
            raw = json.dumps(body).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Length', str(len(raw)))
            if self.headers.get('Origin') == 'null':
                self.send_header('Access-Control-Allow-Origin', 'null')
                self.send_header('Vary', 'Origin')
                self.send_header('Access-Control-Allow-Methods', 'GET, POST')
                self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
                self.send_header('Access-Control-Allow-Private-Network', 'true')
            self.end_headers()
            self.wfile.write(raw)

        def valid_source(self):
            return self.headers.get('Host') == f'127.0.0.1:{PORT}' and self.headers.get('Origin') in (None, 'null')

        def authorized(self):
            return hmac.compare_digest(self.headers.get('Authorization', '').encode(), ('Bearer ' + token).encode())

        def do_OPTIONS(self):
            requested = {part.strip().lower() for part in self.headers.get('Access-Control-Request-Headers', '').split(',') if part.strip()}
            if not self.valid_source() or self.headers.get('Origin') != 'null' or self.headers.get('Access-Control-Request-Method') not in ('GET', 'POST') or not requested <= {'authorization', 'content-type'}:
                self.send_json(403, {'error': 'forbidden'})
                return
            self.send_json(200, {})

        def do_GET(self):
            if not self.valid_source():
                self.send_json(403, {'error': 'forbidden'})
            elif not self.authorized():
                self.send_json(401, {'error': 'unauthorized'})
            elif self.path == '/v1/status':
                self.send_json(200, {'ready': True})
            else:
                self.send_json(404, {'error': 'not_found'})

        def do_POST(self):
            if not self.valid_source():
                self.send_json(403, {'error': 'forbidden'}); return
            if not self.authorized():
                self.send_json(401, {'error': 'unauthorized'}); return
            if self.path != '/v1/activate-pin':
                self.send_json(404, {'error': 'not_found'}); return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 8192 or self.headers.get('Transfer-Encoding') or self.headers.get_content_type() != 'application/json':
                    raise ValueError()
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict) or set(body) != {'url'} or not isinstance(body['url'], str) or not site(body['url']):
                    raise ValueError()
            except (ValueError, TypeError):
                self.send_json(400, {'error': 'invalid_request'}); return
            started = time.perf_counter()
            try:
                active = native.activate(body['url'])
                self.send_json(200 if active else 404, {'ok': active, 'elapsedMs': round((time.perf_counter() - started) * 1000, 1)})
            except (queue.Empty, BrokenPipeError, OSError):
                self.send_json(503, {'error': 'browser_unavailable'})
    return Handler


def main():
    credential = json.loads(CONFIG.read_text())['token']
    native = Native()
    server = ThreadingHTTPServer(('127.0.0.1', PORT), handler(native, credential))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        while True:
            header = sys.stdin.buffer.read(4)
            if len(header) != 4:
                break
            size = struct.unpack('<I', header)[0]
            if not 0 < size <= 4 * 1024 * 1024:
                break
            data = sys.stdin.buffer.read(size)
            if len(data) != size:
                break
            native.responses.put(json.loads(data))
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
