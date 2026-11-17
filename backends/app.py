#!/usr/bin/env python3
"""Lab backend: reports which app answered and the headers NGINX forwarded."""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = sys.argv[1]
PORT = int(sys.argv[2])


class Handler(BaseHTTPRequestHandler):
    server_version = "LabBackend"   # hide Python version in replies
    sys_version = ""

    def do_GET(self):
        body = json.dumps({
            "app": NAME,
            "path": self.path,
            "connection_from": self.client_address[0],
            "host": self.headers.get("Host"),
            "x_real_ip": self.headers.get("X-Real-IP"),
            "x_forwarded_for": self.headers.get("X-Forwarded-For"),
            "x_forwarded_proto": self.headers.get("X-Forwarded-Proto"),
        }, indent=2).encode() + b"\n"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
