# Architecture Decision Records

Format: Context → Decision → Alternatives → Consequences. Never delete; mark superseded.

### ADR-001: Fork Activepieces; clients run images built from the fork
- **Status:** accepted
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
- **Status:** accepted
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
- **Status:** accepted
- **Decision:** Kilo: `AGENTS.fork.md` + `kilo.jsonc` + `.kilo/`. Factory: `.factory/AGENTS.md` + `.factory/skills/`. Same `docs/`, same nested AGENTS.md in our folders.
