#!/usr/bin/python3
from http.server import BaseHTTPRequestHandler,HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body=b'<!doctype html><title>TaskENV web test</title><h1>TaskENV desktop</h1><button id="counter" onclick="this.textContent=Number(this.textContent)+1">0</button><input id="clipboard">'
        self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(body)
HTTPServer(('0.0.0.0',3000),Handler).serve_forever()
