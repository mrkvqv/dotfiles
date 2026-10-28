#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import json
import secrets
import sys
sys.dont_write_bytecode = True
import threading
import unittest
import urllib.error
import urllib.request

spec = importlib.util.spec_from_file_location('tab_controller', Path(__file__).with_name('tab-controller.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ControllerTests(unittest.TestCase):
    def test_only_existing_pin_is_activated(self):
        native = module.Native()
        commands = []
        def command(message, accept):
            commands.append(message)
            value = ['1.11\tVideo title\thttps://www.youtube.com/watch?v=keep-playing', '1.12\tOther pin\thttps://www.youtube.com/'] if message['name'] == 'query_tabs' else ['1.11']
            self.assertTrue(accept(value))
            return value
        native.command = command
        self.assertTrue(native.activate('https://www.youtube.com/'))
        self.assertEqual([item['name'] for item in commands], ['query_tabs', 'update_tabs'])
        self.assertEqual(commands[1]['updates'], [{'tab_id':11,'properties':{'active':True}}])
        self.assertIsNone(module.site('javascript:alert(1)'))
        self.assertIsNone(module.site('https://example.org:invalid/'))

    def test_no_pin_means_no_create(self):
        native = module.Native(); commands = []
        native.command = lambda message, accept: commands.append(message) or []
        self.assertFalse(native.activate('https://absent.example/'))
        self.assertEqual([item['name'] for item in commands], ['query_tabs'])

    def test_local_http_access(self):
        class FakeNative:
            def activate(self, url): return url == 'https://existing.example/'
        credential = secrets.token_urlsafe(32)
        server = module.ThreadingHTTPServer(('127.0.0.1',0), module.handler(FakeNative(),credential))
        old_port = module.PORT; module.PORT = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        def request(path, body=None, extra=None, authorized=True, method=None):
            headers = {'Content-Type':'application/json','Origin':'null'}
            if authorized:headers['Authorization']='Bearer '+credential
            headers.update(extra or {})
            req=urllib.request.Request('http://127.0.0.1:'+str(module.PORT)+path, data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method)
            try:r=urllib.request.urlopen(req,timeout=2)
            except urllib.error.HTTPError as error:r=error
            return r.status,r.read(),r.headers
        try:
            self.assertEqual(request('/v1/status',authorized=False)[0],401)
            self.assertEqual(request('/v1/status',extra={'Origin':'https://evil.example'})[0],403)
            self.assertEqual(request('/v1/status',extra={'Host':'evil.example'})[0],403)
            self.assertEqual(request('/v1/home',{},authorized=False)[0],401)
            self.assertEqual(request('/v1/home',{})[0],404)
            self.assertEqual(request('/v1/activate-pin',{'url':'javascript:alert(1)'})[0],400)
            self.assertEqual(request('/v1/activate-pin',{'url':'https://existing.example/','command':'get_html'})[0],400)
            self.assertEqual(request('/v1/activate-pin',{'url':'https://absent.example/'})[0],404)
            code,body,headers=request('/v1/activate-pin',{'url':'https://existing.example/'})
            self.assertEqual(code,200);self.assertTrue(json.loads(body)['ok'])
            self.assertEqual(headers['Cache-Control'],'no-store')
            self.assertEqual(request('/v1/activate-pin',extra={'Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'authorization,content-type'},authorized=False,method='OPTIONS')[0],200)
        finally:
            server.shutdown();server.server_close();module.PORT=old_port

if __name__ == '__main__':unittest.main()
