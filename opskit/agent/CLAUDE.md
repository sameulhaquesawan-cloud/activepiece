# opskit/agent — scripts that run on client hosts

- Standalone Bash (no repo on hosts): backup, detect-failed-runs, health, heartbeat.
- Read-only DB access for detectors; alerts go directly to the client's channels (Telegram/email/Slack); heartbeats go to Uptime Kuma push URLs (ADR-012).
- Must be safe to run from cron repeatedly (locking with `flock`, idempotent).
