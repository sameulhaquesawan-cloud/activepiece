# Architecture Decision Records

Format: Context → Decision → Alternatives → Consequences. Never delete; mark superseded.

### ADR-001: Fork Activepieces; clients run images built from the fork
- **Status:** accepted; image part superseded by ADR-012 (clients run official images in V1)
- **Context:** Owner wants an enhanced repo on GitHub to install clients from; private piece upload is paid, and the custom-piece route assumes a fork.
- **Decision:** Fork, pin release tags, fetch-only upstream; build our CE image with custom pieces via GitHub Actions.
- **Alternatives:** Ops-kit repo with Activepieces cloned inside (can't ship custom pieces on CE); official images only.
- **Consequences:** Must sync releases and rebuild images; heavy builds happen in CI.

### ADR-002: Our code isolated; upstream edits only via ledger
- **Status:** accepted
- **Decision:** `opskit/`, `packages/pieces/custom/`, `.github/workflows/opskit-*.yml`, docs, IDE config. Upstream workflows disabled in the fork.
- **Consequences:** Clean syncs.

### ADR-003: Community Edition only
- **Status:** accepted
- **Context:** Docs' manual path suggests `AP_EDITION=ee`; ee code is commercially licensed.
- **Decision:** Render `AP_EDITION=ce` explicitly; never touch `packages/ee`.
- **Consequences:** No branding/projects/SSO/private-piece upload; one stack per client.

### ADR-004: One stack per client; dedicated or shared hosts
- **Status:** accepted
- **Decision:** Per-client compose project, volumes, `.env`, domain, backups; hosts may carry one or several stacks behind one Caddy.
- **Consequences:** Clean isolation; capacity checks needed on shared hosts.

### ADR-005: Bash ops tooling driven by validated `client.yaml`
- **Status:** accepted
- **Context:** Hosts are plain Ubuntu; minimal dependencies; testable with bats.
- **Decision:** `opskit` dispatcher + libs; JSON-schema validation; templates rendered with envsubst/yq.
- **Alternatives:** Ansible, Terraform, Node CLI.
- **Consequences:** Simple to run anywhere; keep scripts small and tested.

### ADR-006: Ops-hub = our own Activepieces + Uptime Kuma
- **Status:** superseded by ADR-012
- **Context:** CE alerting features may be limited; multi-channel routing needed; dogfooding shows clients the product.
- **Decision:** Hosts push heartbeats/alerts to ops-hub webhooks; ops-hub flows route to Telegram/email/Slack/WhatsApp and send reports.
- **Consequences:** Ops-hub must itself be monitored (UptimeRobot) and backed up.

### ADR-007: Failed-run detection by read-only SQL
- **Status:** accepted (verify schema in Phase 0)
- **Decision:** Cron query on run tables with a read-only role; de-duplicated alerts.
- **Consequences:** Must re-verify table names after each upstream sync.

### ADR-008: Encrypted secrets escrow with age + off-server copies with rclone
- **Status:** accepted
- **Decision:** `.env` encrypted to owner's age key; dumps + escrow copied off-server; tested restores monthly.

### ADR-009: Upgrades through staging with automatic rollback
- **Status:** accepted
- **Decision:** Backup → staging restore on new image → smoke tests → promote → rollback on failure.

### ADR-010: Two IDE packages share docs
- **Status:** superseded by ADR-011
- **Decision:** Kilo: `AGENTS.fork.md` + `kilo.jsonc` + `.kilo/`. Factory: `.factory/AGENTS.md` + `.factory/skills/`. Same `docs/`, same nested AGENTS.md in our folders.

### ADR-011: Build with Claude Code (cloud sessions) instead of Factory/Kilo
- **Status:** accepted (20 Oct 2026)
- **Context:** Owner moved the build from Factory IDE to Claude Code cloud sessions. Upstream already ships `.claude/` (rules, `settings.json`) and `.claude/skills` as a symlink to `.agents/skills`.
- **Decision:** Opskit rules in `.claude/CLAUDE.md` (new file, upstream has none); our skills in `.agents/skills/opskit-*` (prefixed, new folders only); nested `CLAUDE.md` in `opskit/`, `opskit/agent/`, `opskit/flows/`, `packages/pieces/custom/`; SessionStart hook `.claude/hooks/session-start.sh` registered in upstream `.claude/settings.json` (ledger #1). `.factory/` removed.
- **Consequences:** One upstream file edited (settings.json); re-apply on upstream sync.

### ADR-012: V1 = official images + direct alerts; custom pieces/own image and ops-hub routing deferred
- **Status:** accepted (owner, 20 Oct 2026)
- **Context:** Plan review after pinning 0.92.3 (SPEC Appendix C). Private pieces are paid; CE admins can install pieces via `POST /api/v1/pieces`; an ops-hub in the alert path is a single point of failure.
- **Decision:** Client stacks run official `activepieces/activepieces:<tag>` images; Improvement 8 (custom pieces + own image) → V2. Host scripts send alerts directly (Telegram/email/Slack) and push heartbeats to Uptime Kuma; an ops-hub Activepieces stack is demo-only. WhatsApp → later add-on; shared hosts → after first paying client.
- **Alternatives:** ADR-001 own image; ADR-006 ops-hub routing.
- **Consequences:** Simpler upgrades (official tags) and no hub outage blind spot; per-host alert config holds channel secrets (mode 600, never in git).

### ADR-013: One custom piece in V1 — `openai-compatible`, installed by archive (no own image)
- **Status:** accepted (owner, 20 Oct 2026); narrows ADR-012 for this one piece
- **Context:** Owner wants BYOK OpenAI-compatible AI with a live model dropdown and max reasoning by default. CE 0.92.3 has a `custom` AI provider (Platform Admin → AI Center) but its models are typed in by hand (`listModels` returns the stored list) and AI steps send no reasoning effort except `minimal` for OpenAI summaries.
- **Decision:** Build `packages/pieces/custom/openai-compatible` (connection = base URL + API key; dropdown from `GET {baseUrl}/models`; `reasoning_effort` default `high`). Ship it with the CE admin piece-install API (archive), not an own Docker image.
- **Alternatives:** Patch upstream AI provider/worker/web (needs our own image = V2, large ledger); use the built-in custom provider as is (no live models, no reasoning control).
- **Consequences:** Clients keep official images; the piece must be re-installed per stack (scriptable later) and re-tested on upgrades. Built-in AI steps/agents don't use it — flows use the piece's actions.

### ADR-014: Deployment layout — one Caddy edge per host, stacks on a shared edge network, local transport for practice
- **Status:** accepted (Phase 2, 20 Oct 2026)
- **Context:** SPEC 3/7: only Caddy publishes ports; one stack per client; practice without a VPS; idempotent deploys.
- **Decision:** Host layout `<opskit_root>/{clients/<id>/{compose.yml,.env},caddy/etc/{Caddyfile,sites/<id>.caddy},caddy/{data,config},agent,logs}`; pinned `caddy:2.10.0` container on Docker network `opskit_edge`; each app joins it with alias `<id>-app`; Postgres/Redis stay private; compose project = client id, no `container_name`, named volumes `<id>_postgres/_redis/_cache`. Secrets generated once per client on the operator machine (`clients/<id>/secrets.env`, 600). Host transport `ssh` (BatchMode, `sudo -n` only for bootstrap) or `local` (practice/selftest) behind `host_run/host_put`.
- **Alternatives:** binding each app to 127.0.0.1:<port> with host-level Caddy (needs port allocation now, shared-host work deferred); Caddy as a systemd service (less reproducible); regenerating secrets per render (would break stored connections).
- **Consequences:** Adding shared hosts later needs no port allocation for apps (only DNS/sites). The edge is a single point per host (restart policy + uptime monitor in Phase 4). Practice hosts may need the IPv4 listen shim (`practice_quirks`), never used on real hosts.

### ADR-015: Backups run on the host; restores and restore tests run from the owner's machine
- **Status:** accepted (Phase 3, 20 Oct 2026)
- **Context:** SPEC 9 + reliability rules: a backup counts only with dump + encrypted `.env` local and off-server; `AP_ENCRYPTION_KEY` must never be lost; restores go into a fresh stack; monthly restore test. The owner's age private key must never sit on a server.
- **Decision:** A standalone `agent/backup.sh` on each host (cron, `flock`) writes `backups/<id>/<UTC ts>/{db.dump.age (pg_dump -Fc, then age to the owner's public key — since 21 Oct 2026, owner-approved), env.age (age to the owner's public key), compose.yml, status.json}`, copies off-server with rclone, prunes by folder name (14/30 days, never the newest), pings an Uptime Kuma push URL only when everything succeeded and alerts directly otherwise. Redis is not backed up (ASSUMPTIONS #8). `opskit restore` runs on the operator machine: decrypts `env.age` there, re-creates the stack with the original secrets, `pg_restore`s, runs the deploy checks and fails unless every stored connection decrypts. `opskit restore-test` does the same into a throwaway practice host on the operator machine and records the result in `clients/<id>/restore-tests.jsonl`.
- **Alternatives:** volume snapshots/`pg_basebackup` (bigger, version-bound, harder off-server); plain-text `.env` in the backup (key leaks with any backup copy); restore tests on the client server (needs the private key there and RAM a small VPS lacks); a hub that pulls backups (single point of failure, ADR-012).
- **Consequences:** Restores need the owner's machine and private key (by design); losing that key makes all backups unreadable, so it lives in the password manager plus an offline copy. The monthly test is operator-run (optionally a cron on an always-on WSL), not server-run.

### ADR-016: Client hosts watch themselves; Uptime Kuma watches from outside; no hub in the alert path
- **Status:** accepted (Phase 4, 20 Oct 2026)
- **Context:** SPEC 10 + ADR-012: alerts must not depend on an ops-hub; failed runs need flow names and run links; the owner always gets Telegram; clients may want quiet hours. Uptime Kuma 2.x has no REST API for monitors.
- **Decision:** Standalone cron agents on each client host (`detect-failed-runs.sh` every 5 min via a passwordless read-only role `opskit_ro` that can only log in on the postgres container's local socket, `health.sh` hourly, `digest.sh` daily) send through one `alert.sh` (Telegram, Slack, email via `curl` SMTP, webhook; templates in `opskit/templates/alerts/`; de-dup keys in `<root>/state/`; quiet hours hold non-critical client alerts for the digest). The owner's Uptime Kuma (pinned 2.5.5, SQLite, behind Caddy) checks each client's `/api/v1/health` every 60 s and a 26 h backup push monitor, notifying the owner's Telegram; opskit configures it through Uptime Kuma's own socket API from inside its container.
- **Alternatives:** CE's built-in alerts (hidden, owner-only); an ops-hub Activepieces stack routing alerts (single point of failure); an extra API client (`uptime-kuma-api`, needs Python on the operator machine); msmtp on every host (extra package).
- **Consequences:** A dead client server cannot report itself — that is what Uptime Kuma + the backup watchdog cover; a dead monitoring server is covered by UptimeRobot. Uptime Kuma data is rebuilt from the registry, not backed up (ASSUMPTIONS #15). Each host carries its alert secrets (`agent/alerts.conf`, 600).
