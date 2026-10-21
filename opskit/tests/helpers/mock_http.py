import fnmatch
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[1]
PORT_FILE = sys.argv[2]
RESPONSES = sys.argv[3] if len(sys.argv) > 3 else ""


def reply_for(method, path):
    if not RESPONSES or not os.path.exists(RESPONSES):
        return 200, '{"ok":true}'
    with open(RESPONSES) as handle:
        table = json.load(handle)
    for pattern, answer in table.items():
        if fnmatch.fnmatchcase(method + " " + path, pattern):
            body = answer.get("body", {})
            return answer.get("status", 200), body if isinstance(body, str) else json.dumps(body)
    return 404, '{"message":"not mocked"}'


class Recorder(BaseHTTPRequestHandler):
    def record(self, method):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length).decode(errors="replace") if length else ""
        with open(LOG, "a") as handle:
            handle.write(json.dumps({"method": method, "path": self.path, "body": body,
                                     "authorization": self.headers.get("authorization", "")}) + "\n")
        status, payload = reply_for(method, self.path)
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.end_headers()
        self.wfile.write(payload.encode())

    def do_GET(self):
        self.record("GET")

    def do_POST(self):
        self.record("POST")

    def do_DELETE(self):
        self.record("DELETE")

    def log_message(self, *args):
        pass


server = HTTPServer((os.environ.get("MOCK_BIND", "127.0.0.1"), 0), Recorder)
with open(PORT_FILE, "w") as handle:
    handle.write(str(server.server_port))
server.serve_forever()
