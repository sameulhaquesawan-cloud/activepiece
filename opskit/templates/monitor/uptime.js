const { io } = require("socket.io-client");
const input = JSON.parse(require("fs").readFileSync(0, "utf8"));
const socket = io("http://localhost:3001", { transports: ["websocket"], reconnection: false, timeout: 20000 });
const call = (event, ...args) => new Promise((resolve) => socket.emit(event, ...args, resolve));
const done = (result) => { console.log(JSON.stringify(result)); socket.close(); process.exit(result.ok ? 0 : 1); };
setTimeout(() => { console.log(JSON.stringify({ ok: false, msg: "no answer yet" })); process.exit(2); }, 60000);

let monitors = null;
socket.on("monitorList", (list) => { monitors = Object.values(list); });
const waitFor = async (getter) => { for (let i = 0; i < 100 && getter() === null; i++) await new Promise((r) => setTimeout(r, 100)); return getter(); };

socket.on("connect_error", (error) => done({ ok: false, msg: "connect: " + error.message }));
socket.on("connect", async () => {
  try {
    const login = await call("login", { username: input.admin.username, password: input.admin.password, token: "" });
    if (!login.ok) return done({ ok: false, msg: "login: " + login.msg });
    const monitor = (await waitFor(() => monitors) || []).find((m) => m.name === input.name);
    if (!monitor) return done({ ok: true, found: false, beats: [] });
    const result = await call("getMonitorBeats", monitor.id, input.hours);
    if (!result.ok) return done({ ok: false, msg: "beats: " + result.msg });
    const beats = result.data.filter((b) => b.time >= input.from && b.time < input.to).map((b) => [b.time, b.status]);
    done({ ok: true, found: true, beats });
  } catch (error) {
    done({ ok: false, msg: String(error.message || error) });
  }
});
