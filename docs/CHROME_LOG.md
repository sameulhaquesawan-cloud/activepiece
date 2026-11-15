# Chrome log — tasks for the local session

Two sessions share the branch named in `docs/PROGRESS.md`:
- **Cloud session**: code, tests, docs. Writes tasks here, owns every other tracked file. Cannot SSH out.
- **Local session** (owner's Windows laptop): Claude in Chrome **and** the opskit operator inside WSL2 Ubuntu
  (SSH to hosts, `opskit` commands). In git it writes **only this file**. The plan behind the tasks:
  `docs/go-to-market/launch-plan.md`.

## Protocol
1. Before work: `git pull`. After work: commit only this file, `git pull --rebase`, `git push`.
2. Cloud adds a task under **Open tasks** (`### T<n> — title`, steps, report format).
3. Local does it, moves it to **Done** with a report: what was done, results, problems.
4. **Never write secrets here or in chat** (passwords, API keys, tokens, private keys, `.env` values, full
   contents of `opskit/clients/` or `opskit/hosts/`). Write `[stored by owner]`. IPs, hostnames, record names,
   versions and error text are fine.
5. Stop and ask the owner before anything destructive, paid, account-creating, message-sending, or that changes
   a live server, firewall or DNS. Read-only work needs no approval.
6. **Teach mode (always):** the owner is learning. Before each action, say in one plain sentence what you are
   about to do and why; after each page or command, one sentence on what it showed. When a task says
   *Owner tries*, stop and let the owner do that part while you guide.
7. Opskit commands run in WSL (`wsl -d Ubuntu-24.04 -- bash -lc '...'`) from the clone inside Ubuntu, never
   against the AnythingLLM containers. The registry (`opskit/clients/`, `opskit/hosts/`) exists only there.

## Open tasks

### T1 — Read-only inventory of the Oracle server and DNS
No changes anywhere. Report every item; "unknown" is a valid answer.
1. Oracle Cloud console (Chrome): instance name, shape (e.g. VM.Standard.A1.Flex / E2.1.Micro), OCPUs, RAM,
   boot volume size, OS image, region, public IP. VCN → security list / NSG: list the ingress rules (port, source).
2. Spaceship (Chrome): DNS records of `autonyxai.shop` — type, host, value (no account details).
3. SSH (from Windows PowerShell or WSL, with the owner's existing key). Run only these and report output:
   `uname -m; lsb_release -ds; nproc; free -h; df -h /; docker --version; docker compose version;
   docker ps --format '{{.Names}}  {{.Image}}  {{.Ports}}'; sudo ss -tlnp | grep -E ':(80|443|22)\b';
   sudo ufw status; sudo iptables -S INPUT | head -20; id -un`
   Do not open or print any `.env` or config file.
4. Laptop: `wsl --status` and `wsl -l -v` in PowerShell (is WSL2 + Ubuntu installed?), free disk on C:.
5. *Owner tries:* open AnythingLLM in the browser and note its URL (does it use a domain, port 3001, or 80/443?).
Report format: a short table per item, then "Blockers I see".

### T2 — Getting paid from Bangladesh (research, then Payoneer signup start)
1. Using official pages only (payoneer.com, upwork.com, fiverr.com, wise.com, paypal.com, stripe.com), check for a
   seller living in Bangladesh: can they receive and withdraw to a BD bank? Fees for receiving USD and withdrawing to BDT.
   Report a table: provider · works in BD (yes/no/partly) · fee · source URL · date checked.
2. Payoneer: open the signup page and walk the owner through it. *Owner tries:* the owner fills and submits
   every field and document. You only explain fields. Report which documents were asked for and the status shown.

### T3 — Telegram alert bot (owner on phone or web.telegram.org)
Opskit already sends alerts to Telegram (`alerts.telegram.chat_id` in `client.yaml`, `opskit/agent/alert.sh`);
it only needs a bot. *Owner tries* every step; you explain.
1. In Telegram open `@BotFather` → `/newbot` → name `AutonyxAI Alerts`, username ending in `bot`. The owner keeps
   the token in a password manager (secret — never in this file or chat).
2. Owner sends any message to the new bot, then opens `https://api.telegram.org/bot<TOKEN>/getUpdates` in the browser
   and finds `"chat":{"id":…}`. That number is the chat id; keep it with the token.
Report: bot created yes/no, chat id found yes/no (write `[stored by owner]` for both values).

## Done

### T0 — Round-trip test
- **Date:** 2026-11-15
- **Machine:** owner's Windows laptop, Microsoft Windows 10 Pro 10.0.19045
- **Claude in Chrome connected:** yes. Checked by opening a new tab in its own tab group, going to https://github.com/sameulhaquesawan-cloud/activepiece and reading the page title: "sameulhaquesawan-cloud/activepiece". The GitHub header showed a signed-in user avatar. Tab closed afterwards; no other tabs touched.
- **`git --version`:** `git version 2.47.0.windows.1`
- **Clone:** `%USERPROFILE%\Documents\activepiece`, branch `claude/ecstatic-keller-dxgivp`
- **Problems:** none.
