# Operator guide — running your automation service

For you, the owner. How your setup fits together, what runs on its own, what you do daily/monthly,
how to add a client, and what to do when something breaks. Using the Activepieces builder itself:
`ACTIVEPIECES_GUIDE.md`. Each section links to the detailed runbook in `docs/runbooks/`.

## 1. Your setup today (24 Oct 2026)
| Piece | Where | Notes |
|---|---|---|
| Your builder (practice client `autonyx-practice`) | `https://activepiece.autonyxai.shop` | Activepieces 0.92.2, admin account = you |
| Monitoring (Uptime Kuma) | `https://status.autonyxai.shop` | login in `opskit/hosts/oracle-mumbai.monitor/admin.env` (Codespace) |
| AnythingLLM (your other project) | `https://mychat.autonyxai.shop` | served through the same web front door (opskit's Caddy) |
| Server | Oracle Cloud Free, Mumbai, `129.154.225.22`, 2 CPU ARM / 12 GB, Ubuntu 24.04 | $0; shared by all three; host file `opskit/hosts/oracle-mumbai.yaml` |
| Domain | `autonyxai.shop` at Spaceship | **turn auto-renew on** (expires 5 Sep 2027) |
| Your control room | GitHub Codespace on this repo | where opskit commands run; Claude Code runs there too |

Secrets and where they live (never in chat, never in git):
| Secret | Lives in | Backup copy |
|---|---|---|
| Server SSH key | Codespaces secret `ORACLE_SSH_KEY_PRIVATE` → `~/.ssh/oracle` | your password manager |
| Owner age private key (unlocks all backups) | `~/.config/opskit/owner.key` in the Codespace | **password manager (required)** |
| Kuma admin login | `opskit/hosts/oracle-mumbai.monitor/admin.env` | password manager |
| Builder admin login | you | password manager |
| Telegram / SMTP / Backblaze keys | `opskit/owner/alerts.conf`, `opskit/owner/rclone.conf` | password manager |

**Codespace warning:** stopping a Codespace keeps its files; **deleting** it loses the files above that
are not in git (`opskit/clients/`, `opskit/hosts/`, `opskit/owner/`, your keys). Keep the password-manager
copies, and back the folders up (encrypted to your owner key) after every change and monthly:
```bash
opskit/bin/opskit registry backup --to b2:<your bucket>/registry
```
On a new Codespace or laptop: put the owner key back in `~/.config/opskit/owner.key`, create
`opskit/owner/rclone.conf` again (or download the newest `registry-*.tar.gz.age` from Backblaze), then
`opskit/bin/opskit registry restore b2:<your bucket>/registry/<file>` (or the downloaded file).

## 2. What runs on its own
| What | When | You hear about it when |
|---|---|---|
| Encrypted backup of each client (database + settings) | nightly 02:30 server time | it fails, or is only on the server |
| Failed-run check | every 5 min | a client flow fails (flow, step, link) |
| Watchdog (restarts a hung app) | every 2 min | it restarts something, or gives up |
| Server health (disk, memory, containers, certificate) | hourly | a problem starts, and when it is fixed |
| Daily summary | 08:00 client time | every day, one message |
| Uptime check of each client site | every minute, from Kuma | site down / back up |
| Missed-backup check | Kuma, 26 h window | no backup arrived |
| HTTPS certificates | Caddy renews automatically | renewal fails (health check) |

All alerts go to your Telegram once it is set up (§4). Until then they are only written to log files
on the server.

## 3. Your routine
- **Daily (1 min):** read the daily summary; act on red alerts (§7).
- **When an alert says a flow failed:** open the run link, fix, retry (`ACTIVEPIECES_GUIDE.md` §7).
- **Monthly, on the 1st (15 min):**
  ```bash
  opskit/bin/opskit restore-test --all          # proves last night's backups really restore
  opskit/bin/opskit report --all                # builds last month's care reports; read them
  opskit/bin/opskit report --all --send         # emails them (needs SMTP, §4)
  opskit/bin/opskit registry backup --to b2:<your bucket>/registry   # your own settings, encrypted
  ```
- **During the month:** log work you do for a client (it shows in their report):
  `opskit/bin/opskit hours <client> add 1.5 "changed the reply text"` and
  `opskit/bin/opskit incident <client> add "what happened"`.
- **When Activepieces releases a new version (every few weeks):** upgrade clients one by one (§6).

## 4. Still to set up (in this order)
1. **Telegram alerts (5 min)** — `docs/runbooks/monitoring.md` §A: bot from @BotFather, your chat id,
   both into `opskit/owner/alerts.conf` (you type them), then in the Codespace Claude:
   "redeploy autonyx-practice, send a test alert, then `opskit monitor sync autonyx-practice`".
2. **Off-server backups — Backblaze B2 (15 min, free 10 GB):** create an account, a **private** bucket
   (e.g. `autonyx-backups`) and an **application key limited to that bucket**. Then
   `rclone config --config opskit/owner/rclone.conf` → new remote `b2`, type `b2`, paste the key id
   and key yourself. Set `backup.remote: b2:autonyx-backups/clients` in the client's `client.yaml`,
   redeploy, run `opskit backup <client>` → it must say "complete". Runbook:
   `docs/runbooks/backup-restore.md` §B.
3. **Email (10 min):** Brevo free (300 mails/day) or a Gmail app password → `SMTP_*` lines in
   `opskit/owner/alerts.conf` (`docs/runbooks/monitoring.md` §B). Needed for email alerts and care reports.
4. **Your business details:** copy `opskit/templates/business.example.yaml` to
   `opskit/owner/business.yaml` and fill in name, support email, website (used in handover packs
   and reports instead of "YourBrand").
5. **UptimeRobot (5 min, free):** one HTTP monitor on `https://status.autonyxai.shop` emailing you,
   so you learn if the monitoring itself is down.

## 5. Adding a client
Plan per client: a domain or subdomain (e.g. `auto.clientname.com`, or `client.autonyxai.shop`), and
which flows they want. A paying client should get **their own server** (≥ 2 CPU / 4 GB; Hetzner or
DigitalOcean ~€6–24/month — billed to them); your free Oracle server is for you and demos.
1. **Server (once):** print the server setup text with `opskit/bin/opskit host cloud-init --user ops --key ~/.ssh/id_ed25519.pub`
   and paste it into the provider's "cloud config" box when creating an Ubuntu 24.04 server; DNS A record →
   its IP; describe it in `opskit/hosts/<host>.yaml`; `opskit/bin/opskit host preflight <host>` (read-only
   check), then `opskit/bin/opskit host bootstrap <host> --dry-run`, then without `--dry-run`. Details and the shared-server options (`firewall: keep`, `edge.join_networks`) in
   `docs/runbooks/deploy-client.md` and ADR-020.
2. **Client:**
   ```bash
   opskit/bin/opskit client new acme --domain auto.acme.com --host <host> --contact owner@acme.com --name "Acme Dental" --timezone Europe/London
   opskit/bin/opskit deploy acme
   ```
   The moment it prints `[ok] deployed`, open the site and **create the admin account yourself** — the
   first sign-up becomes the admin.
3. **Monitoring + backup:** `opskit/bin/opskit monitor sync acme`, then `opskit/bin/opskit backup acme`
   (must end "complete").
4. **Flows:** import templates (`ACTIVEPIECES_GUIDE.md` §6), the client connects their own accounts on
   a call, you test with real data, publish.
5. **Handover:** add one-sentence notes per flow in `opskit/clients/acme/notes.yaml`, run
   `opskit/bin/opskit docs acme`, open `opskit/clients/acme/docs/handover.html`, print to PDF, send it.
   Runbook: `docs/runbooks/handover-and-report.md`.
6. **Pause / leave:** `opskit/bin/opskit client pause acme` / `resume`; leaving clients:
   run `opskit/bin/opskit backup acme`, export their flows, then `opskit/bin/opskit client offboard acme` (stops it, data kept); after 30 days `opskit/bin/opskit client offboard acme --purge --yes` deletes it.

## 6. Upgrading Activepieces (safe, with automatic undo)
```bash
opskit/bin/opskit upgrade acme --to 0.92.3 --plan     # read-only: what changes, are backups fresh
opskit/bin/opskit upgrade acme --to 0.92.3 --yes      # inside the client's quiet hours; or add --now
```
It makes a fresh backup, tests the new version on a copy first, switches (about 15–30 s of downtime),
checks everything and **rolls back by itself** if any check fails. Undo by hand within 7 days:
`opskit/bin/opskit upgrade acme --rollback --yes`. Runbook: `docs/runbooks/upgrade.md`.
Your practice client is on 0.92.2 on purpose: upgrading it to 0.92.3 is the next practice step.

## 7. When something breaks
| You see | Do this |
|---|---|
| Telegram: a flow failed | open the link, read the red step, fix (reconnect the app, fix the data), Retry |
| Kuma/Telegram: site down | wait 5 min (the watchdog may restart it); still down → ask the Codespace Claude: "activepiece.autonyxai.shop is down, investigate read-only and propose a fix" |
| Backup failed / missed | `opskit/bin/opskit backups <client>`, then `opskit/bin/opskit backup <client>` and read the `[fail]` line |
| Disk / memory warning | ask the Codespace Claude to investigate read-only first |
| mychat broken after a change | rollback to AnythingLLM's own web server, on the server: `sudo docker stop opskit-caddy && sudo docker start anythingllm-caddy` |
| Lost the server completely | new server → bootstrap → `opskit/bin/opskit restore <client> --host <new host>` from the off-server backup (needs B2 and your age private key). Runbook: `docs/runbooks/backup-restore.md` |

Rule of thumb with Claude: ask for **read-only investigation and a proposal first**, approve, then let
it change things. Anything that deletes data asks you to type the client id.

## 8. Working with Claude (the Codespace session)
- Start: open the Codespace → terminal → `claude --continue` (last conversation) or `claude`.
- First message after a break: "git pull, read docs/PROGRESS.md and continue from Next steps".
- Only one session should change the repo at a time; always `git pull` first when switching between
  the cloud session and the Codespace one.
- Never paste keys, tokens or passwords into any chat; type them into the files/websites it names. To
  look at a secret file yourself, use a separate plain terminal tab, not `!` inside Claude.

## 9. Costs today
| Item | Cost |
|---|---|
| Oracle server (Always Free: 2 OCPU / 12 GB in this account; at the limit) | $0 |
| Domain `autonyxai.shop` | yearly renewal at Spaceship |
| Codespaces | free monthly hours on a personal GitHub account |
| Backblaze B2 (≤ 10 GB), Brevo (≤ 300 mails/day), Telegram, UptimeRobot, Let's Encrypt | $0 |
Oracle may reclaim Always Free servers that sit idle for 7 days (CPU, network and memory all under
20 %); yours is busy enough today. Paying clients go on paid servers (`docs/go-to-market/pricing.md`).
