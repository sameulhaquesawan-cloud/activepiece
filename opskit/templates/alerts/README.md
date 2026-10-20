# Alert templates

Used by `opskit/agent/alert.sh` (shipped to `<root>/agent/alerts/` on every host by `opskit deploy`).
Each `*.jq` file turns one alert object into a channel payload; `text.jq` is the shared message text.

Alert object: `client`, `severity` (`info|warn|critical`), `what` and `action` (each cut to 300
characters), `host`, `at` (UTC ISO time), `date` (RFC 2822), `link` (optional, e.g. a run link),
`body` (optional extra lines, ≤ 1500 characters, used by the daily digest).

| Severity | Meaning | Quiet hours |
|---|---|---|
| `critical` | client is losing work or data now (failed backup, stack down, failing flows) | always sent |
| `warn` | needs action soon (backup only on the server, disk 85 %, certificate < 14 days) | held for the digest |
| `info` | for the record (recovered, daily digest) | held for the digest |

Channels: owner Telegram (always), client Telegram chat, Slack incoming webhook, email (SMTP via
`curl`), generic JSON webhook. Never put secrets or personal data into `what`/`action`.
