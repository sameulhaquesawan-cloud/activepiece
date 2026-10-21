# Runbook — monitoring and alerts

Commands run on your machine (Codespace, WSL, cloud AI session). Design and reasons: ADR-016 in
`docs/DECISIONS.md`. Alert texts: `opskit/templates/alerts/README.md`.

## What watches what
| Check | Runs where | How often | Alerts |
|---|---|---|---|
| Failed flow runs (production only) | client server, `agent/detect-failed-runs.sh` | every 5 min | one per flow per 30 min, with flow name, step, short error, run link |
| Server health: disk, memory, containers, HTTPS certificate | client server, `agent/health.sh` | hourly | once per problem per 24 h, then "Recovered" |
| Daily summary | client server, `agent/digest.sh` | 08:00 client time | one message per client |
| Backup failed / only on the server | client server, `agent/backup.sh` | nightly | right away |
| Client site down | your Uptime Kuma (`<id> uptime`) | every 60 s | when down and when back up |
| No backup for 26 h | your Uptime Kuma (`<id> backup`) | — | when the heartbeat is missing |
| Uptime Kuma itself down | UptimeRobot (free) | every 5 min | email to you |

Every alert names the client, the severity (`info`, `warn`, `critical`), what happened and the first
thing to do. You always get Telegram. Clients get their own channels from `client.yaml`
(`alerts.channels`: telegram, email, slack). During a client's quiet hours (`alerts.quiet_hours`, their
time zone) only `critical` reaches them; the rest is in their next daily summary.

## One-time setup for you

### A. Your Telegram bot (5 minutes)
1. In Telegram, open **@BotFather**, send `/newbot`, pick a name (e.g. "YourBrand Alerts") and a
   username ending in `bot`. BotFather replies with a **token** like `123456:ABC…`. Keep it secret.
2. Open your new bot and press **Start** (send it any message).
3. In a browser open `https://api.telegram.org/bot<token>/getUpdates` (paste your token). Find
   `"chat":{"id":123456789` — that number is your **chat id**.
4. On your machine create `opskit/owner/alerts.conf` (git-ignored) with your own editor:
   ```
   TELEGRAM_BOT_TOKEN=<token>
   TELEGRAM_CHAT_ID=<chat id>
   ```
   then `chmod 600 opskit/owner/alerts.conf`. Never paste the token into chat.
5. `opskit deploy <id>` for each client copies it to their server.

A client's Telegram group: add your bot to the client's group, send a message there, read the
group's (negative) chat id from `getUpdates`, put it in `client.yaml` `alerts.telegram.chat_id`.

### B. Email (optional, for client email alerts)
Create a free SMTP account (Brevo: 300 mails/day; or a Gmail app password). Add to
`opskit/owner/alerts.conf`:
```
SMTP_URL=smtp://smtp-relay.brevo.com:587
SMTP_USER=<login>
SMTP_PASSWORD=<SMTP key>
SMTP_FROM=alerts@yourbrand.com
```
Mail is sent with `curl` over STARTTLS; nothing to install on servers.

### C. Uptime Kuma (your monitoring server)
1. A small separate VPS (Phase 4 Q1), DNS `status.yourbrand.com` → its IP. Describe it in
   `opskit/hosts/monitor-vps.yaml` like any host, plus:
   ```yaml
   monitor: { domain: status.yourbrand.com }
   ```
2. `opskit host bootstrap monitor-vps`, then `opskit monitor deploy monitor-vps`.
3. Log in at `https://status.yourbrand.com` with the user and password in
   `opskit/hosts/monitor-vps.monitor/admin.env` (store them in your password manager too).
4. For each client: `opskit monitor sync <id>` (creates the uptime + backup monitors and points the
   client's backup heartbeat at Uptime Kuma). Re-run it any time; offboarding removes them.
5. UptimeRobot (free): add an HTTP monitor for `https://status.yourbrand.com` with your email, so you
   hear about it if the monitoring server itself goes down.

If the monitoring server is lost: new server → steps 1–2 → `opskit monitor sync <id>` for every client
(history is gone, monitors are back; ASSUMPTIONS #15).

## When an alert arrives
| Alert | First action |
|---|---|
| `Flow "…" failed (…) at step "…"` | open the link, read the failing step, fix it, retry the failed runs |
| `[… uptime] [🔴 Down]` | `ssh` to the server, `docker compose -p <id> ps`, then logs of the stopped service |
| `[… backup] [🔴 Down] No heartbeat` | `opskit backups <id>`; run `opskit backup <id>` and read the `[fail]` line |
| `Disk …% full` | `docker image prune`, old logs in `<root>/logs`; or resize the disk |
| `Low memory` | `docker stats`; lower worker replicas or move to a bigger server |
| `Container … restarted` / `not running` | `docker logs --tail 100 <container>` |
| `HTTPS certificate … expires` | `docker logs opskit-caddy` (ACME errors), check DNS |
| Daily summary says "check …" | look at the lines it names |

## Checking it works
- `opskit selftest` includes a deliberately failing flow → exactly one Telegram alert (mock) with the
  run link (needs internet for pieces; CI always runs it).
- `bats opskit/tests/monitor.bats` (Docker): stopping a client app makes Uptime Kuma alert, a missed
  backup heartbeat triggers the watchdog.
- On a real server: `<root>/agent/alert.sh --client <id> --severity info --what "test" --action "none"`
  sends a test message to every configured channel.
