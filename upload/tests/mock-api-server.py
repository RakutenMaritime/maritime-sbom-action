#!/usr/bin/env python3
"""Minimal one-shot mock API server for SBOM upload tests.

Usage: mock-api-server.py <body_out> <header_out> [status]

Binds an ephemeral port, prints it to stdout, then handles a single POST
request: it records the request body to <body_out> and selected headers to
<header_out>, responds with HTTP <status> (default 200), and exits. A timeout
guards against hanging if no request ever arrives.
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

body_out = sys.argv[1]
header_out = sys.argv[2]
status = int(sys.argv[3]) if len(sys.argv) > 3 else 200


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        data = self.rfile.read(length) if length else b''
        with open(body_out, 'wb') as f:
            f.write(data)
        with open(header_out, 'w') as f:
            f.write((self.headers.get('X-Api-Key', '') or '') + '\n')
            f.write((self.headers.get('Content-Type', '') or '') + '\n')
        self.send_response(status)
        self.end_headers()
        self.wfile.write(b'ok')

    def log_message(self, *args):
        pass


httpd = HTTPServer(('0.0.0.0', 0), Handler)
httpd.timeout = 20
print(httpd.server_address[1], flush=True)
httpd.handle_request()
