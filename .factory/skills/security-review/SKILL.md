---
name: security-review
description: Review changed code for security and permission problems
---

# Security review

Review all files changed in the current phase (`git diff main...HEAD`). Check against the Security, Ops script and Reliability rules in `.factory/AGENTS.md`:

1. No secrets, `.env`, keys, dumps, `opskit/clients/` or `opskit/hosts/` content committed or printed.
2. Secret generation aborts on empty values; `.env` files written with mode 600.
3. Destructive commands require `--yes` + typed client id; restores never overwrite a running stack by default.
4. Hosts: SSH key-only, ufw 22/80/443, Postgres/Redis not published, only Caddy exposed.
5. Detectors/reports use read-only SQL and a read-only role; alert payloads carry no secrets or full personal data.
6. `AP_EDITION=ce` everywhere; nothing from `packages/ee/` used or changed.
7. Backups: `.env` escrow encrypted with age; private key never in repo or on hosts.
8. Upstream files unchanged unless ledgered and approved; upstream remote push disabled.

Output a table: issue, file:line, severity (high/medium/low), fix suggestion. Don't change code until the user approves.
