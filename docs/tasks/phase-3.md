# Phase 3 — Backups & restore (Improvement 2)

SPEC: Section 17 Phase 3, Section 9, 15; reliability rules in `.claude/CLAUDE.md`; ADR-012 (direct alerts, Uptime Kuma heartbeats), ADR-014 (host layout).
**Needs owner approval before implementation** (backup/restore logic, task-loop rule).

## Open questions for the owner
- **Q1 — Off-server backup target** (SPEC App. B #3): Backblaze B2 (10 GB free, recommended), Google Drive, or another server? Tests use a local rclone "remote" either way; the real target is only needed for Phase 9 / first client.
- **Q2 — Your `age` key pair:** backups of each client's `.env` are encrypted to *your* public key; the private key never leaves you (password manager). Agent prepares a 3-step guide; until then tests use a throwaway test key.

## Design (to confirm in ADR-015)
- Host-side standalone agent: `<root>/agent/backup.sh <id>` (cron from the rendered `cron` file), `flock` per client, writes `<root>/backups/<id>/<UTC ts>/{db.sql.gz, env.age, compose.yml, status.json}`.
- Off-server: `rclone copy` to `<remote>/<id>/<ts>/`; local keep 14 days, remote keep 30 (from client.yaml); pruning by timestamp directory names.
- A backup counts only if dump + `env.age` exist locally **and** remotely with size > 0 → then heartbeat (Uptime Kuma push URL, optional until Phase 4); any failure → alert via a minimal standalone `agent/alert.sh` (payload format shared with Phase 4).
- Restore from the operator machine: `opskit restore <id> --from <ts> [--target <client>]` → fresh stack (new compose project), never over a running one without `--overwrite --yes`; decrypt `env.age` locally with your private key.
- Redis is not backed up — **verify** (3.1) whether schedules/delays live only in Redis.

## Tasks

### [x] 3.1 — Verify what must be backed up
- **Goal:** read-only check on a running stack: which state is in Postgres vs Redis (repeatable schedule jobs, delays/paused runs, webhook queue); does the app rebuild schedules from Postgres on start? Record in ASSUMPTIONS; adjust design if Redis holds durable state.

### [x] 3.2 — `agent/backup.sh` (dump + escrow + local layout)
- **Goal:** standalone, `flock`, `pg_dump` via the postgres container (`-Fc` or gzip SQL), `age -r <owner pubkey>` on `.env`, compose snapshot, `status.json` (sizes, duration, ok); never writes secrets in clear outside `.env`.
- **Tests:** bats with stub `docker`/`age`; real run tagged docker on a selftest stack.

### [x] 3.3 — Off-server copy + retention pruning
- **Goal:** `rclone copy` + verify remote sizes; prune local > 14 d, remote > 30 d (configurable); never prune the newest successful backup.
- **Tests:** fixture directories with dated names → exactly the configured days kept; rclone `local` remote for tests.

### [x] 3.4 — Heartbeat + failure alert
- **Goal:** heartbeat only when 3.2+3.3 fully succeed; on failure `agent/alert.sh` sends `{client, severity, what, first_action}` (≤ 300-char excerpts, no secrets) to configured channels.
- **Tests:** mock HTTP listener receives exactly one alert on failure, none on success.

### [x] 3.5 — Install agent + cron via deploy
- **Goal:** `opskit deploy` copies `agent/*.sh`, the owner's age public key and per-client backup config to the host and installs `/etc/cron.d/opskit-<id>` (ssh hosts) / user crontab note (practice hosts).
- **Tests:** rendered cron content; deploy pushes agent files (stubs).

### [x] 3.6 — `opskit backup <id>` (on demand) + `opskit backups <id>` (list)
- **Goal:** run the host agent now; list local/remote backups with sizes and status.

### [x] 3.7 — `opskit restore <id> --from <ts> [--target <new-id>] [--overwrite --yes]`
- **Goal:** fetch backup (remote or host), decrypt `env.age` with the owner's private key on the operator machine, create a fresh stack (same secrets → stored connections decrypt), load the dump, start, smoke checks (health, worker, a flow listed).
- **Acceptance:** refuses a running target without `--overwrite --yes` + typed id.

### [ ] 3.8 — Round-trip acceptance test (docker)
- **Goal:** selftest-style: demo client + 3 flows + a stored connection (via API) → backup → restore into a new stack → flows present, connection decrypts (connection test via API) → teardown.

### [ ] 3.9 — Monthly restore test job + docs
- **Goal:** `opskit restore-test <id>` (temporary stack, 3.8 checks, result recorded for the care report); runbook `docs/runbooks/backup-restore.md`; ADR-015; PROGRESS.
