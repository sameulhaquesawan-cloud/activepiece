import base64
import json
import socketserver
import sys

LOG = sys.argv[1]
PORT_FILE = sys.argv[2]


class Session(socketserver.StreamRequestHandler):
    def reply(self, line):
        self.wfile.write((line + "\r\n").encode())

    def handle(self):
        mail = {"from": "", "rcpt": [], "data": "", "auth": ""}
        self.reply("220 mock ESMTP")
        while True:
            raw = self.rfile.readline()
            if not raw:
                return
            line = raw.decode().rstrip("\r\n")
            verb = line.split(" ")[0].upper()
            if verb in ("EHLO", "HELO"):
                self.wfile.write(b"250-mock\r\n250 AUTH PLAIN\r\n")
            elif verb == "AUTH":
                parts = line.split(" ")
                if len(parts) < 3:
                    self.reply("334 ")
                    parts.append(self.rfile.readline().decode().strip())
                mail["auth"] = base64.b64decode(parts[2]).decode().split("\0", 1)[1].replace("\0", ":")
                self.reply("235 ok")
            elif verb == "MAIL":
                mail["from"] = line.split(":", 1)[1].strip()
                self.reply("250 ok")
            elif verb == "RCPT":
                mail["rcpt"].append(line.split(":", 1)[1].strip())
                self.reply("250 ok")
            elif verb == "DATA":
                self.reply("354 go")
                body = []
                while True:
                    part = self.rfile.readline().decode()
                    if part.rstrip("\r\n") == ".":
                        break
                    body.append(part)
                mail["data"] = "".join(body)
                with open(LOG, "a") as handle:
                    handle.write(json.dumps(mail) + "\n")
                self.reply("250 queued")
            elif verb == "QUIT":
                self.reply("221 bye")
                return
            else:
                self.reply("250 ok")


server = socketserver.TCPServer(("127.0.0.1", 0), Session)
with open(PORT_FILE, "w") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
