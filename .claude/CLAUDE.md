# .claude/CLAUDE.md — Automation Ops Kit (fork of activepieces/activepieces)

This repo is the owner's fork of Activepieces (open-source Zapier alternative, MIT Community Edition) plus **opskit**: tooling to deploy, back up, monitor, upgrade, document and report on one Activepieces stack per client, and a flow template library. Custom pieces / own Docker image are V2 (owner, 20 Oct 2026).

**Two instruction sets apply.** Upstream's root `AGENTS.md`/`CLAUDE.md` govern upstream code. This file (including the rules below) and `docs/SPEC.md` govern opskit. On conflict: upstream conventions for how to edit upstream files; SPEC for what opskit does.

## Document map
| File | Use it for | Authority |
|---|---|---|
| `docs/SPEC.md` | Requirements, phases (Section 17) | **Source of truth** |
| `docs/EXPLORATION_REPORT.md` | Phase 0 findings (CE feature matrix, verify answers, RAM) | Informs later phases; blockers go to the owner |
| `docs/DECISIONS.md` | ADRs | Binding unless superseded |
| `docs/TECH_ARCHITECTURE.md` | Stack layout, repo structure, command pattern, sizing | Must follow |
| `docs/USER_FLOWS.md` | Operator flows and edge cases | Derived from SPEC |
| `docs/ENVIRONMENT.md` | Tools, accounts, variables | Must follow |
| `docs/UPSTREAM_CHANGES.md` / `docs/UPSTREAM_SYNC.md` | Pinned tag, patch ledger, sync procedure | Must follow |
| `docs/RESEARCH.md` | Facts behind the SPEC | Background |
| `docs/PROGRESS.md`, `docs/tasks/phase-N.md`, `docs/ASSUMPTIONS.md` | Status, current tasks, assumptions | Update every task |

**Conflict order:** SPEC > DECISIONS > TECH_ARCHITECTURE > other docs.

## Session start (or run `/opskit-resume`)
1. Read `docs/HANDOFF.md`, `docs/PROGRESS.md` and the current `docs/tasks/phase-N.md`. Machine setup: `opskit/bin/dev-env`.
2. Read only the referenced SPEC/doc sections.
3. State: phase, task, files to touch (flag any upstream file).

## Golden rules
- **Phase 0 = install & explore Activepieces as it is** (`/opskit-explore`): no opskit code, no upstream changes. Then continue; ask the owner only when blocked or unclear.
- ONE task at a time; never jump ahead. SPEC silent → simplest option consistent with SPEC 3, log in ASSUMPTIONS.
- Never invent Activepieces env vars, tables, APIs or piece CLI commands: check the pinned source/docs/running instance first; *(verify)* items must be verified and recorded.
- **Community Edition only**: never `AP_EDITION=ee`, never touch `packages/ee/` or `packages/server/api/src/app/ee/`.
- **Client safety**: no secrets in git; destructive actions need `--yes`, typed client id, and owner approval.
- Never mark done unless `opskit/bin/check` passes (and `opskit/bin/opskit selftest` from Phase 2).
- Never remove or weaken a test. Don't edit SPEC or anything in `.claude/` without approval.
- Stop and ask before: new dependencies, upstream file edits, anything touching a real client host.

## Stack
Upstream: TypeScript monorepo (bun, turbo), Docker app/worker, Postgres, Redis. Opskit: Bash (shellcheck, bats), JSON schema, envsubst/yq/jq, Caddy, ufw, age, rclone, Uptime Kuma; GitHub Actions. Run everything in Linux: the Claude Code cloud session (Docker daemon started by the SessionStart hook) or WSL2 Ubuntu on the owner's Windows laptop (12 GB RAM).

## Repo layout (ours)
`opskit/bin` · `opskit/lib` · `opskit/schema` · `opskit/templates` · `opskit/agent` (host scripts) · `opskit/flows` · `opskit/tests` · `opskit/clients` + `opskit/hosts` (git-ignored) · `packages/pieces/custom/` · `.github/workflows/opskit-*.yml` · `explore/` (Phase 0 scratch, git-ignored) · `docs/`

## Commands (Linux shell)
`opskit/bin/check` · `opskit/bin/check --quick` · `opskit/bin/opskit doctor` · `opskit/bin/opskit selftest` · `docker compose -p <id> ps`

## End of every task
Update PROGRESS (incl. **Next steps**, precise enough for any AI or person to continue — see `docs/HANDOFF.md`); ADR for architectural choices; ledger for upstream edits; conventional commit; push.

## Rules (always apply)

### Workflow rules

#### Task loop
1. Plan: list files to create/modify and the approach (max ~10 bullets). Wait for approval if the task touches upstream (non-opskit) files, dependencies, secret generation, backup/restore/upgrade logic, anything destructive, or any real client host.
2. Implement in small steps. After each meaningful step, run `opskit/bin/check --quick`.
3. Verify: `opskit/bin/check`, plus the manual check described in the task file.
4. Record: update `docs/PROGRESS.md`; add an ADR to `docs/DECISIONS.md` if an architectural choice was made.

#### Scope control
- Only work on the current task in `docs/tasks/phase-N.md`.
- If you notice a bug outside scope, log it in PROGRESS.md "Known issues". Don't fix it silently.
- Features marked V2/Future in the spec: do not implement. Only keep the data model/interfaces ready.

#### Anti-hallucination
- Before using a library function, confirm it exists in the installed version (read the installed package's types/source or the official docs for that version).
- Before calling an internal function, search the codebase to confirm its name and signature. Don't assume.
- Don't claim something works unless you ran it. Say "not verified" otherwise.
- If a command fails, read the actual error output before changing code. Don't guess-and-retry repeatedly; after 3 failed attempts, stop and report.

#### Context hygiene
- When the conversation gets long, update PROGRESS.md with exact next steps and recommend starting a new task.
- Keep files under ~300 lines; split by responsibility.

### Architecture rules (mirror of SPEC Section 3)

- Our code lives only in `opskit/`, `packages/pieces/custom/`, `.github/workflows/opskit-*.yml`, `docs/`, IDE config. Everything else is upstream.
- One client = one stack: own compose project (`-p <client_id>`), `.env`, volumes `<id>_postgres`/`<id>_redis`, domain, backups. Never share data between stacks.
- `client.yaml` (validated by `opskit/schema/client.schema.json`) drives rendering; never hand-edit compose/.env on servers — change config, re-render, redeploy.
- Rendered stacks always: pinned image tag, `AP_EDITION=ce`, worker `AP_FRONTEND_URL=http://app`, worker replicas from config (default 1), memory limits, healthchecks, only Caddy publishing ports.
- Hosts send alerts directly to the configured channels (Telegram, email, Slack) and push heartbeats to Uptime Kuma; no hub in the alert path (an ops-hub stack is for demos only).
- Scripts are Bash, `set -euo pipefail`, idempotent; host agent scripts in `opskit/agent/` are standalone (no repo needed on hosts).
- Custom pieces follow upstream piece conventions and ship only via our CI image.
- Follow `docs/TECH_ARCHITECTURE.md` Section 3 layout and command pattern.

### Security & client-data rules

#### Never read, print, or commit
- `.env` files, `opskit/clients/**`, `opskit/hosts/**`, private keys (age, SSH), DB dumps, rclone configs, tokens.

#### Always
- Generate secrets with `openssl rand`; abort if any required secret is empty.
- Destructive actions (delete volume/stack, restore over data, drop DB, prune remote backups early) need `--yes` + typed client id + owner approval in chat.
- Hosts: SSH keys only, root login disabled, ufw 22/80/443, Postgres/Redis never published, `.env` mode 600.
- Encrypt `.env` escrow with the owner's age public key; never store the private key in the repo or on hosts.
- Detectors/reports use a read-only DB role and read-only SQL.
- Alert/report payloads: no secrets, no full personal data; error excerpts ≤ 300 chars.
- Gemini free tier only with practice data; client AI steps use client-owned keys.
- Never set `AP_EDITION=ee`, never touch `packages/ee/` or `packages/server/api/src/app/ee/`, never add a license key.

### Upstream fork rules

- Upstream `AGENTS.md`/`CLAUDE.md` govern upstream code; follow them if an approved patch touches upstream files.
- `main` = pinned release tag + our commits; `upstream` remote fetch-only; never merge upstream automatically; sync only via `docs/UPSTREAM_SYNC.md` when the owner asks.
- Upstream GitHub Actions stay disabled in the fork; our CI lives in `.github/workflows/opskit-*.yml`.
- Changing any upstream file needs approval + ledger row in `docs/UPSTREAM_CHANGES.md` + test, in one commit.
- Items marked *(verify)* in SPEC must be verified against the pinned version (source, docs, running instance) and recorded in `docs/ASSUMPTIONS.md` before code depends on them.

### Ops script rules

- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, `IFS=$'\n\t'` where lists are parsed, shellcheck clean, `--help`.
- Quote all variables; no `eval`; no parsing `ls`; use `mktemp` + `trap` cleanup.
- Remote actions via `opskit/lib/ssh.sh` helpers only (BatchMode, StrictHostKeyChecking=accept-new, timeouts).
- Docker commands always with `-p <client_id>`; never `docker system prune` or volume removal outside offboard/restore flows.
- Print a one-line summary per step (`[ok]`, `[warn]`, `[fail]`); exit non-zero on failure.
- Templates render with `envsubst`/`yq` from validated config; fail on unresolved `${...}`.
- Keep functions small; shared logic in `opskit/lib/`.

### Reliability rules (backups, alerts, upgrades)

- A backup counts only if: dump + encrypted `.env` exist locally and remotely, sizes > 0, and a heartbeat reached its Uptime Kuma push monitor.
- Restores go into a fresh stack; never over a running stack without `--overwrite --yes`.
- Monthly automated restore test per client; result appears in the care report.
- Failed-run detector: read-only SQL, runs every 5 min, de-duplicates (30 min window), includes flow name + run link.
- Every alert names client, severity (`info|warn|critical`), what happened, first action to take; owner always gets Telegram.
- Upgrades: backup → staging on new image → smoke tests → promote → smoke → rollback on any failure; record history.
- Never lose `AP_ENCRYPTION_KEY`: escrow before first deploy; verify decryption in restore tests.

### Custom pieces & flow template rules

- Custom pieces and our own image are V2: do not build them in V1.
- Flow templates: `flow.json` (exported, placeholders instead of real IDs/keys), `README.md`, `test/` payloads, `CHECKLIST.md`; every template includes a failure-notification convention.
- Templates must import into a fresh CE stack of the pinned version before they count as done.

### Testing & quality rules

#### Definition of Done
- [ ] `opskit/bin/check` passes (shellcheck + bats; `--quick` skips docker integration)
- [ ] From Phase 2: `opskit/bin/opskit selftest` passes (local Docker stack; no real clients)
- [ ] New logic has tests; bugs get a failing test first
- [ ] PROGRESS.md updated with manual verification steps

#### What must have tests
- Secret generation never empty; config/schema validation errors
- Compose/.env/Caddy rendering (worker URL, replicas, limits, CE edition, pinned tag)
- Backup → restore round trip incl. stored connection decrypting; retention pruning
- Failed-run detector query + de-duplication; alert payload per channel
- Upgrade promote and rollback paths
- Care report numbers vs fixture DB
- Custom piece actions (upstream test runner)

#### Tools
shellcheck, bats-core, docker compose (cloud session or WSL) for integration tests, mock channel endpoint (small HTTP listener), fixture Postgres data. Never test against real client hosts.

### Git rules

- Conventional commits (upstream uses commitlint): `feat(opskit): …`, `fix(opskit): …`, `feat(pieces): …`, `test: …`, `docs: …`, `chore: …`.
- Commit after each completed task; never a broken state. Work on the branch the session names (cloud: `claude/...`); the owner merges finished phases to `main` by PR. Upstream syncs on `sync/<tag>`.
- Never commit `.env`, keys, `opskit/clients/`, `opskit/hosts/`, dumps, rclone configs.
- Never push to `upstream`; our pushes go to `origin` only.
- Commit before risky changes so they can be reverted.
