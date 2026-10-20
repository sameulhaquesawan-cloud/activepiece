# opskit/agent — scripts that run on client hosts

- Standalone Bash (no repo on hosts): backup, detect-failed-runs, health, heartbeat.
- Read-only DB access for detectors; POST to `OPSKIT_HUB_URL` with token; fallback email if hub unreachable.
- Must be safe to run from cron repeatedly (locking with `flock`, idempotent).
