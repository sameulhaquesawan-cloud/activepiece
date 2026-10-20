# Phase 4 — Monitoring & alerts (Improvement 3)

SPEC: Section 17 Phase 4, Section 10, 3.9, 15; reliability rules in `.claude/CLAUDE.md`; ADR-012 (direct alerts, ops-hub demo only), ADR-014 (host layout), ADR-015 (backup heartbeat).
**Accept (SPEC 17):** a deliberately failing demo flow produces exactly one Telegram alert within 10 minutes with flow name and run link; stopping a client stack triggers an uptime alert; a missed backup heartbeat triggers the watchdog after 26 h (time-shifted test); Slack and email adapters pass payload tests; alerts still arrive when no ops-hub exists.

## Open questions for the owner
**Answered 20 Oct 2026: owner accepted all recommendations** — Q1 separate small VPS (domain later; local practice host until then), Q2 (a) automatic — 4.1 found it needs **no** new tool: the helper runs inside the Uptime Kuma container (ASSUMPTIONS #11), Q3 email via `curl`, Q4 quiet hours as proposed.
- **Q1 — Where does Uptime Kuma run?** (SPEC App. B #1) Recommended: one small separate VPS (~€4/month) at `status.<yourbrand>.com`, so monitoring survives a client server going down. Needed only for the first real client (Phase 9); until then everything is tested on a local practice host. Tell me your brand domain when you have it.
- **Q2 — Creating monitors automatically.** Uptime Kuma 1.x has no REST API for monitors (only its web socket, *verify in 4.1*). Options: (a) **automatic** with a small helper that talks to that socket — needs one new pinned dev tool on your machine (e.g. `socket.io-client` or Python `uptime-kuma-api`); (b) **semi-manual**: `opskit monitor plan <id>` prints exactly what to click, you paste the push URL into `client.yaml`. Recommended: (a) — the uptime acceptance test needs monitors created by code anyway. I will ask before adding the dependency.
- **Q3 — Email sending.** SPEC says msmtp on hosts. Recommended instead: `curl` (already installed on every host) speaks SMTP, so no new host package. You will need an SMTP account later (e.g. Brevo free, 300 mails/day, or a Gmail app password). OK?
- **Q4 — Quiet hours** (per client, client time zone). Proposed: `critical` always goes out at once; `info`/`warn` are held and delivered in the next daily digest. The owner's Telegram ignores quiet hours. OK?

## Design (to confirm in ADR-016)
- Everything that alerts runs on the client's own host from cron (standalone `opskit/agent/*.sh`), sends directly via `agent/alert.sh` channel adapters, and pings Uptime Kuma. Uptime Kuma (owner's monitoring host) watches `https://<domain>/api/v1/health` every 60 s and one push monitor per client for backups (26 h); its own notifications go to the owner's Telegram. Nothing depends on an ops-hub.
- Detectors read Postgres through a passwordless read-only role `opskit_ro` that can only log in over the container's local socket (official image `pg_hba`: `local all all trust`, TCP needs a password — checked on the explore stack, re-verify on the client image in 4.1).
- State (last check time, de-dup keys, held alerts) lives in `<root>/state/<id>/` on the host.

## Tasks

### [x] 4.1 — Verify monitoring facts (no code)
- **Goal:** pin and record: Uptime Kuma image + tag (Docker Hub was rate-limited at planning time — retry / mirror), its monitor API (1.x socket vs 2.x), push-monitor settings for a 26 h window, notification types (Telegram, webhook); the run link format in 0.92.3 (planning read: `/projects/<projectId>/runs/<runId>`); `flow_run.failedStep` shape and where the error message lives; `pg_hba` of `pgvector/pgvector:0.8.0-pg14`; whether a selftest stack can run a webhook + code flow offline (piece metadata was missing in 3.8).
- **Spec refs:** 10.1–10.3, 0 (never invent APIs)
- **Files likely touched:** `docs/ASSUMPTIONS.md`, `docs/EXPLORATION_REPORT.md` (addendum)
- **Acceptance checks:** every item above has a source/test reference in ASSUMPTIONS.
- **Tests required:** none (research)
- **Manual verification:** read the ASSUMPTIONS rows.

### [x] 4.2 — Alert core: channel adapters, severity, templates
- **Goal:** split `agent/alert.sh` into adapters (Telegram, Slack, email via `curl` SMTP if Q3 OK, generic webhook) with message templates in `opskit/templates/alerts/` (text + JSON per channel); severity `info|warn|critical`; owner always gets Telegram; ≤ 300-char excerpts; no secrets.
- **Spec refs:** 10.5, 10.6, 3.9
- **Files likely touched:** `opskit/agent/alert.sh`, `opskit/templates/alerts/*`, `opskit/tests/alert_channels.bats`, `opskit/tests/helpers/mock_smtp.py`
- **Acceptance checks:** Slack and email payloads match the templates; a failing channel does not block the others; exit code reports partial failure.
- **Tests required:** one bats test per channel against mock HTTP / mock SMTP listeners; secret-looking text never appears in payloads.
- **Manual verification:** `alert.sh --client demo --severity warn --what test --action none` against the mock listeners.

### [x] 4.3 — De-duplication + quiet hours
- **Goal:** `--dedupe-key <k> --window <min>` (state file per client, 30 min default) and quiet hours from `client.yaml` (`alerts.quiet_hours`, `timezone`) per Q4; held alerts go to `<root>/state/<id>/held.jsonl`.
- **Spec refs:** 10.6, reliability rules
- **Files likely touched:** `opskit/agent/alert.sh`, `opskit/lib/stack.sh` (render quiet hours/timezone into client `alerts.conf`), tests
- **Acceptance checks:** same key twice in the window → one alert; quiet hours across midnight handled; critical never held.
- **Tests required:** bats with `OPSKIT_NOW` time-shifting.

### [x] 4.4 — Read-only database role
- **Goal:** `opskit deploy` creates/updates `opskit_ro` (LOGIN, no password, `SELECT` on `flow`, `flow_version`, `flow_run`, `project`, read-only default transaction) idempotently; agents use `psql -U opskit_ro` inside the postgres container.
- **Spec refs:** 15, security rules
- **Files likely touched:** `opskit/lib/deploy.sh` (or new `lib/dbrole.sh`), tests
- **Acceptance checks:** `opskit_ro` can read runs, cannot `INSERT`/`UPDATE`/`DELETE`, cannot log in over TCP; re-deploy changes nothing.
- **Tests required:** docker-tagged bats on a selftest stack.

### [ ] 4.5 — Failed-run detector
- **Goal:** `agent/detect-failed-runs.sh <id>` (cron every 5 min, `flock`): runs with status in FAILED, INTERNAL_ERROR, TIMEOUT, MEMORY_LIMIT_EXCEEDED, QUOTA_EXCEEDED, LOG_SIZE_EXCEEDED finished since the last check → one alert per flow per 30 min (count if several) with flow name, run id, error excerpt ≤ 300 chars, run link.
- **Spec refs:** 10.3, reliability rules
- **Files likely touched:** `opskit/agent/detect-failed-runs.sh`, tests, fixture SQL
- **Acceptance checks:** first run does not alert on old history; no double alerts across runs; read-only SQL only.
- **Tests required:** bats with a fixture Postgres (docker-tagged) + stubbed unit tests for de-dup and message format.

### [ ] 4.6 — Host health checks
- **Goal:** `agent/health.sh` (cron hourly): disk > 85 %, memory pressure (MemAvailable < 10 %), container restart count increased, HTTPS certificate expiring < 14 days → alert, de-duplicated per condition for 24 h, "recovered" info when cleared.
- **Spec refs:** 10.4
- **Files likely touched:** `opskit/agent/health.sh`, tests
- **Tests required:** bats with stubbed `df`, `/proc/meminfo`, `docker`, `openssl`.

### [ ] 4.7 — Daily digest
- **Goal:** `agent/digest.sh` (cron daily, client morning in its time zone): one message per client — last backup result, failed runs in 24 h (by flow), health state, held quiet-hour alerts (then cleared).
- **Spec refs:** 10.1, 10.6
- **Files likely touched:** `opskit/agent/digest.sh`, tests
- **Tests required:** bats on fixture state files; exactly one message per run.

### [ ] 4.8 — Install monitoring agents via deploy
- **Goal:** `opskit deploy` ships the new agent scripts and adds detector/health/digest lines to the client `cron` (existing `cron-sync.sh`); practice hosts print the commands instead.
- **Spec refs:** 10, ADR-014
- **Files likely touched:** `opskit/templates/cron.tmpl`, `opskit/lib/deploy.sh`, tests
- **Tests required:** rendered cron content; deploy pushes every agent file (stubs); selftest still passes.

### [ ] 4.9 — Uptime Kuma via the kit
- **Goal:** `opskit monitor deploy <host>`: Uptime Kuma (pinned tag from 4.1) behind the host's Caddy edge at the monitoring domain, data in a named volume, included in host backups; works on a practice host.
- **Spec refs:** 10.1, 10.2, 7
- **Files likely touched:** `opskit/lib/commands/monitor.sh`, `opskit/templates/monitor/*`, schema (`hosts/*.yaml` monitor section), tests
- **Tests required:** rendering tests; docker-tagged: Uptime Kuma answers through Caddy.

### [ ] 4.10 — Monitors per client (depends on Q2)
- **Goal:** `opskit monitor sync <id>`: HTTP monitor on `/api/v1/health` (60 s) + backup push monitor (26 h) + owner Telegram notification; writes the push URL into `client.yaml` `backup.heartbeat_url` and redeploys the backup config. `opskit offboard` removes them.
- **Spec refs:** 10.1, 10.2, 9
- **Acceptance checks:** stopping a client stack → Uptime Kuma notification (mock webhook in tests); missed heartbeat → watchdog alert (time-shifted: short interval in the test, 26 h asserted in rendered settings).
- **Tests required:** docker-tagged with a local Uptime Kuma.

### [ ] 4.11 — End-to-end acceptance test
- **Goal:** extend `selftest` (or `selftest --monitoring`): failing demo flow → detector → exactly one Telegram message (mock `OPSKIT_TELEGRAM_API`) within 10 min with flow name and run link; second detector run sends nothing; no ops-hub present.
- **Spec refs:** 17 Phase 4 accept
- **Tests required:** docker-tagged; CI runs it.

### [ ] 4.12 — Docs + phase close
- **Goal:** `docs/runbooks/monitoring.md` (plain steps: create a Telegram bot and find chat ids, SMTP account, Uptime Kuma first login, UptimeRobot watching Uptime Kuma, what each alert means and the first action); ADR-016; ENVIRONMENT; PROGRESS + phase verification report.
- **Manual verification:** owner reads the runbook; `opskit/bin/check` + `opskit selftest` pass.
