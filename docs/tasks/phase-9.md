# Phase 9 — Field readiness

SPEC: 17 Phase 9; everything it exercises: 3 (rules), 6–7 (registry, deploy kit, host bootstrap), 9 (backups/restore), 10 (monitoring/alerts), 11 (templates), 12 (upgrades), 13 (handover pack, care report), 15 (security), 18 (pricing notes), Appendix B (open owner questions).
**Accept (SPEC 17):** the whole run completes from the operator guide without undocumented steps; costs and timings recorded in PROGRESS; server deleted or kept as the monitoring host by owner decision.
**Rules from `.claude/CLAUDE.md`:** a real server is involved → every step that touches it waits for the owner. It is a *practice* server with test data only (no client data). Secrets (VPS, DNS, B2, Telegram, SMTP, age private key) are typed by the owner, never pasted in chat.

**Who runs what.** This cloud session cannot open SSH connections (port 22 blocked, checked 22 Oct 2026), so it cannot reach a VPS. The agent writes the guide, the helper commands and the Cowork test prompts and fixes what the runs find; the owner (or Cowork on the owner's behalf) runs the guide in a Codespace (has Docker, SSH and internet) — which is exactly what the acceptance asks for: the guide alone must be enough.

## Field server facts (owner's Cowork report, 24 Oct 2026)
Oracle Free Tier, home region ap-mumbai-1, one instance `anythingllm`: VM.Standard.A1.Flex 2 OCPU / 12 GB (the tenancy's whole A1 limit), Ubuntu 24.04 Minimal aarch64, user `ubuntu`, boot 47 GB of 200 GB, public IP 129.154.225.22 (ephemeral), cost 0. 7-day load: CPU ~59 %, memory ~34 %. Security list already allows 22/80/443 (no NSG). DNS (Spaceship): `mychat` → AnythingLLM; added A `activepiece.autonyxai.shop` and `status.autonyxai.shop` → same IP. Owner decision: Activepieces shares this server with AnythingLLM (practice; deviates from "dedicated host", SPEC 3.5 — record in ASSUMPTIONS). Before any change: read-only inspection inside the server (what holds ports 80/443, Docker, firewall, memory/CPU users), because bootstrap's Caddy edge, ufw and sshd hardening must not break AnythingLLM.

## Shared-server run (owner approved 24 Oct 2026)
Read-only inspection 24 Oct 2026 (agent, SSH as `ubuntu`): Ubuntu 24.04.4 aarch64, 2 CPU, 11.6 GiB (7.5 available), no swap, `/` 45 GB (32 %). docker-ce 29.8.0 (Docker's repo) — bootstrap's `docker.io` install would remove it. `anythingllm-caddy` (`caddy:2`) holds 80/443, config `/opt/anything-llm/deploy/oracle/Caddyfile` (`mychat.autonyxai.shop` and `http://<ip>` → `anything-llm:3001`), certs in volume `anythingllm-oracle_caddy_data`, network `anythingllm-oracle_anything-llm`. No ufw; Oracle iptables (22/80/443, rest rejected, netfilter-persistent). sshd key-only, `PermitRootLogin without-password`. A headless Chrome renderer inside `anythingllm` held ~1.1 CPU. Owner answers: shared edge yes (test the rollback once right after the switch), swap 2 GB, restart `anythingllm` at the start of step 3, client id `autonyx-practice`, keys stay as they are. ASSUMPTIONS #32, ADR-020.

- [x] **S1 — opskit code (repo only)** (commit 5039f306c5; Codespace check: shellcheck clean, 404/408 bats, the 4 failures are the umask issue in Known issues and fail on HEAD too): bootstrap keeps an existing Docker install; `firewall: keep` (checks iptables, never installs ufw; `ufw` refused on Oracle images); `swap: <size>`; `edge.join_networks`. Tests in `bootstrap.bats`.
- [x] **S2 — safety copy (server):** AnythingLLM's Caddyfile, compose files and Caddy volumes → `/opt/opskit-preflight/` (24 Oct 2026; mode 700, tgz 600, mychat cert + key inside). Host yaml `opskit/hosts/oracle-mumbai.yaml`; `host bootstrap --dry-run` plan as expected; it stops at `PermitRootLogin without-password`, so S3 runs bootstrap with `--harden-ssh` (S4 folds into S3). Planned edge + `mychat.caddy` validated with `caddy:2.10.0`; the old Caddy is v2.11.4.
- [x] **S3a — pre-install (owner: "go, pre-install first", 24 Oct 2026):** `age` 1.1.1 and `rclone` 1.60.1 (Ubuntu packages; `curl`, `unattended-upgrades` were already there; apt simulation: nothing removed or upgraded), 2 GB `/swapfile` (600, in fstab). mychat stayed up (200). Bootstrap in the window now only finds them present.
- [ ] **S3b — edge switch, on the owner's "window" after CI run 65 is green; keep the first SSH session open until the second-session test passes (touches AnythingLLM; owner sees the plan first):** restart `anythingllm`, check mychat; copy certs into `/opt/opskit/caddy/data`; `sites/mychat.caddy`; stop old Caddy, bootstrap with `firewall: keep`, `swap: 2G`, `edge.join_networks`; check mychat; **rollback test** (stop `opskit-caddy`, start old Caddy, check mychat, switch again); `profiles: ["disabled"]` for `caddy` in AnythingLLM's override file.
- [ ] **S4 — sshd:** `--harden-ssh` (`PermitRootLogin no`), checked from a second session.
- [ ] **S5 — Activepieces:** client `autonyx-practice` on `activepiece.autonyxai.shop`, image 0.92.2, Let's Encrypt.
- [ ] **S6 — Uptime Kuma:** `status.autonyxai.shop` on this host (512 MB).

## Open questions for the owner (recommended defaults in brackets — "ok" accepts them)
**Owner, 22 Oct 2026:** wants a **$0 stack**; has an **Oracle Cloud Always Free instance** running (SSH key in hand) and a **domain at Spaceship**; is not comfortable with server work and wants the agent to do it. Consequences: Q2 = Oracle Always Free (ARM — verified 22 Oct: `activepieces/activepieces` 0.92.2/0.92.3, caddy 2.10.0, postgres, uptime-kuma all publish linux/arm64); Q1 = a Claude Code session *inside the owner's Codespace* (it has SSH; this cloud session does not) does the server work, with the private key stored as a Codespaces secret (never in chat, never in git); Q3 = the Spaceship domain, two A records added by the owner with exact clicks (an API key would control the whole domain for a one-time change); Q5 = Backblaze B2 free 10 GB (Oracle Object Storage free 20 GB as fallback); SMTP = Brevo free or Gmail app password. Still needed from the owner (not secret): domain name, server public IP, instance shape (OCPU/RAM), image (Ubuntu or Oracle Linux), login user, region.
- **Q1 — Where do you run the commands?** [A GitHub Codespace on this repo, like the Phase 6+7 test. WSL on your laptop works the same and is the long-term home (your age key and registry stay on your machine); the guide covers both.]
- **Q2 — Which server?** SPEC: Oracle Always Free if capacity allows, else a ~$5 VPS, deleted after. [Hetzner Cloud, the smallest 2 vCPU / 4 GB x86 type available in an EU location, Ubuntu 24.04, hourly billing (a few days cost about €1–3). Oracle Always Free is ARM and usually out of capacity — skip it unless you already have an account. US clients later: DigitalOcean, same steps.]
- **Q3 — Which domain?** Appendix B Q1 is still open. [Your business domain if you have one, else buy one now (~€10/year, any registrar with simple DNS — Cloudflare, Porkbun, Namecheap). Practice names: `practice.<domain>` (client) and `status.<domain>` (Uptime Kuma).]
- **Q4 — Uptime Kuma for the practice run?** [On the same practice VPS (fits in 4 GB: client stack ≈ 0.8 GB idle + Kuma 0.5 GB). For real clients it moves to its own small server (ADR-016). At the end you decide: delete the VPS, or keep it as your monitoring host (then the practice client is offboarded).]
- **Q5 — Off-server backups?** [Backblaze B2, EU region, one private bucket, an application key limited to that bucket (10 GB free).]
- **Q6 — "Upgrade dry run"?** [A real upgrade on the practice server: deploy 0.92.2 first, later upgrade to 0.92.3 (the pinned release) with staging, switch and smoke checks, plus one rollback by hand. A plan-only run would test much less.]
- **Q7 — Which two templates go live?** [`lead-capture-tables` and `invoice-reminder-tables`: they need only an SMTP account (no Google sign-in, which is still blocked by 2-step verification). Optional third: `lead-capture` with Google Sheets once your Google test account works.]
- **Q8 — Alerts?** [Real Telegram bot to you (owner channel) + email to you via SMTP; the "client" channel is also you (a second email address of yours).]
- **Q9 — Fix the two open known issues before the run?** (deploy without the owner public key drops the nightly backup line; host agent logs never rotate) [Yes — 9.2 and 9.3, both small and both would bite on a real server.]

## What the owner prepares (task 9.6 turns this into exact clicks)
1. **Oracle Cloud Always Free instance** (have) — tell the agent its public IP, shape, image, login user, region; keep the private key file safe.
2. **Domain at Spaceship** (have) — two A records later, exact clicks given.
3. **Backblaze B2 account** — create nothing yet.
4. **Telegram:** a bot from @BotFather (token) and your chat id (Phase 4 runbook `docs/runbooks/monitoring.md`).
5. **SMTP account** for alerts and reports: Gmail app password (needs 2-step verification) or Brevo free (300 mails/day).
6. **SSH key** on the machine you work from (`ssh-keygen -t ed25519`), and your **age key pair** (`age-keygen`; private key into your password manager — never into the repo or chat).

## Tasks

### [ ] 9.1 — Field facts and pre-flight design (no code)
- **Goal:** Verify against the pinned version and today's providers what a real run depends on: Oracle Always Free limits (A1 ARM 4 OCPU / 24 GB total, block storage, egress), idle-instance reclamation rules and how to avoid them, VCN security list ingress for 80/443, the iptables rules Oracle's Ubuntu images ship (vs ufw), Ubuntu 24.04 aarch64 vs Oracle Linux (bootstrap needs Ubuntu; recreate if needed — free), creating the `ops` user with key + passwordless sudo, Let's Encrypt via Caddy on a fresh host (ports 80/443 open, A record first, rate limits), B2 S3 endpoint and rclone `b2` remote fields, Activepieces image architecture (amd64/arm64), Ubuntu 24.04 defaults that bootstrap touches (ufw, unattended-upgrades, sshd drop-ins, IPv6 on).
- **Spec refs:** 4, 7.3–7.4, 9.3, 15, 18
- **Files likely touched:** `docs/ASSUMPTIONS.md`, `docs/EXPLORATION_REPORT.md` (§11 field facts)
- **Acceptance checks:** each fact has a source (doc URL + date, or a command output); price table dated.
- **Tests required:** none (facts).
- **Manual verification:** owner reads the price table and confirms the server type.

### [ ] 9.2 — Fix: deploy never drops an installed nightly backup
- **Goal:** Known issue (22 Oct): `opskit deploy` without the owner public key re-installs the client's cron without the backup line. When the host already has `agent/backup.sh` for the client, deploy refuses with a clear message instead (or keeps the existing key/line); first deploys without a key still warn as today.
- **Spec refs:** 9.1–9.2, reliability rules
- **Files likely touched:** `opskit/lib/deploy.sh`, `opskit/tests/backup_install.bats`
- **Acceptance checks:** re-deploy without the key on a host with backups → exit 1, cron unchanged; with the key → unchanged behaviour.
- **Tests required:** failing test first in `backup_install.bats`.
- **Manual verification:** `bats opskit/tests/backup_install.bats`.

### [ ] 9.3 — Log rotation for host agent logs
- **Goal:** Known issue: `<root>/logs/<id>-*.log` grow forever. Bootstrap installs a logrotate rule (weekly, keep 8, compress, `copytruncate`) for `<root>/logs/*.log`; idempotent; `--dry-run` shows it.
- **Spec refs:** 7.3, ops script rules
- **Files likely touched:** `opskit/agent/bootstrap.sh`, `opskit/templates/host/` (logrotate file), `opskit/tests/bootstrap.bats`
- **Acceptance checks:** rule file content and path exact; `logrotate -d` accepts it (in test, if logrotate present).
- **Tests required:** `bootstrap.bats` case.
- **Manual verification:** on the VPS in 9.7: `sudo logrotate -d /etc/logrotate.d/opskit`.

### [ ] 9.4 — `opskit host cloud-init` and `opskit host preflight`
- **Goal:** (a) `opskit host cloud-init --user ops --key ~/.ssh/id_ed25519.pub` prints the user-data to paste into the provider's "Cloud config" box (user with key, passwordless sudo, no root password login) — removes the manual first-login step. (b) `opskit host preflight <host>` (read-only): SSH as `ssh_user` works, sudo without password, Ubuntu 24.04, CPU/RAM/disk vs the host yaml, IPv6 not disabled in the kernel, outbound HTTPS to the image registry / `cloud.activepieces.com` / npm, and for each client on the host: the domain's A record points at the host IP. `opskit deploy` runs the DNS part first and stops before touching anything when it is wrong (protects Let's Encrypt rate limits).
- **Spec refs:** 7.3–7.4, 15
- **Files likely touched:** `opskit/lib/commands/host.sh`, `opskit/lib/host.sh` or new `opskit/lib/preflight.sh`, `opskit/templates/host/cloud-init.yaml.tmpl`, `opskit/lib/deploy.sh`, tests
- **Acceptance checks:** cloud-init output passes `cloud-init schema` if available, else yq parse + exact content test; preflight prints one `[ok]/[warn]/[fail]` per item and exits non-zero on any fail; wrong DNS stops deploy with "A record of … points at …, expected …".
- **Tests required:** bats with stubbed ssh/dig (`host_preflight.bats`), deploy DNS-gate case; practice hosts (`transport: local`, `*.localhost`) skip the DNS check.
- **Manual verification:** `opskit host cloud-init --user ops --key <pub>`; preflight against the practice host.

### [ ] 9.5 — Off-server backups to Backblaze B2: guided setup
- **Goal:** The guide's B2 path works without guessing: documented bucket + key settings (private, EU, key limited to the bucket, no delete-files capability if rclone retention allows — verify), the exact `opskit/owner/rclone.conf` `b2` section, and a read-only check (`opskit backups <id>` lists the remote; `opskit doctor --remote <name>` or similar lists the bucket) before the first backup.
- **Spec refs:** 9.3, security rules (rclone config never printed)
- **Files likely touched:** `docs/runbooks/backup-restore.md`, possibly `opskit/lib/commands/doctor.sh`, tests if code changes
- **Acceptance checks:** a wrong key or bucket fails with a clear message and no secret in the output.
- **Tests required:** bats for any new check (stub rclone).
- **Manual verification:** in 9.8 with the real bucket.

### [ ] 9.6 — `docs/OPERATOR_GUIDE.md`
- **Goal:** One guide from zero to a running, monitored, backed-up client and back to zero, in the order a new operator needs it: accounts (9 prep items, exact clicks) → operator machine (Codespace or WSL, `dev-env`, `doctor`, age key) → owner files (`alerts.conf`, `rclone.conf`, `business.yaml`) → server (cloud-init, host yaml, preflight, bootstrap, `--harden-ssh`) → monitoring host (Uptime Kuma, UptimeRobot) → client (new, deploy, admin account, monitor sync, templates import, handover pack) → routine (alerts, digest, backups, restore test, upgrade, care report, hours/incidents) → offboard and server deletion. Each step: command, what success looks like, how long it took, first action when it fails; links to runbooks instead of repeating them.
- **Spec refs:** 17 Phase 9, all runbooks
- **Files likely touched:** `docs/OPERATOR_GUIDE.md`, runbooks (links/fixes), `README-START-HERE.md` (link)
- **Acceptance checks:** every command in the guide exists with those flags (a test greps the guide's `opskit …` lines and runs each with `--help`/usage parse); no secret values in examples.
- **Tests required:** `operator_guide.bats` (commands and flags exist).
- **Manual verification:** owner reads it once before 9.7.

### [ ] 9.7 — Field run part 1: server, monitoring, client (owner + Cowork prompt)
- **Goal:** From the guide only: VPS created with cloud-init → DNS → host yaml → preflight → bootstrap (+ harden SSH) → Uptime Kuma on `status.<domain>` + UptimeRobot check → client `practice` on `practice.<domain>` with image **0.92.2**, real HTTPS (Let's Encrypt) → admin account → `monitor sync` → alerts test (Telegram + email). Times per step recorded.
- **Spec refs:** 7, 10, 15
- **Files likely touched:** `docs/PROGRESS.md` (run log), fixes to whatever breaks
- **Acceptance checks:** `[ok] deployed practice`; HTTPS certificate from Let's Encrypt; Kuma shows the uptime monitor green; one test alert received on each channel; `ssh root@<ip>` refused, Postgres/Redis ports closed from outside (`nc -z` from the Codespace).
- **Tests required:** none new unless a fix needs one (bug → failing test first).
- **Manual verification:** the Cowork report; every deviation from the guide becomes a guide fix or a code fix.

### [ ] 9.8 — Field run part 2: templates live, backups, restore test
- **Goal:** Import and switch on `lead-capture-tables` and `invoice-reminder-tables` (SMTP connection typed by the owner), 5+ test runs each from their `test/` payloads incl. one failure → failed-run alert with run link; `opskit backup practice` → off-server copy in B2 → nightly backup the next night (cron) → `opskit restore-test practice` passes; daily digest received.
- **Spec refs:** 9, 10.3, 11
- **Files likely touched:** `docs/PROGRESS.md`, fixes
- **Acceptance checks:** template CHECKLISTs ticked; backup listed locally and in B2 with sizes > 0; heartbeat green in Kuma; restore test `[ok]` and recorded; one alert per failed run (no duplicates).
- **Tests required:** as needed for fixes.
- **Manual verification:** Cowork report.

### [ ] 9.9 — Field run part 3: upgrade, rollback, handover pack, care report
- **Goal:** `opskit upgrade practice --to 0.92.3 --plan`, then the real upgrade inside quiet hours (or `--now`), follow-ups; one `--rollback` by hand and upgrade again; `opskit docs practice` → PDF; hours + incident logged; `opskit report practice --month <this month> --send` reaches your inbox (and the "client" address).
- **Spec refs:** 12, 13
- **Files likely touched:** `docs/PROGRESS.md`, fixes
- **Acceptance checks:** downtime measured (expected < 1 min); data and flows intact after upgrade and rollback; Kuma recorded no false "down" (monitor paused); report numbers match the runs of 9.8; email formatted, not in spam (else note SPF/DKIM of the SMTP account).
- **Tests required:** as needed for fixes.
- **Manual verification:** Cowork report + the PDF and email.

### [ ] 9.10 — Costs and timings
- **Goal:** Real numbers into PROGRESS and the pricing material: VPS price per month, B2 and SMTP cost, RAM/CPU/disk of the client stack + Kuma at idle and during runs (`docker stats`, `df`), time per onboarding step (from 9.7–9.9), backup size and duration, upgrade duration and downtime; per-client cost dedicated vs shared (shared estimated from measured RAM, SPEC 7.5); update `docs/go-to-market/pricing-calculator.csv` inputs and `pricing.md` if the numbers change the price.
- **Spec refs:** 17 Phase 9, 18
- **Files likely touched:** `docs/PROGRESS.md`, `docs/go-to-market/pricing.md`, `pricing-calculator.csv`, `research.md` (dated prices)
- **Acceptance checks:** every number has its source (run log line or invoice/price page date); calculator results re-computed by script.
- **Tests required:** none (docs).
- **Manual verification:** owner reviews the cost table.

### [ ] 9.11 — Demo script on the real server
- **Goal:** Update `docs/go-to-market/demo-script.md` for the field server (option A: real demo server) with the exact URLs, the failure to trigger, the alert to show, the backup/restore-test evidence and the care report; timed rehearsal ≤ 3 min; owner records the Loom.
- **Spec refs:** 17 Phase 9 (roadmap Loom), 4b
- **Files likely touched:** `docs/go-to-market/demo-script.md`
- **Acceptance checks:** every step points to something that exists on the field server; fallbacks listed.
- **Tests required:** none.
- **Manual verification:** owner's Loom link (optional).

### [ ] 9.12 — Close: server decision, guide fixes, verification report
- **Goal:** Owner decides: delete the VPS (offboard the practice client, delete the B2 bucket, remove DNS records — guide steps) or keep it as the monitoring host (offboard only the practice client). Fold every deviation found in 9.7–9.9 into the guide; ADR for any architectural choice (e.g. preflight DNS gate); verification report against the acceptance criteria.
- **Spec refs:** 17 Phase 9
- **Files likely touched:** `docs/OPERATOR_GUIDE.md`, `docs/PROGRESS.md`, `docs/DECISIONS.md`
- **Acceptance checks:** SPEC 17 Phase 9 accept lines each answered with evidence; `opskit/bin/check` + selftest green (CI).
- **Tests required:** full `opskit/bin/check`, CI.
- **Manual verification:** owner sign-off.
