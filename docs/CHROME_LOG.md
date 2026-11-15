# Chrome log — tasks for the local session

Two sessions share the branch named in `docs/PROGRESS.md`:
- **Cloud session**: code, tests, docs. Writes tasks here, owns every other tracked file. Cannot SSH out.
- **Local session** (owner's Windows laptop): Claude in Chrome. In git it writes **only this file**.
- **Codespace Claude**: the opskit operator (registry + SSH key). Server commands happen there, not here. The plan behind the tasks:
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
7. No opskit commands from the laptop: the registry and the SSH key live in the Codespace. Read-only SSH only when a task lists the exact commands.

## Open tasks

(none)

## Done

### T5 — Rescue the Codespace registry (owner approved starting it, 15 Nov 2026)
Goal: reset the 30-day deletion clock and get an encrypted copy of the registry off the Codespace. In the Codespace's
browser terminal. Never `cat`, open or screenshot `.env`, `owner.key`, `admin.env`, `alerts.conf`, `rclone.conf`.
1. github.com/codespaces → `verbose trout` → Open in browser (starting it resets the clock). Wait until the terminal is ready.
2. Uncommitted changes, names only: `git status --short; git stash list; git log --oneline -1`. Report the output. Do not commit, stash, pull or discard anything.
3. `opskit/bin/opskit registry backup` — report the `[ok]`/`[fail]` lines and the file name it wrote in `~/opskit-registry-backups/`.
4. Copy that one file out: `mkdir -p explore/handoff && cp ~/opskit-registry-backups/<that file> explore/handoff/` (`explore/` is git-ignored), then in the Explorer right-click it → Download → save to `Documents\autonyx-backups\` on the laptop. Then `rm -r explore/handoff`. The file is encrypted to the owner's age key, so it is safe on the laptop.
5. *Owner only, no screenshots by you during this step:* is the age private key (`~/.config/opskit/owner.key`) in the owner's password manager? If not, the owner opens it in the editor, copies it into the password manager and closes the tab. Report yes/no only.
6. Leave the Codespace running; it stops itself after 30 min idle.
Report: step 2 output, step 3 result, file saved yes/no, step 5 yes/no.

**Report 1 (local, 2026-11-15) — partly done; step 3 blocked, needs cloud.**

| Step | Result |
|---|---|
| 1. Start Codespace | **done** — opened `https://verbose-trout-r7pwv4q7g7qpf54gv.github.dev/`, connected (status bar: Codespaces: verbose trout, branch `claude/funny-keller-x6sgy1`). 30-day deletion clock reset → earliest auto-delete ≈ mid-Dec 2026. On open, the editor restored an `owner.key` tab from a previous session; local closed all editors (`View: Close All Editors`) before any screenshot, so the key was never shown. |
| 2. Uncommitted changes | `git status --short`: **empty** (no tracked changes; GitHub's "uncommitted changes" label looks stale). `git stash list`: **empty**. `git log --oneline -1`: `84e84b7a8e (HEAD -> claude/funny-keller-x6sgy1, origin/claude/funny-keller-x6sgy1, origin/HEAD) feat(opskit): watchdog restarts hung containers; app memory floor`. |
| 3. `opskit/bin/opskit registry backup` | **[fail] unknown command: registry (see: opskit --help)**. The Codespace is on the older branch `claude/funny-keller-x6sgy1`, which has no `registry` subcommand. `~/opskit-registry-backups/` does not exist. Not pulled/switched (task forbids it). |
| 4. Copy backup to laptop | **not done** (nothing to copy). |
| 5. age key in password manager | **yes** — owner copied it into their password manager (value [stored by owner]). Local did not view it; only checked the file exists: `/home/vscode/.config/opskit/owner.key`, 184 bytes, mode `-rw-------`, dated Oct 24. |
| 6. Leave running | **yes** — left running; local closed only its browser tab. |

**Needed from cloud:** a way to run the backup on this Codespace without breaking the "no pull/switch" rule — e.g.
approve `git fetch origin && git switch claude/ecstatic-keller-dxgivp` (tree is clean, so safe) or give a one-off
command. No rush: the clock was reset today.

**Report 2 (local, 2026-11-15) — done.** Owner told local to run `git fetch origin && git switch main && git pull`, then steps 3 and 4.

| Step | Result |
|---|---|
| Switch to `main` | `git status --short` empty first. Fetch got new `claude/blissful-lovelace-ltnlm9`, `claude/ecstatic-keller-dxgivp`, updated `main` and `claude/funny-keller-x6sgy1`. `Switched to a new branch 'main'`, `Already up to date`. HEAD now `5c5dd57087 (HEAD -> main, origin/main) Merge PR #2: consolidate funny-keller, blissful-lovelace and ecstatic-keller into main`. |
| 3. `opskit/bin/opskit registry backup` | `[ok] registry backup registry-20261115T161336Z.tar.gz.age: clients hosts (17 entries, encrypted, checked with your private key)` → `/home/vscode/opskit-registry-backups/registry-20261115T161336Z.tar.gz.age` (2935 bytes, `-rw-------`). Also `[warn] kept on this machine only: add --to <remote:path> (e.g. b2:your-bucket/registry) to copy it off`. |
| 4. Copy to laptop | **yes** — copied to `explore/handoff/` (owner allowed `explore/handoff` once, since the standing rule keeps local out of `explore/`), Explorer → right-click → Download (browser saved it to Downloads), moved to `C:\Users\LENOVO\Documents\autonyx-backups\registry-20261115T161336Z.tar.gz.age`, 2935 bytes (size matches). `rm -r explore/handoff` done; original stays in `~/opskit-registry-backups/`. |
| 6. Leave running | **yes** — Codespace left running on `main`; local closed only its own tab. |

**Note for cloud:** the Codespace is now on `main`, not `claude/funny-keller-x6sgy1`. The laptop copy is the only
off-Codespace copy; the `[warn]` suggests a `--to` remote for a regular off-site backup.

### T4 — Is the Codespace (the operator's registry) still there?
Done 2026-11-15. Read-only: nothing was started, stopped, deleted or saved.

**⚠ Urgent:** the activepiece Codespace was last used 22 days ago and retention is 30 days → it will be
auto-deleted around **2026-11-23** (≈8 days) unless it is started before then. It also shows uncommitted changes.

**1. Codespaces (github.com/codespaces)**

| Name | Repo | Branch | State | Last used | Deletion date |
|---|---|---|---|---|---|
| `verbose trout` | sameulhaquesawan-cloud/activepiece | `claude/funny-keller-x6sgy1*` (PR #1) | not running (no "Active" label); "This codespace has uncommitted changes"; 4-core · 16 GB RAM · 32 GB | 22 days ago | not shown on the list; by retention ≈ 2026-11-23 |
| `wild toad` | sameulhaquesawan-cloud/AutoPost | `agency-edition` | not running; no changes; 18.05 GB | 21 days ago | not shown; ≈ 2026-11-24 |

**2. Codespaces settings (github.com/settings/codespaces)**

| Setting | Value |
|---|---|
| Default retention period | 30 days (maximum; "deleted 30 days after the last time they were stopped") |
| Default idle timeout | 30 minutes |
| Deletion warning emails | enabled |
| User-level Codespaces secrets | `ORACLE_SSH_KEY` (1 repository), `ORACLE_SSH_KEY_PRIVATE` (1 repository) — values [stored by owner] |

**3. Repo Codespaces secrets** (activepiece → Settings → Secrets and variables → Codespaces)

| Item | Value |
|---|---|
| Repository secrets | **none** ("This repository has no secrets") |
| Where `ORACLE_SSH_KEY_PRIVATE` lives | as a **user** secret (item 2), granted to 1 repository |

**4. Oracle limits** (Compute, scope AP-MUMBAI-1-AD-1, compartment root)

| Limit | Service limit | Used | Available |
|---|---|---|---|
| Cores for Standard.A1 (`standard-a1-core-count`) | 2 | 2 | 0 |
| Memory for Standard.A1 (`standard-a1-memory-count`) | 12 GB | 12 | 0 |
| Reservable / reserved A1 cores and memory | 0 / n/a | 0 | 0 / n/a |

**Correction to T1:** the phase-9 note is right — the instance uses the whole A1 limit. T1 blocker 3's "second free A1
instance (2 OCPU / 12 GB left)" is **wrong**; I had read the generic Free Tier banner (4 OCPU / 24 GB), but this
tenancy's actual limit is 2 / 12. A second A1 box needs a limit increase or a paid upgrade.

**5. NSG on the instance VNIC**

| Item | Value |
|---|---|
| Network security groups | **none** (—) |
| Route table / subnet | default route table for sawan / public subnet-sawan |

So the only firewall layers are the subnet security list and the host iptables (both in T1, they match).

**6. Telegram token rotation**

| Item | Value |
|---|---|
| Rotated with `/revoke` after the screenshot | **yes** (owner confirmed 2026-11-15); new token [stored by owner] |

### T1 — Read-only inventory of the Oracle server and DNS
Done 2026-11-15. Nothing was changed anywhere (only viewed pages and ran the listed read-only commands).

**1. Oracle Cloud** (Free Tier account, compartment `sameulhaquesawan (root)`)

| Item | Value |
|---|---|
| Instance | `anythingllm` — Running, created 2026-09-05 |
| Shape | VM.Standard.A1.Flex (ARM) — 2 OCPU, 12 GB RAM, 2 Gbps (free allowance is 4 OCPU / 24 GB, so half is unused) |
| Boot volume | 47 GB, no extra block volumes (free allowance 200 GB total) |
| OS image | Canonical Ubuntu 24.04 Minimal aarch64 (`Canonical-Ubuntu-24.04-Minimal-aarch64-2026.08.25-0`) |
| Region / AD | ap-mumbai-1 (India West, Mumbai), AD-1, FD-1 |
| Public / private IP | 129.154.225.22 / 10.0.0.204 |
| SSH user | `ubuntu` |
| VCN / subnet | `sawan` / `public subnet-sawan` (10.0.0.0/24) |
| Security list | `Default Security List for sawan` (only list on the subnet). NSG on the VNIC: not checked. |

Ingress rules (all stateless = No):

| Source | Protocol | Port | Description |
|---|---|---|---|
| 0.0.0.0/0 | TCP | 22 | SSH |
| 0.0.0.0/0 | ICMP | type 3,4 | default |
| 10.0.0.0/16 | ICMP | type 3 | default |
| 0.0.0.0/0 | TCP | 80 | HTTP |
| 0.0.0.0/0 | TCP | 443 | HTTPS |
| 0.0.0.0/0 | UDP | 3478 | dograh-ops… |
| 0.0.0.0/0 | TCP | 3478 | dograh-ops… |
| 0.0.0.0/0 | UDP | 49152-49200 | dograh-ops… |

**2. Spaceship DNS — `autonyxai.shop`** (nameservers launch1/launch2.spaceship.net, DNSSEC enabled, 7 records)

| Type | Host | Value | TTL |
|---|---|---|---|
| A | activepiece | 129.154.225.22 | 5 min |
| A | mychat | 129.154.225.22 | 30 min |
| A | status | 129.154.225.22 | 5 min |
| A | voice | 129.154.225.22 | 30 min |
| A | youraireceptionist | 129.154.225.22 | 30 min |
| NS | waas | ns1.vercel-dns.com. | 5 min |
| NS | waas | ns2.vercel-dns.com. | 5 min |

No `staging-activepiece`, no `@` (apex) and no `www` record.

**3. SSH** (Windows OpenSSH 9.5, key `oracle-anythingllm.key`, user `ubuntu`)

| Command | Output |
|---|---|
| `uname -m` | aarch64 |
| `lsb_release -ds` | Ubuntu 24.04.4 LTS |
| `nproc` | 2 |
| `free -h` | Mem 11Gi total, 4.0Gi used, 7.6Gi available; swap 2.0Gi (56Ki used) |
| `df -h /` | /dev/sda1 45G, 27G used, 18G free (61%) |
| `docker --version` | 29.8.0 |
| `docker compose version` | v5.5.1 |
| `ss -tlnp` 22/80/443 | 22 → sshd; 80 and 443 → docker-proxy (Caddy), IPv4 + IPv6 |
| `ufw status` | `ufw: command not found` (not installed) |
| `iptables -S INPUT` | policy ACCEPT, then ESTABLISHED, icmp, lo, NEW tcp 22/80/443, udp+tcp 3478, udp 49152:49200, final `REJECT icmp-host-prohibited` — matches the Oracle list |
| `id -un` | ubuntu |

Containers (`docker ps`, 18 running):

| Group | Containers (image) | Published ports |
|---|---|---|
| Reverse proxy | opskit-caddy (caddy:2.10.0) | 0.0.0.0:80, 0.0.0.0:443 (only public listener) |
| Activepieces practice | autonyx-practice-app-1, -worker-1 (activepieces:0.92.2), -postgres-1 (pgvector 0.8.0-pg14), -redis-1 (redis 7.0.7) | none |
| Monitoring | opskit-monitor-uptime-kuma-1 (uptime-kuma:2.5.5) | none |
| AnythingLLM | anythingllm (local image anythingllm-oracle-anything-llm) | none |
| Dograh voice | dograh-ops-api, -ui (1.48.0), -callops, -postgres (pg17), -redis, -minio, -site (nginx 1.29), -coturn (4.8.0) | none published in `docker ps` |
| crw | crw-crw-1 (ghcr.io/us/crw:latest), crw-lightpanda-1, crw-searxng-1 | 127.0.0.1:3000 only |

**4. Laptop**

| Item | Value |
|---|---|
| `wsl --status` | Default version 2 |
| `wsl -l -v` | **No distributions installed** (no Ubuntu) |
| Free disk C: | 49.2 GB of 232.3 GB |
| SSH client | Windows OpenSSH 9.5; keys present: `oracle-anythingllm.key`, `oracle_vps.key` (contents [stored by owner]) |

**5. AnythingLLM URL (owner)** — `https://mychat.autonyxai.shop/login`: domain over HTTPS (443) through Caddy, not port 3001.

**Blockers I see**
1. **No Ubuntu in WSL** — opskit can't run on the laptop until `wsl --install -d Ubuntu-24.04` (owner action; needs a reboot).
2. **No `staging-activepiece` DNS record** — HANDOFF expects `staging-activepiece.autonyxai.shop`; needs an A record → 129.154.225.22 (DNS change, needs owner approval).
3. **One small box runs everything** — 18 containers (voice stack, AnythingLLM, crw, Activepieces practice, Kuma) on 2 OCPU / 12 GB with 18 GB disk free. Room for staging is tight on disk. ~~A second free A1 instance (2 OCPU / 12 GB left in the allowance) is an option.~~ Wrong — corrected in T4: the A1 limit (2 / 12) is fully used.
4. `crw` uses an unpinned `:latest` image (minor; not ours to change without owner).
5. NSG on the instance VNIC not checked (security list and iptables agree, so low risk).

**Owner note (2026-11-15):** cloud session, please turn every blocker above into tasks and handle them all.
`staging-activepiece` was **not** created on purpose — the owner wants to watch/learn the full flow, so set up
staging as guided tasks (explain each step; DNS change still needs the owner's OK).

### T2 — Getting paid from Bangladesh
Done 2026-11-15. Official pages only; all checked 2026-11-15.

| Provider | Works in BD | Fee (receive USD → BDT bank) | Source |
|---|---|---|---|
| Payoneer | **yes** — the main route for BD | Receive in non-local currency (USD) 1% (min 1 USD); withdraw to bank with conversion 1.2%–4%; free from another Payoneer balance; annual fee 29.95 USD if < 6,000 USD received in 12 months. Exact BD rate only shown after sign-in. | https://www.payoneer.com/pricing/ (page says "last updated 1 January 2026") |
| Upwork | **yes** | Direct to Local Bank (outside US) 0.99 USD/transfer; Direct to Wallet lists Bangladesh; Payoneer and PayPal also offered; USD wire 50 USD. Upwork service fee on earnings is separate. Beneficiary name must match verified Upwork name. | https://support.upwork.com/hc/en-us/articles/211060918-How-to-get-paid-on-Upwork |
| Fiverr | **partly** — via Payoneer only (PayPal not usable from BD) | Bank Transfer via Payoneer 1 USD (min 20 USD, 1–3 business days local currency); Payoneer account 3 USD (min 10 USD); max 5,000 USD per withdrawal | https://help.fiverr.com/hc/en-us/articles/360010530058-Withdrawing-your-earnings-managing-payout-methods |
| Wise | **partly** — a client can send to a BD bank via Wise (sender pays), but a BD resident cannot hold money or get USD account details (BD not in the list) | n/a for receiving | https://wise.com/help/articles/2813542/where-do-i-need-to-live-to-hold-money-with-wise , https://wise.com/help/articles/2978049/where-can-i-use-wise |
| PayPal | **no** — Bangladesh not in PayPal's country list (paypal.com/bd shows the US site) | — | https://www.paypal.com/us/webapps/mpp/country-worldwide |
| Stripe | **no** — Bangladesh not a supported country (only via Stripe Atlas US company, paid) | — | https://stripe.com/global |

**Step 2 (Payoneer signup):** skipped at the owner's request — the owner already has a payment method to get paid.
No documents asked, nothing submitted.

### T3 — Telegram alert bot
Done 2026-11-15 by the owner (local session only explained; it did not touch Telegram).

| Item | Result |
|---|---|
| Bot created via @BotFather (name `AutonyxAI Alerts`) | **yes** — token: [stored by owner] |
| Chat id found via `getUpdates` | **yes** — chat id: [stored by owner] |
| Where kept | Owner's password manager (Google Password Manager suggested) |

Problems / notes:
- First `getUpdates` returned `{"ok":true,"result":[]}` because no message had been sent to the bot yet; fixed by
  pressing Start and sending a message, then reloading.
- A screenshot shared in the local chat showed part of the token in the address bar. Owner was advised to rotate it
  with `/revoke` in @BotFather and keep only the new token — **done**, owner rotated it (confirmed 2026-11-15).
- Next for cloud: when the opskit client config is set up, the owner enters token + chat id into
  `alerts.telegram` locally (in the WSL registry, never in git) and we send a test alert.

### T0 — Round-trip test
- **Date:** 2026-11-15
- **Machine:** owner's Windows laptop, Microsoft Windows 10 Pro 10.0.19045
- **Claude in Chrome connected:** yes. Checked by opening a new tab in its own tab group, going to https://github.com/sameulhaquesawan-cloud/activepiece and reading the page title: "sameulhaquesawan-cloud/activepiece". The GitHub header showed a signed-in user avatar. Tab closed afterwards; no other tabs touched.
- **`git --version`:** `git version 2.47.0.windows.1`
- **Clone:** `%USERPROFILE%\Documents\activepiece`, branch `claude/ecstatic-keller-dxgivp`
- **Problems:** none.
