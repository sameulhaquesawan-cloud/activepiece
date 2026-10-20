const { io } = require("socket.io-client");
const input = JSON.parse(require("fs").readFileSync(0, "utf8"));
const socket = io("http://localhost:3001", { transports: ["websocket"], reconnection: false, timeout: 20000 });
const call = (event, ...args) => new Promise((resolve) => socket.emit(event, ...args, resolve));
const done = (result) => { console.log(JSON.stringify(result)); socket.close(); process.exit(result.ok ? 0 : 1); };
setTimeout(() => { console.log(JSON.stringify({ ok: false, msg: "no answer yet" })); process.exit(2); }, 15000);
socket.on("connect_error", (error) => done({ ok: false, msg: "connect: " + error.message }));
socket.on("connect", async () => {
  if (await call("needSetup")) {
    const setup = await call("setup", input.username, input.password);
    if (!setup.ok) return done({ ok: false, msg: "setup: " + setup.msg });
  }
  const login = await call("login", { username: input.username, password: input.password, token: "" });
  done(login.ok ? { ok: true, msg: "admin ready" } : { ok: false, msg: "login: " + login.msg });
});
