import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[1]
PORT_FILE = sys.argv[2]


class Recorder(BaseHTTPRequestHandler):
    def record(self, method):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        with open(LOG, "a") as handle:
            handle.write(json.dumps({"method": method, "path": self.path, "body": body}) + "\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def do_GET(self):
        self.record("GET")

    def do_POST(self):
        self.record("POST")

    def log_message(self, *args):
        pass


server = HTTPServer(("127.0.0.1", 0), Recorder)
with open(PORT_FILE, "w") as handle:
    handle.write(str(server.server_port))
server.serve_forever()
