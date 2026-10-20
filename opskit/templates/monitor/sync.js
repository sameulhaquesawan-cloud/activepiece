const { io } = require("socket.io-client");
const crypto = require("crypto");
const input = JSON.parse(require("fs").readFileSync(0, "utf8"));
const socket = io("http://localhost:3001", { transports: ["websocket"], reconnection: false, timeout: 20000 });
const call = (event, ...args) => new Promise((resolve) => socket.emit(event, ...args, resolve));
const done = (result) => { console.log(JSON.stringify(result)); socket.close(); process.exit(result.ok ? 0 : 1); };
setTimeout(() => { console.log(JSON.stringify({ ok: false, msg: "no answer yet" })); process.exit(2); }, 30000);

let monitors = null;
let notifications = null;
socket.on("monitorList", (list) => { monitors = Object.values(list); });
socket.on("notificationList", (list) => { notifications = list; });
const waitFor = async (getter) => { for (let i = 0; i < 100 && getter() === null; i++) await new Promise((r) => setTimeout(r, 100)); return getter(); };

const BASE = {
  accepted_statuscodes: ["200-299"], kafkaProducerBrokers: [], kafkaProducerSaslOptions: {}, conditions: [],
  rabbitmqNodes: [], active: true, parent: null, description: null, upsideDown: false, resendInterval: 0,
};

async function ensureNotification(wanted) {
  const existing = (await waitFor(() => notifications)).find((n) => n.name === wanted.name);
  const result = await call("addNotification", { ...wanted, isDefault: false, applyExisting: false }, existing ? existing.id : null);
  if (!result.ok) throw new Error("notification: " + result.msg);
  return existing ? existing.id : result.id;
}

async function ensureMonitor(wanted, notificationId) {
  const notificationIDList = { [notificationId]: true };
  const existing = (await waitFor(() => monitors)).find((m) => m.name === wanted.name);
  if (!existing) {
    const pushToken = wanted.type === "push" ? crypto.randomBytes(24).toString("base64url").slice(0, 32) : undefined;
    const added = await call("add", { ...BASE, ...wanted, ...(pushToken ? { pushToken } : {}), notificationIDList });
    if (!added.ok) throw new Error("add " + wanted.name + ": " + added.msg);
    const saved = await call("getMonitor", added.monitorID);
    return { id: added.monitorID, pushToken, interval: saved.monitor.interval, created: true };
  }
  const current = await call("getMonitor", existing.id);
  if (!current.ok) throw new Error("get " + wanted.name + ": " + current.msg);
  const edited = await call("editMonitor", { ...BASE, ...current.monitor, ...wanted, notificationIDList });
  if (!edited.ok) throw new Error("edit " + wanted.name + ": " + edited.msg);
  const saved = await call("getMonitor", existing.id);
  return { id: existing.id, pushToken: saved.monitor.pushToken, interval: saved.monitor.interval, created: false };
}

async function removeMonitors(names) {
  const removed = [];
  for (const monitor of await waitFor(() => monitors)) {
    if (!names.includes(monitor.name)) continue;
    const result = await call("deleteMonitor", monitor.id);
    if (!result.ok) throw new Error("delete " + monitor.name + ": " + result.msg);
    removed.push(monitor.name);
  }
  return removed;
}

socket.on("connect_error", (error) => done({ ok: false, msg: "connect: " + error.message }));
socket.on("connect", async () => {
  try {
    const login = await call("login", { username: input.admin.username, password: input.admin.password, token: "" });
    if (!login.ok) return done({ ok: false, msg: "login: " + login.msg });
    if (input.action === "remove") return done({ ok: true, removed: await removeMonitors(input.remove) });
    const notificationId = await ensureNotification(input.notification);
    const result = {};
    for (const wanted of input.monitors) result[wanted.type] = await ensureMonitor(wanted, notificationId);
    done({ ok: true, notificationId, monitors: result });
  } catch (error) {
    done({ ok: false, msg: String(error.message || error) });
  }
});
