# Automation Ops Kit (Activepieces fork) — Product & Technical Specification (V1.0)

> **Build, host, and care for client automations on Activepieces Community Edition — safely, repeatably, and profitably.**
> **Source of truth:** this SPEC. The owner's roadmap `05-activepieces-roadmap.md` (25 Sep 2026) is a **reference only**. Binding owner decisions (27 Sep 2026): fork `activepieces/activepieces` (needed for custom pieces on the free edition) and install client servers from the enhanced fork on the owner's GitHub; Community Edition (MIT) only; hosting kit supports one-server-per-client (main) and several clients per server; scope C — all 8 improvements (Section 2.1), built only after Phase 0; alerts via Telegram for demos, email/Telegram/Slack/WhatsApp for clients. Research: `docs/RESEARCH.md`. **Owner decisions 20 Oct 2026** (plan review after pinning 0.92.3, Appendix C): custom pieces/own image → V2; WhatsApp → later add-on; alerts sent directly by host scripts + Uptime Kuma (ops-hub only for demos); shared hosts → after the first paying client; Phase 0 builds 1–2 starter flows; go-to-market step after Phase 4; telemetry off; data/privacy note and Zapier migration checklist in handover docs.

---

## 0. Instructions for the AI coding agent (READ FIRST)

1. **This repo is a fork of `activepieces/activepieces`.** Upstream's own `AGENTS.md`/`CLAUDE.md` govern upstream code. Our product rules are in this SPEC, and `.claude/CLAUDE.md` (Claude Code), which holds the always-on rules.
2. **Phase 0 installs and explores Activepieces as it is:** fork, set it up in the Claude Code cloud session (or WSL2) the free way, build 1–2 starter flows by hand, fill `docs/EXPLORATION_REPORT.md`. No ops-kit code and no upstream changes in Phase 0. Then continue to Phase 1 — pause and ask the owner **only** if something blocks the plan.
3. **Build phase by phase** using Section 17; each phase must pass its acceptance criteria before the next starts.
4. **Community Edition only.** Never set `AP_EDITION=ee`, never import, copy, or modify anything in `packages/ee/` or `packages/server/api/src/app/ee/` (commercial license), never add a license key.
5. **Upstream files are changed only through the patch ledger** (`docs/UPSTREAM_CHANGES.md`); our code lives in `opskit/`, `packages/pieces/custom/`, `.github/workflows/opskit-*.yml`, `docs/`, and the IDE config folders.
6. **Client data safety:** never commit client secrets, `.env` files, database dumps, or client configs; every destructive command (delete volume, restore over data, drop DB) needs explicit owner approval in the chat.
7. **All ops commands run in a Linux shell** (WSL2 Ubuntu on the laptop, Ubuntu 24.04 on servers). Scripts are Bash, `set -euo pipefail`, shellcheck-clean.
8. When this spec is ambiguous, pick the simplest option consistent with Section 3, record it in `docs/ASSUMPTIONS.md`, continue. Items marked *(verify)* must be checked against the pinned upstream version and recorded.
9. Write automated tests (bats + shellcheck for scripts, Vitest/Jest per upstream convention for custom pieces) for: secret generation (never empty), config validation, compose rendering, multi-stack port/route allocation, backup/restore round trip, retention pruning, failed-run detection query, alert payloads, upgrade rollback, report numbers.
10. Features marked **V2** must NOT be built.

---

## 1. Product overview

**Automation Ops Kit** ("opskit") is the owner's fork of Activepieces plus an operations kit that turns the open-source Zapier alternative into a sellable **setup + hosting + care** service:
- **Activepieces CE (upstream, MIT):** visual flow builder, pieces (integrations), triggers, branches, loops, code steps, AI steps, run logs; 4 containers (app, worker, Postgres, Redis).
- **Opskit (our code):** per-client deployment kit (secure config, HTTPS, firewall, right-sized workers), backups with off-server copies and tested restores, monitoring and failure alerts routed through an **ops-hub**, a flow template library, safe upgrades with staging and rollback, handover docs and monthly care reports. Alerts go straight from host scripts and Uptime Kuma to the owner/client channels. Custom pieces and an own Docker image are V2.

**Buyers (roadmap):** small agencies, e-commerce stores, clinics/service businesses, coaches, real estate, businesses paying a lot for Zapier. Agencies can white-label the *service* (not the Activepieces UI branding, which is a paid feature).

**Positioning (research):** Activepieces CE is MIT, so hosting clients' workflows is allowed (n8n's Sustainable Use License requires an Enterprise license for that). Activepieces Cloud now charges per active flow ($5/flow/month after 10 free). The service sells reliability: alerts, backups, updates, and someone who fixes things.

### Glossary
| Term | Meaning |
|---|---|
| Upstream | `github.com/activepieces/activepieces`; remote `upstream`, fetch-only. |
| Pinned release | Upstream release tag our `main` is based on. |
| Client stack | One Activepieces install (app, worker, postgres, redis) for one client, with its own `.env`, volumes, domain. |
| Host | A server running one (dedicated) or several (shared) client stacks behind one Caddy. |
| Monitoring host | The owner's Uptime Kuma (plus, for demos only, an owner Activepieces "ops-hub" stack). Receives heartbeats; alerts themselves are sent directly by host scripts. |
| Client registry | `opskit/clients/<client_id>/` (git-ignored): `client.yaml`, rendered compose, `.env` (secret), docs. |
| Flow template | Exported flow JSON + README + test payloads in `opskit/flows/<template>/`. |
| Custom piece | (V2) Our TypeScript integration in `packages/pieces/custom/<name>`; CE admins can also install pieces via `POST /api/v1/pieces` (npm or archive). |
| Care report | Monthly per-client summary: runs, failures, uptime, backups, updates, changes. |

---

## 2. Scope

### 2.1 Agreed improvements (owner, scope C, 27 Sep 2026) — all built after Phase 0
| # | Improvement | Phase |
|---|---|---|
| 1 | Client deployment kit (config generator, HTTPS, firewall, worker fix, sizing, pinned version, dedicated hosts; shared hosts after the first paying client) | 2 |
| 2 | Backups + restore (daily dumps, encrypted key escrow, off-server copies, tested restore) | 3 |
| 3 | Monitoring + failure alerts (uptime, failed-run detector, direct alert sending, daily digest) | 4 |
| 4 | Flow template library (6 starter flows, test data, import guide) | 5 |
| 5 | Safe upgrade runbook/script (checklist, backup, staging, smoke tests, rollback) | 6 |
| 6 | Client handover docs (flow one-pagers, pause guide, credential ownership) | 7 |
| 7 | Monthly care report | 7 |
| — | Go to market (offer, pricing, one-page site, demo) — minimum sellable service = Phases 1–4 | 4b |
| 8 | Custom pieces + own Docker image from the fork | V2 |

### V2 (not now)
Custom pieces + own Docker image (Improvement 8), WhatsApp alerts (paid add-on), shared hosts (until the first paying client), alert routing through an ops-hub, single multi-tenant install (needs paid Projects), UI white-label (paid), Kubernetes/Helm, a web control panel for the fleet, automatic Zapier import, client self-service portal, embedding.

---

## 3. Architecture rules (non-negotiable)

1. **Fork layout.** Our paths: `opskit/` (bin, lib, templates, flows, clients [git-ignored], tests), `packages/pieces/custom/` (custom pieces), `.github/workflows/opskit-*.yml`, `docs/`, Claude Code config (`.claude/CLAUDE.md`, `.claude/hooks/`, `.agents/skills/opskit-*`, nested `CLAUDE.md` files in our folders), `README-START-HERE.md`. Everything else is upstream.
2. **Upstream untouched by default.** Changes to upstream files need owner approval + ledger row + test. Upstream GitHub Actions are disabled in the fork (Settings → Actions) so they don't run or fail on our pushes; our workflows are separate files.
3. **Pinned releases, manual sync.** `main` = upstream release tag + our commits; `upstream` remote is fetch-only; updates follow `docs/UPSTREAM_SYNC.md`. No automated merges.
4. **Community Edition.** Every rendered `.env` sets `AP_EDITION=ce` explicitly (verified: default `ce`); code steps run `AP_EXECUTION_MODE=UNSANDBOXED` (verified default; fine for one client per server per upstream docs); `AP_TELEMETRY_ENABLED=false`.
5. **One client = one stack.** Separate compose project, `.env`, volumes, domain, and backups per client, on dedicated hosts (shared hosts later). No client data shared between stacks.
6. **Config as data.** `client.yaml` (validated against `opskit/schema/client.schema.json`) drives everything: domain, host, mode (dedicated/shared), image + version, worker replicas, memory limits, alert channels, backup target, report recipients. Templates render from it; no hand-edited compose files on servers.
7. **Secrets never in git.** `.env`, keys, tokens live only on the host and in the encrypted escrow (Section 9.3). `opskit/clients/` is git-ignored. Generation uses `openssl rand` and **fails** if any required value is empty.
8. **Idempotent scripts.** Re-running any `opskit` command converges to the same state; destructive steps require `--yes` plus an explicit confirmation prompt with the client id.
9. **Direct alerts.** Host scripts send alerts straight to the configured channels (Telegram, email via msmtp, Slack) through `opskit` alert helpers, and push heartbeats to Uptime Kuma push monitors. No single hub sits in the alert path.
10. **Scripts are Bash (Linux).** `opskit/bin/opskit` dispatcher + `opskit/lib/*.sh`; shellcheck-clean; bats tests. Small helpers may use `jq`, `yq`, `envsubst`, `curl`, `rclone`, `age`. No Python/Node required on hosts.
11. **Custom pieces (V2)** will follow upstream piece conventions in `packages/pieces/custom/<name>`; never hot-patch a running container.

---

## 4. Tech stack & environment

| Area | Choice |
|---|---|
| Base | Fork of `activepieces/activepieces` (MIT CE), pinned to the latest release tag in Phase 0 |
| Upstream stack | TypeScript monorepo (bun, turbo), Node per `.nvmrc`, Docker images `app` + `worker`, Postgres, Redis |
| Laptop | Windows 10/11, 12 GB RAM, WSL2 Ubuntu, Docker Desktop (WSL2 backend), VS Code opened in WSL (Remote-WSL) |
| Hosts | Ubuntu 24.04 VPS, ≥ 2 vCPU / 4 GB RAM per client stack (official minimum); shared hosts sized by sum of stacks |
| Reverse proxy | Caddy (automatic HTTPS, WebSockets) |
| Firewall | ufw: 22, 80, 443 only |
| Backups | `pg_dump` via the postgres container, compressed; secrets archive encrypted with `age`; off-server copy with `rclone` (Backblaze B2, S3-compatible, Google Drive, or another server) |
| Monitoring | Owner's Uptime Kuma (uptime + heartbeat push monitors); UptimeRobot free as an external second check of Uptime Kuma itself |
| Alerts | Sent directly by host scripts: Telegram bot (demo + clients), email (SMTP via msmtp), Slack (incoming webhook). WhatsApp = later add-on |
| Tests | shellcheck, bats-core, docker-based integration tests in WSL; upstream test runner for custom pieces |
| CI | GitHub Actions `opskit-ci.yml` (shellcheck + bats). Clients run official images (`activepieces/activepieces:<tag>` on Docker Hub or `ghcr.io/activepieces/activepieces:<tag>`) |

---

## 5. Actors & permissions
| Action | Owner (operator) | Client |
|---|---|---|
| Deploy, upgrade, restore, backups, alerts | ✅ | ❌ |
| Build/edit flows in the client's Activepieces | ✅ | optional (client account; roadmap: allowed, charge for access/support) |
| Own third-party accounts/API keys used in flows | shares access | ✅ owns them (roadmap: client creates accounts, shares via password manager) |
| Receive care reports and alerts | ✅ | ✅ (channels chosen per client) |

---

## 6. Client registry & configuration

`opskit/clients/<client_id>/client.yaml` fields: `client_id` (slug), `name`, `contact` (email), `domain` (e.g. `auto.client.com`), `host` {`name`, `ip`, `ssh_user`, `mode`: `dedicated|shared`}, `image` {`repo` (default `ghcr.io/activepieces/activepieces`), `tag`}, `ap_version` (upstream release it's based on), `workers` {`replicas`: default 1, `memory_limit`}, `app` {`memory_limit`}, `port` (shared mode, later), `timezone`, `alerts` {`channels`: [`telegram`, `email`, `slack`], per-channel targets}, `backup` {`schedule` (default daily 02:30 host time), `retention_days` (14 local / 30 remote), `remote` (rclone remote name)}, `report` {`recipients`, `day_of_month`: 1}, `support` {`response_hours`: 12}, `created_at`, `status` (`draft|deployed|paused|offboarded`).
Rendered per client: `compose.yml`, `.env`, `Caddy` site block, `cron` entries, `docs/`.

---

## 7. Deployment kit (Improvement 1)

1. `opskit client new <id>` → scaffolds `client.yaml` from `opskit/templates/client.yaml.tmpl`, validates it.
2. `opskit render <id>` → renders compose + `.env` + Caddy block from templates:
   - pinned image tag; `AP_EDITION=ce`; worker service gets its own `AP_FRONTEND_URL=http://app` (official fix for the empty Workers page); `replicas` from config (default 1, not upstream's 5); memory limits; healthchecks; named volumes `<id>_postgres`, `<id>_redis`; restart policy.
   - secrets via `openssl rand` for `AP_API_KEY`, `AP_ENCRYPTION_KEY`, `AP_JWT_SECRET`, `AP_POSTGRES_PASSWORD` (the 4 that upstream `tools/deploy.sh` generates, verified 0.92.3); **abort if any is empty**.
   - `AP_TELEMETRY_ENABLED=false` (client privacy).
   - `AP_FRONTEND_URL=https://<domain>` for the app.
3. `opskit host bootstrap <host>` (fresh Ubuntu 24.04): Docker + compose plugin, ufw (22/80/443), unattended security upgrades, swap if RAM ≤ 4 GB, Caddy container, `opskit` agent files (backup, health, heartbeat scripts), SSH key-only login check.
4. `opskit deploy <id>` → copies rendered files over SSH, `docker compose -p <id> up -d`, waits for `GET /api/v1/health`, checks the worker is registered (verified: `GET /api/v1/worker-machines` as platform admin, or Platform Admin → Operations → Workers), adds the Caddy site, verifies HTTPS, registers the stack in Uptime Kuma, records in `client.yaml`. The app listens on port 80 inside its container (IPv6 `::`, so hosts must not disable IPv6 in the kernel). Hosts need outbound HTTPS to `cloud.activepieces.com` (piece catalog, templates) and `registry.npmjs.org` (piece code).
5. **Shared hosts (later — after the first paying client):** ports auto-allocated from `opskit/hosts/<host>.yaml`; each stack gets its own Caddy site; `opskit host capacity <host>` warns if Σ memory limits > 85% of RAM.
6. `opskit client pause|resume|offboard <id>`: offboard = final backup → export flows → hand over → stop stack → delete after `offboard_retention_days: 30` with approval.
7. Local practice: the same commands work against a WSL "host" using Caddy's internal CA and `*.localhost` domains *(inferred)*.

## 8. Explore-derived defaults
Phase 0 records real RAM use, startup time, worker behavior, and CE feature availability (projects, API keys, piece management, alerts, templates import/export). Phases 2–8 must use those findings; if the exploration contradicts this SPEC, the agent asks the owner before continuing.

## 9. Backups & restore (Improvement 2)
1. Nightly on each host (cron): `pg_dump` through the stack's postgres container → `/<backups>/<id>/<ts>.sql.gz`; also `docker compose config` snapshot.
2. Secrets escrow: `.env` encrypted with `age` to the owner's public key → `<ts>.env.age`; the owner's private key is stored offline/password manager only.
3. Off-server copy via `rclone` to the client's configured remote; local retention 14 days, remote 30 days; pruning is tested.
4. Every backup writes a status line (size, duration, success) and sends a heartbeat to its Uptime Kuma push monitor; failure → direct alert.
5. `opskit restore <id> --from <ts> [--target staging|new-host]` restores into a fresh stack (never over a running one without `--overwrite --yes`), then runs smoke checks.
6. **Monthly automated restore test** into a temporary stack on the monitoring host or a local machine; result included in the care report.
7. Redis is treated as a cache/queue (not backed up) *(verify that no durable state lives only in Redis)*.

## 10. Monitoring & alerts (Improvement 3)
1. **Monitoring host**: the owner's Uptime Kuma. Backup watchdog = an Uptime Kuma push monitor per client (missed heartbeat after 26 h → alert). Daily digest = a host cron script that sends one summary message. An owner "ops-hub" Activepieces stack may exist for demos only; nothing depends on it.
2. **Uptime:** Uptime Kuma checks each client's `https://<domain>/api/v1/health` every 1 min; UptimeRobot free checks Uptime Kuma itself.
3. **Failed-run detector** (host cron, every 5 min): read-only SQL on `flow_run` (verified 0.92.3: `status`, `finishTime`, `failedStep`, `projectId`, `flowId`, `flowVersionId`) for runs with status in FAILED, INTERNAL_ERROR, TIMEOUT, MEMORY_LIMIT_EXCEEDED, QUOTA_EXCEEDED, LOG_SIZE_EXCEEDED since the last check → send summary (flow name, run id, error excerpt ≤ 300 chars, link) directly to the channels; de-duplicated. The built-in CE alerts module is hidden in the UI (`SHOW_ALERTS=false`) and owner-only, so it is not used.
4. **Host health**: disk > 85%, memory pressure, container restarts, cert expiry < 14 days → alert.
5. **Channels:** Telegram (bot token + chat id), email (SMTP), Slack (incoming webhook). WhatsApp is a later add-on (needs the client's Meta Business setup). Each client chooses channels; the owner always receives Telegram.
6. Alert payload format, severity levels (`info|warn|critical`) and quiet hours (per client timezone) live in `opskit/templates/alerts/`.

## 11. Flow template library (Improvement 4)
Templates in `opskit/flows/<template>/`: `flow.json` (exported from Activepieces), `README.md` (what it does, trigger, steps, connections needed, how to pause, test data), `test/` (sample payloads), `CHECKLIST.md` (roadmap testing checklist: 5+ runs, failure cases, error notifications to owner, client-owned credentials).
Starter set (roadmap): 1 lead capture (webhook form → sheet → owner email → auto-reply), 2 AI email sorter (Gmail → AI classify → label + Slack), 3 review request (order → wait 7 days → email), 4 invoice reminder (schedule → unpaid rows → reminder), 5 social lead alert (lead ads → CRM → WhatsApp/email), 6 Elmo monthly report (schedule → Elmo API → email summary).
Every template includes an **error branch or failure notification** convention consistent with Section 10. Import/export method uses what CE supports *(verify: UI import/export vs API — Phase 0 blocked on piece catalog, re-check)*; templates from the cloud gallery need `cloud.activepieces.com`; if only UI, `opskit flows import` prints step-by-step instructions and validates the JSON.

## 12. Safe upgrades (Improvement 5)
`opskit upgrade <id> --to <tag>`:
1. Show upstream breaking changes between versions (link + manual checklist `docs/runbooks/upgrade-checklist.md`) and require confirmation.
2. Fresh backup (Section 9) → restore into a **staging stack** with the new image → smoke tests (health, worker registered, test webhook flow runs, one scheduled flow dry run); reuse upstream's `smoke-test/` and rollback guide where they fit.
3. If staging passes: upgrade production (pull, up -d), re-run smoke tests; if they fail: automatic rollback to previous tag + restore if migrations ran.
4. Record upgrade in `client.yaml` history and the care report.
Our fork's own upstream sync (new Activepieces releases → new image) follows `docs/UPSTREAM_SYNC.md`; client upgrades use only images built from a synced, tested `main`.

## 13. Handover docs & care report (Improvements 6, 7)
- `opskit docs <id>` renders client docs from templates: overview of active flows (from template READMEs + client notes), "how to pause a flow", credential ownership checklist, support/response-time promise, backup and data-location summary, a **data & privacy note** (where data is stored, who can access it), and a **Zapier → Activepieces migration checklist** for clients moving from Zapier.
- `opskit report <id> --month YYYY-MM`: runs total/succeeded/failed per flow (read-only SQL *(verify)*), uptime % (Uptime Kuma API *(verify)*), backups (count, last success, last restore test), upgrades applied, incidents, hours used vs included; rendered HTML + PDF-friendly; emailed (msmtp) on `report.day_of_month` by an owner-side cron.

## 14. Custom pieces & own image (Improvement 8) — V2 (owner, 20 Oct 2026)
Not built in V1. Phase 0 found CE admins can install pieces via `POST /api/v1/pieces` (npm package or archive), which may remove the need for an own image; re-evaluate in V2.
- Develop pieces in `packages/pieces/custom/<name>` using upstream's CLI and conventions *(verify current commands: create/build/test)*; first piece: `opskit-heartbeat` (action: send heartbeat/event to ops-hub) as the reference implementation.
- `opskit-image.yml` builds the CE image from our fork (pinned tag + custom pieces) and pushes to GHCR as `ghcr.io/<owner>/activepieces:<upstream-tag>-ops.<n>`; build runs on GitHub Actions (too heavy for the 12 GB laptop *(verify)*).
- Verify how CE loads bundled custom pieces (piece source/sync settings) *(verify)*; document the working method in ADR.

## 15. Security
SSH keys only; root login disabled; ufw; unattended upgrades; containers not exposing Postgres/Redis ports publicly; Caddy only public entry; secrets in `.env` with 600 permissions; `age` escrow; client credentials inside Activepieces are encrypted by `AP_ENCRYPTION_KEY` (never rotate it without the documented procedure); least-privilege read-only DB role for detectors/reports *(inferred)*; alert payloads never include secrets or full personal data.

## 16. Environment & commands
Laptop: all commands in WSL Ubuntu. Key commands: `opskit/bin/opskit doctor`, `opskit/bin/check` (shellcheck + bats; `--quick` skips docker integration tests), `opskit/bin/opskit selftest` (renders a demo client, deploys it to a local WSL stack, runs backup→restore→smoke tests, tears down). Variables and files: `docs/ENVIRONMENT.md`.

---

## 17. Build phases

Each phase: implement → `opskit/bin/check` → (from Phase 2) `opskit/bin/opskit selftest` → pass acceptance → update `docs/PROGRESS.md` → continue.

### Phase 0 — Fork, set up & explore Activepieces (as it is, no changes)
Runs in the Claude Code cloud session (webhooks tested on the same machine, no ngrok; RAM/CPU from the cloud machine). Fork on GitHub; `upstream` remote fetch-only; pin `main` to the latest release tag (record tag + SHA in `docs/UPSTREAM_CHANGES.md`); disable upstream GitHub Actions in the fork. Install locally **the official way** (docker compose, CE — no `AP_EDITION=ee`), apply the worker `AP_FRONTEND_URL=http://app` fix, reduce worker replicas to 1, confirm `/api/v1/health` and the Workers page. Explore with free tools: admin account; builder basics; webhook trigger (local); schedule trigger; branches, loops, delays, code step, HTTP piece; AI step with a Gemini free-tier key (practice data only); run logs, retries, failure display; flow import/export; templates; Platform Admin in CE — record exactly what's available vs locked (projects, API keys, piece management, alerts/notifications, branding, audit logs, Git Sync); build 1–2 starter flows by hand (the full set is Phase 5); back up the Postgres volume and `.env`, restore into a fresh local stack; measure RAM/CPU idle and under 20 test runs; try upstream piece development locally (create a hello-world piece in dev mode) if the laptop can handle it; inspect run tables for Section 10.3 *(read-only)*. Fill every section of `docs/EXPLORATION_REPORT.md` (answers to all *(verify)* items). No opskit code, no upstream changes.
**Accept:** Activepieces CE runs locally with worker registered; report complete with CE feature matrix, *(verify)* answers, RAM/CPU numbers, flow-building notes for 1–2 starters, and a successful local backup→restore; blockers/mismatches logged and owner asked before continuing.

### Phase 1 — Opskit foundation
`opskit/` structure, `bin/opskit` dispatcher, `lib/` (logging, confirm, render, ssh, validate), JSON schema for `client.yaml` + `hosts/*.yaml`, `bin/check`, bats + shellcheck setup, `opskit doctor` (WSL, Docker, compose v2, tools), `opskit-ci.yml` (shellcheck + bats on push), `.gitignore` for `opskit/clients/` and secrets, docs ledger/sync files completed.
**Accept:** `opskit/bin/check` passes locally and in CI; `opskit doctor` reports tools; invalid `client.yaml` fixtures fail validation with field-level messages; `git diff <pinned-tag> --stat` lists only our paths.

### Phase 2 — Client deployment kit (Improvement 1)
`client new/render/deploy/pause/resume/offboard`, `host bootstrap`, templates (compose, `.env`, Caddy, cron), secret generation with non-empty checks, local practice host, `selftest` (render → local deploy → health → teardown).
**Accept:** bats tests prove secret generation aborts on empty values; rendered compose has worker `AP_FRONTEND_URL=http://app`, `replicas` from config, memory limits, pinned tag, `AP_EDITION=ce`, `AP_TELEMETRY_ENABLED=false`; `selftest` deploys a stack whose health endpoint returns OK and worker registers; re-running `deploy` is idempotent.

### Phase 3 — Backups & restore (Improvement 2)
Backup script + cron, `age` escrow, rclone remote copy, retention pruning, heartbeat, `restore` into fresh stack, monthly restore-test job.
**Accept:** backup of a demo client with 3 flows restores into a new stack where the flows and a stored connection work (proves `AP_ENCRYPTION_KEY` escrow); pruning keeps exactly the configured days (fixture test); restore refuses to overwrite a running stack without `--overwrite --yes`; failed backup triggers an alert payload (mock channel endpoint).

### Phase 4 — Monitoring & alerts (Improvement 3)
Uptime Kuma deployment via the kit; direct alert helpers; daily-digest script; backup watchdog via push monitors; failed-run detector; host health checks; channel adapters (Telegram, email, Slack); quiet hours; de-duplication.
**Accept:** a deliberately failing demo flow produces exactly one Telegram alert within 10 minutes with flow name and run link; stopping a client stack triggers an uptime alert; a missed backup heartbeat triggers the watchdog after 26 h (time-shifted test); Slack and email adapters pass payload tests; alerts still arrive when no ops-hub exists.

### Phase 4b — Go to market (owner-led, agent assists)
Phases 1–4 = minimum sellable service. Offer and pricing (from Section 18), a one-page site, a 3-minute demo; start finding clients while Phases 5–7 are built.
**Accept:** owner signs off offer, pricing sheet, page draft and demo script in `docs/go-to-market/`.

### Phase 5 — Flow template library (Improvement 4)
Six templates with `flow.json`, README, test payloads, checklist, error-notification convention; `opskit flows list/validate/import` (per CE capability).
**Accept:** each template imports into a fresh local stack and passes its sample-run instructions (using free/test accounts; where a paid third-party account is required, documented as manual test); `flows validate` catches malformed JSON and missing placeholders.

### Phase 6 — Safe upgrades (Improvement 5)
`upgrade` with breaking-change checklist, staging restore, smoke tests, promote, automatic rollback; `docs/runbooks/upgrade-checklist.md`; fork sync rehearsal.
**Accept:** upgrading a demo client from the previous to the pinned release passes staging and production smoke tests; an injected smoke-test failure triggers rollback and the client is back on the old tag with data intact; upgrade history recorded.

### Phase 7 — Handover docs & care report (Improvements 6, 7)
`docs` generator, credential ownership checklist, data & privacy note, Zapier migration checklist, `report` (runs/failures/uptime/backups/upgrades/incidents/hours), `monthly-report-sender` flow.
**Accept:** report numbers for a demo month match fixture DB counts exactly; generated handover docs list every active flow with pause instructions; report email is delivered to a test inbox; handover docs include the privacy note and Zapier checklist.

### Phase 8 — Custom pieces & own image (Improvement 8) — **moved to V2 (owner, 20 Oct 2026); skip**
`packages/pieces/custom/opskit-heartbeat`, piece tests, `opskit-image.yml` building the CE image with custom pieces → GHCR, deploy kit switched to our image, verified loading method (ADR).
**Accept:** CI publishes `ghcr.io/<owner>/activepieces:<tag>-ops.1`; a stack deployed from it shows the `opskit-heartbeat` piece in the builder and a flow using it reaches the ops-hub; image runs as CE (no license prompts, no ee features enabled).

### Phase 9 — Field readiness
Practice production run on a real VPS (Oracle Always Free if capacity allows, else a ~$5 VPS, deleted after): host bootstrap → client deploy with real domain + HTTPS → 2 templates live → backup → off-server copy → restore test → upgrade dry run → care report; `docs/OPERATOR_GUIDE.md`; pricing worksheet (VPS cost per client for dedicated vs shared); 3-minute demo script (roadmap Loom).
**Accept:** the whole run completes from the operator guide without undocumented steps; costs and timings recorded in PROGRESS; server deleted or kept as the monitoring host by owner decision.

---

## 18. Notes for the owner
- **Pricing check:** each client stack needs ≥ 2 vCPU/4 GB; dedicated VPS ≈ $6–24/month depending on provider; shared hosts lower cost per client but share failure risk. Price "hosting + care" above server cost + your time.
- **WhatsApp alerts** are a later paid add-on: they need the client's WhatsApp Business setup (Meta Cloud API, message templates).
- **Oracle Always Free** is good for practice/the monitoring host; capacity is often unavailable and it isn't ideal for paying clients.
- **Never lose `AP_ENCRYPTION_KEY`**: without it, stored connections can't be decrypted even from a full database backup.
- **Paid-only features** stay unused. Phase 0 (0.92.3) confirmed locked in CE: API keys, audit logs, Git Sync, project members/roles, branding, SSO/SCIM, secret managers, global connections, manage pieces/templates UI, MCP servers, agents, environments, embedding. Available: 1 team project, tables, analytics, AI providers, admin piece install via API.

## Appendix A — Roadmap items changed by research or owner decisions
| # | Roadmap said | Spec does | Why |
|---|---|---|---|
| R1 | Clone and run | Fork on GitHub, pin release, fetch-only upstream; clients install from the enhanced fork's image | Owner wants an enhanced repo; custom pieces need a fork on CE |
| R2 | `tools/deploy.sh` manual path | Official path explored first; kit renders config itself with non-empty secret checks, CE edition, worker URL fix, 1 replica | Docs changed; `AP_EDITION=ee` path and 5 replicas unsuitable |
| R3 | "Error notifications to you" | Ops-hub + failed-run detector + uptime + backup watchdog | CE lacks some alerting features *(verify)*; reliability is the product |
| R4 | Daily pg_dump to /backups | + encrypted key escrow + off-server copy + tested restores | Key loss makes backups useless; local-only backups die with the server |
| R5 | Oracle free VM for first client | Practice/ops-hub only; paid VPS for clients | Capacity and reliability |
| R6 | Update script | Staging + smoke tests + rollback | Updates are the main breakage risk |

## Appendix B — Open questions for the owner
1. Your business name and the domain for the monitoring host (e.g. `status.yourbrand.com`)?
2. Preferred VPS provider for clients (Hetzner, DigitalOcean, Vultr, Contabo…)?
3. Off-server backup target: Backblaze B2 (10 GB free), Google Drive, or another VPS?
4. Response-time promise for care clients (default 12 h)?

## Appendix C — Owner decisions after Phase 0 setup (20 Oct 2026)
| # | Decision |
|---|---|
| C1–C6 | Accepted: app port 80 in container; EE code also in `packages/server/api/src/app/ee/`; verified CE values (edition, health, Workers page, `flow_run`, 4 secrets, unsandboxed OK); detector covers all failed statuses; reuse upstream smoke tests/rollback guide; Phase 0 in the cloud |
| R1 | Custom pieces + own image → V2 |
| R2 | WhatsApp alerts → later add-on |
| R3 | Alerts sent directly by host scripts + Uptime Kuma; ops-hub only for demos |
| R4 | Phase 0 builds 1–2 starter flows |
| R5 | Shared hosts after the first paying client |
| A1 | Minimum sellable service = Phases 1–4, then Phase 4b go to market |
| A2 | `AP_TELEMETRY_ENABLED=false` on client stacks |
| A3 | Disable upstream's auto-enabled third-party Claude plugins/MCP in `.claude/settings.json` (ledger #2) |
| A4 | Data & privacy note in handover docs |
| A5 | Zapier → Activepieces migration checklist |
