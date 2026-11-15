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

### T3 — Telegram alert bot (owner on phone or web.telegram.org)
Opskit already sends alerts to Telegram (`alerts.telegram.chat_id` in `client.yaml`, `opskit/agent/alert.sh`);
it only needs a bot. *Owner tries* every step; you explain.
1. In Telegram open `@BotFather` → `/newbot` → name `AutonyxAI Alerts`, username ending in `bot`. The owner keeps
   the token in a password manager (secret — never in this file or chat).
2. Owner sends any message to the new bot, then opens `https://api.telegram.org/bot<TOKEN>/getUpdates` in the browser
   and finds `"chat":{"id":…}`. That number is the chat id; keep it with the token.
Report: bot created yes/no, chat id found yes/no (write `[stored by owner]` for both values).

## Done

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
3. **One small box runs everything** — 18 containers (voice stack, AnythingLLM, crw, Activepieces practice, Kuma) on 2 OCPU / 12 GB with 18 GB disk free. Room for staging is tight on disk; a second free A1 instance (2 OCPU / 12 GB left in the allowance) is an option.
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

### T0 — Round-trip test
- **Date:** 2026-11-15
- **Machine:** owner's Windows laptop, Microsoft Windows 10 Pro 10.0.19045
- **Claude in Chrome connected:** yes. Checked by opening a new tab in its own tab group, going to https://github.com/sameulhaquesawan-cloud/activepiece and reading the page title: "sameulhaquesawan-cloud/activepiece". The GitHub header showed a signed-in user avatar. Tab closed afterwards; no other tabs touched.
- **`git --version`:** `git version 2.47.0.windows.1`
- **Clone:** `%USERPROFILE%\Documents\activepiece`, branch `claude/ecstatic-keller-dxgivp`
- **Problems:** none.
