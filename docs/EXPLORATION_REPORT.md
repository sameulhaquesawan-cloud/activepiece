# Exploration report — Automation Ops Kit (Activepieces fork)

> Filled during Phase 0 (clone, set up & explore). Facts only — what actually happened on this machine. Blockers or mismatches with the SPEC go to the owner before continuing.
>
> **Status (2026-10-20): nearly complete.** Two machines: the Claude cloud session (install, backup→restore, idle stats; containers there have no internet) and GitHub Codespace `verbose-trout` (4-core, 16 GB; `opskit/bin/explore-stack up` via `.devcontainer/opskit`, driven over its public 8080 URL) for everything needing pieces. Open: AI step (needs owner's Gemini key), stored-connection decrypt after restore, per-container RAM under load. Screenshots: `docs/phase0-screenshots/`.

## 1. Setup
| Item | Value |
|---|---|
| Repo + commit/version explored | Fork at upstream tag `0.92.3` (`2fc7f8dc`), image `activepieces/activepieces:0.92.3` (Docker Hub, digest `sha256:26daa5e1…3bb1`, in-image `package.json` version 0.92.3) |
| How it was installed/cloned | Official way: upstream `docker-compose.yml` + `tools/deploy.sh` (generates `.env` with 4 secrets) copied into git-ignored `explore/stack/`; project name `ap0`. Override file: `AP_EDITION=ce` (app + worker), app `AP_FRONTEND_URL=http://localhost:8080`, worker `AP_FRONTEND_URL=http://app`, worker replicas 1, `AP_TELEMETRY_ENABLED=false` |
| Machine (CPU/RAM/GPU/OS) | (a) Claude Code cloud container: 4 vCPU, 15 GB RAM, no GPU, Linux 6.18, Docker 29.9.1, Compose v5.6.0, no IPv6 in kernel. (b) GitHub Codespace 4-core / 16 GB, Ubuntu 24.04 devcontainer + docker-in-docker; first build to healthy stack ≈ 5–10 min, no errors |
| Free path used (keys, free tiers, local models) | No keys used yet. Gemini free tier not tried yet |
| Setup time + problems hit (and fixes) | ~15 min incl. fixes. (1) dockerd started without proxy env → restarted with `HTTPS_PROXY`. (2) GHCR blob host `pkg-containers.githubusercontent.com` denied by session network policy → pulled the same official tag from Docker Hub (one 429 rate-limit, retry worked). (3) App crash-loop `listen EAFNOSUPPORT :::80`: `packages/server/api/src/main.ts` hard-codes `host: '::'` and this kernel has no IPv6 → sandbox-only `NODE_OPTIONS=--require` shim in `explore/` rewrites `::` to `0.0.0.0` (no upstream change; real VPS hosts have IPv6). After that `/api/v1/health` → `{"status":"Healthy"}` 7 s after container start |

## 2. Feature walkthrough
| Feature | Tried with (sample data) | Result (works / partly / broken) | Notes, screenshots/log paths |
|---|---|---|---|
| Health endpoint | `GET /api/v1/health` | works | `{"status":"Healthy"}` |
| Worker registration / Workers page data | `GET /api/v1/worker-machines` | works | 1 SHARED worker, `executionMode: UNSANDBOXED`, 5 poll loops (concurrency 5 per worker) |
| Admin account | `POST /api/v1/authentication/sign-up` (admin@example.com) | works | First user becomes platform `ADMIN`, verified, gets a PERSONAL project |
| Piece catalog | `GET /api/v1/pieces` | works (Codespace) / broken (cloud session) | Codespace: 771 pieces within ~20 s of first start. Cloud session: empty — app syncs from `cloud.activepieces.com` (`PIECES_SYNC_MODE=OFFICIAL_AUTO`) and containers there have no internet. Image bundles only 5 pieces' webhook handlers |
| Templates | `GET /api/v1/templates` | works (Codespace) | 420 cloud templates listed; 500 `fetch failed` without internet. Platform Admin → Templates (own templates) is paid (crown) |
| Projects | `POST /api/v1/projects` | works (limit 1 team project) | Created a TEAM project; plan `billedTeamProjectsLimit: 1` |
| Alerts | `GET/POST /api/v1/alerts` | partly | Module registered in CE, but `SHOW_ALERTS=false` in UI; personal projects only allow the owner as receiver |
| Install piece (npm or archive upload) | read source `pieces/community-piece-module.ts` | available in CE (not tried live) | `POST /api/v1/pieces`, platform admin only, `packageType: REGISTRY` (npm name+version) or `ARCHIVE` (tarball) |
| Starter 1: Lead capture (webhook → code → router → HTTP / failing code) | `{name,email}` good + bad email | works | Built via API `IMPORT_FLOW` (valid on first try) and visible in the builder (screenshot 2). Good lead SUCCEEDED in 0.43 s; bad email FAILED at `step_4` as designed. Sheet/owner email/auto-reply replaced by HTTP POST to postman-echo (no accounts in Phase 0) |
| Starter 4: Invoice reminder (schedule every 1 min → code → loop → code → delay 10 s → code) | 3 sample invoices | works | First scheduled run fired 1 min after publish; 10.2 s total (delay honoured inline); loop output per item correct; flow disabled afterwards |
| Webhook URLs | — | works | Async `/api/v1/webhooks/<flowId>`, sync `/sync` (30 s → 408), test `/test`. Webhook trigger auth: none/basic/header |
| Run logs + failure display | failed run | works | Runs page lists status, duration, failure; `GET /api/v1/flow-runs/<id>` has per-step status/output; `flow_run.failedStep` = `{name, displayName, message}` where `message` is a JSON string `{message, raw stack}` → detector can use `failedStep->>'displayName'` + parsed message (trim to 300 chars) |
| Retries | — | partly | Per-step `retryOnFailure` / `continueOnFailure` settings exist and import fine; a failing-then-succeeding retry was not exercised |
| Flow export / import | lead capture flow | works | `GET /api/v1/flows/<id>/template` → JSON (name, flows[].trigger tree, pieces, no flow/project IDs); importing its trigger into a new flow via `IMPORT_FLOW` gives a valid flow. Enough for `opskit flows import` via API |
| AI step (Gemini free tier) | — | *not done yet* | Needs the owner's free Gemini API key (practice data only) |
| Backup → restore into fresh stack | admin, 2 projects, worker | works | `pg_dump` via postgres container (2 s, 29 KB gz) + `.env` copy → new project `ap0r` (no `container_name`, port 8081): start postgres+redis, wait for the **second** "ready to accept connections" (first-boot init restarts postgres), `psql` restore (1 s), then `up -d` → healthy in 10 s; admin signs in with the old password, both projects present, worker registers. Stored-connection decrypt not tested yet (no pieces) |
| Hello-world piece in dev mode | — | skipped | Custom pieces moved to V2 (owner, 20 Oct 2026) |

**CE feature matrix (platform plan flags, live):** on — tables, analytics, AI providers. Off/locked — API keys (route 404), audit logs (404), Git Sync (404), project members (404), MCP servers (404), manage pieces, manage templates, custom appearance/branding, project roles, custom roles, global connections, SSO, SCIM, secret managers, environments, event streaming, embedding, agents, chat, worker groups, custom domains. `PRIVATE_PIECES_ENABLED=false` flag, yet the CE install-piece endpoint above exists.

## 3. Performance on this machine
| Task | Input size | Time | Notes |
|---|---|---|---|
| App start → healthy | empty DB (migrations) | 7 s (after fix) | |
| Image size | — | — | app 2.15 GB, pgvector 609 MB, redis 171 MB |
| Idle CPU/RAM | empty instance | — | `docker stats`: app 480 MiB / 0.2 % CPU, worker 218 MiB, postgres 54 MiB, redis 8 MiB → ≈ 760 MiB total idle |
| Backup / restore | 29 KB dump | 2 s / 1 s | restored stack healthy 10 s after restore |
| 20 test runs (Codespace) | 20 concurrent webhooks, lead capture flow | 2.3 s to accept all, 8.6 s until all finished | each run 0.29–0.35 s (Runs page); 20/20 SUCCEEDED, no errors; 1 worker (5 concurrent slots) |
| RAM under load | — | not measured | Worker's own `ramUsagePercentage` showed 98 % on a 16 GB codespace (counts page cache — unreliable); per-container `docker stats` needs the Codespace terminal |

## 4. Output quality
Client-ready: the builder shows flows built by API exactly like hand-built ones (screenshot 2); runs list with durations and failure column (screenshot 3); clear step-level error text. Not client-ready on its own: no failure alerts in CE (alerts hidden), so clients would never hear about the failed run without our detector. Branding is Activepieces (paid white-label), fine for the service model.

## 5. Limits & risks found
- **Pieces and templates depend on `cloud.activepieces.com` at runtime.** A host that cannot reach it has an empty builder. Client hosts need outbound HTTPS to it and to `registry.npmjs.org`.
- **IPv6 required for the app to listen** (`host: '::'` hard-coded). Fine on normal VPS; a host with IPv6 disabled at kernel level crash-loops.
- Code steps run `UNSANDBOXED` by default (OK for one client per server, per upstream docs).
- Telemetry is on by default (`AP_TELEMETRY_ENABLED` default `true`).
- Upstream failed-states list (`FAILED_STATES` in `core/execution`): FAILED, INTERNAL_ERROR, QUOTA_EXCEEDED, TIMEOUT, MEMORY_LIMIT_EXCEEDED — not LOG_SIZE_EXCEEDED. All statuses: those + PAUSED, QUEUED, RUNNING, SUCCEEDED, CANCELED, LOG_SIZE_EXCEEDED.
- `flow_run` columns (source): id, created, updated, projectId, flowId, flowVersionId, environment, logsFileId, parentRunId, failParentOnFailure, status, tags, startTime, triggeredBy, finishTime, timeline, failedStep, archivedAt, stepNameToTest, stepsCount. Live read-only check done: same columns (+ deprecated `pauseMetadata` jsonb); `status` is varchar; indexes include `(projectId, environment, status, created, archivedAt)`, so a status + time-window detector query is indexed.

## 6. Matches the SPEC? (agent's view)
- **Custom pieces:** V2 (owner). CE admins can install a piece from npm/archive via API — re-check in V2.
- **Flow templates (Phase 5):** import/export works over the API with the platform admin's token; `opskit flows import` can use it (CE API keys are paid, so use a user JWT from sign-in).
- **Failed-run detector (Phase 4):** `flow_run.status` + `failedStep` JSON give everything an alert needs (step name, display name, error message).
- **Alerts:** a built-in alert module exists but is hidden in CE; our own detector (SPEC 10.3) is still needed.
- **Client hosts need egress** to `cloud.activepieces.com` and `registry.npmjs.org` (add to Phase 2 firewall/doctor checks).
- No blockers for Phase 1. Open Phase 0 items (AI step, connection decrypt after restore, RAM under load) don't change the plan.

## 7. Questions for the owner (only if blocked or unclear)
1. ~~Network allow-list~~ — done by owner 20 Oct 2026.
2. ~~Containers have no internet in the Claude cloud session~~ — solved by moving piece-dependent work to a GitHub Codespace (owner, 20 Oct 2026).
3. For the AI step: a free Gemini API key (aistudio.google.com) — optional; Phase 0 can close without it.

## 8. Addendum — Phase 5 template facts (task 5.1, 21 Oct 2026)
Sources: pinned 0.92.3 source (paths below), the live piece API `https://cloud.activepieces.com/api/v1/pieces/<name>?release=0.92.3`, `https://secrets.activepieces.com/apps?edition=ce`, and the Phase 0 runs (section 2).

**Export / import format**
- Export: `GET /api/v1/flows/<id>/template` → `{name, description, flows:[{displayName, trigger, schemaVersion, notes}], pieces, …}`, no flow/project ids (Phase 0, section 2).
- UI import (`features/flows/utils/template-parser.ts`) accepts `{name, flows:[…]}` (or legacy `{name, template}`); for each flow it calls create flow, then `IMPORT_FLOW` (`flow-hooks.tsx importFlowsFromTemplates`). Same file works in the UI and in `opskit flows import`.
- API import = `POST /api/v1/flows {displayName, projectId}` then `POST /api/v1/flows/<id> {type: IMPORT_FLOW, request:{displayName, trigger, schemaVersion, notes}}`. The server migrates old `schemaVersion`s (`flow.controller.ts` preValidation) and clears sample data. The flow is a draft and is not published → it starts switched off.
- Sign-in: `POST /api/v1/authentication/sign-in {email,password}` → `token`, `projectId` (used since Phase 3). CE has no API keys.

**Piece versions** (`piece-metadata-service.ts findExactVersion`)
- A step's `pieceVersion` is exact (`^`/`~` stripped on add). Import looks it up among catalog versions allowed for the running release; a version the stack does not know → `404 piece_metadata_not_found` and the import fails (no silent upgrade).
- So templates pin the versions the 0.92.3 catalog serves, and `flows validate` checks them; re-pin after an Activepieces upgrade.

| Piece | Version (0.92.3) | Used for | Auth on CE |
|---|---|---|---|
| `@activepieces/piece-webhook` | 0.1.42 | `catch_webhook` | none / basic / header |
| `@activepieces/piece-schedule` | 0.1.22 | `every_day` … `cron_expression` | — |
| `@activepieces/piece-delay` | 0.4.0 | `delayFor` (`delayFor` + `unit`) | — |
| `@activepieces/piece-smtp` | 0.5.0 | `send-email` | host/port/email/password/TLS |
| `@activepieces/piece-http` | 0.13.0 | `send_request` | — |
| `@activepieces/piece-google-sheets` | 0.18.2 | `insert_row`, `find_rows`, `update_row` | OAuth2 (preconfigured app) or service account |
| `@activepieces/piece-gmail` | 0.18.1 | `gmail_new_email_received` (polling), `gmail_add_label_to_email`, `send_email` | OAuth2 (preconfigured app) or service account (Workspace only) |
| `@activepieces/piece-slack` | 0.23.1 | `send_channel_message` | OAuth2 (preconfigured app) or bot token |
| `@activepieces/piece-hubspot` | 0.13.1 | `create-or-update-contact` | OAuth2 (preconfigured app) or private-app token |
| `@activepieces/piece-facebook-leads` | 0.5.1 | `new_lead` (APP_WEBHOOK) | OAuth2, own Meta app only |
| `@activepieces/piece-openai` | 0.13.2 | fallback for template 2 | API key |
| `@opskit/piece-openai-compatible` | 0.1.0 (ours) | `ask_model` | base URL + key |

**Connections on self-hosted CE** (`oauth-apps-hooks.ts`, `multi-auth-list.tsx`, `cloud-oauth2-service.ts`)
- CE has no platform OAuth apps, but `platform.cloudAuthEnabled` defaults to true, so pieces listed by `secrets.activepieces.com/apps?edition=ce` offer **"OAuth2 (Recommended)"**: Gmail, Google Sheets, Slack, HubSpot (and Facebook Pages) — not Facebook Lead Ads. The code exchange and every token refresh go through `secrets.activepieces.com` (Activepieces Inc.), which therefore sees the OAuth tokens.
- Every OAuth2 piece also offers **"Custom OAuth2 App (Advanced)"**: the client's own client id/secret, redirect URL `https://<domain>/redirect`; tokens stay on the client's server.
- Token-based options with no third party: Google service account (Sheets: share the sheet with its email; Gmail: Workspace with domain-wide delegation only), Slack bot token, HubSpot private-app token.
- **Facebook Lead Ads** (`new_lead` is an `APP_WEBHOOK` trigger; `app-event-routing.module.ts`, `execute-webhook.ts`, upstream `docs/install/configure-operate/setup-app-webhooks.mdx`): needs the client's (or our) own Meta app, its webhook pointed at `https://<domain>/api/v1/app-events/facebook-leads` with verify token `activepieces`, and `AP_APP_WEBHOOK_SECRETS={"@activepieces/piece-facebook-leads":{"webhookSecret":"<Meta app secret>"}}` on the app container (read by the app, passed to workers). One Meta app per stack (one webhook URL per app). Meta app review may be needed for `leads_retrieval` outside development mode.

**Custom piece install** (`community-piece-module.ts`, `AddPieceRequestBody`): `POST /api/v1/pieces` multipart, platform admin, `packageType=ARCHIVE scope=PLATFORM pieceName pieceVersion pieceArchive` — done live in Phase 1 (piece README). The archive (`dist/*.tgz`, 96 KB, git-ignored) is built with the upstream CLI; CI does not build it yet.

## 9. Addendum — Phase 6 upgrade facts (task 6.1, 22 Oct 2026)
Sources: pinned 0.92.3 source (`packages/server/api/src/rollback.ts`, `app/database/rollback-migrations.ts`, `migration/postgres/*`), the published images, and a real upgrade + rollback on a local practice stack (opskit deploy, round-trip data: 3 flows, 1 stored connection).

| Fact | Evidence |
|---|---|
| Image tags before the pin: …, 0.91.4, 0.92.0, 0.92.1, **0.92.2**, 0.92.3 on ghcr.io and Docker Hub | registry tag lists |
| 0.92.2 → 0.92.3: **no schema change** (same 427 named migrations in `dist/src/migration-manifest.json`) | both images' manifests |
| 0.91.4 → 0.92.3: **11 new migrations**, one marked `breaking` (`NullOrphanFolderReferences1846000000000`) | `migrations` table before/after |
| Upgrade = change the image tag + `opskit deploy`: 0.91.4 → 0.92.3 took **15 s** incl. health/worker/HTTPS waits (image pre-pulled); data intact (flows, sign-in, connection decrypt) | experiment |
| **The old image starts and reports healthy on the newer schema** (no check, no error) | experiment: 0.91.4 on a 0.92.3 database |
| Upstream rollback: `node dist/src/rollback.js --to <version>` or `--manifest '<json names>'`, run with the **newer** image (`/usr/src/app/packages/server/api`), reverts migrations one by one, refuses breaking ones without `--force` (exit 1) | source + experiment |
| `--to <version>` selects by each migration's `release` label, and labels are unreliable: 3 migrations shipped since ≤0.92.0 say `0.103.0`, migrations first shipped in 0.92.x say `0.91.0`/`0.88.4` → wrong set; its order check then aborts | source + experiment |
| `--manifest` (list of migration names of the old version) selects exactly the right 11 | experiment |
| **`--force` rollback 0.92.3 → 0.91.4 fails half way**: reverted 5 of 11, then `DROP INDEX CONCURRENTLY cannot run inside a transaction block` (`IndexWaitpointLookups1847000000000` down) → database left between versions | experiment |
| Each image carries its migration list in `/usr/src/app/packages/server/api/dist/src/migration-manifest.json` (unnamed migrations are `null`) | images |

**Consequences for the design (6.7):** upstream's undo is not dependable across releases, and an old image hides a too-new schema. The automatic rollback therefore restores a database dump taken **right before the switch with the app and worker stopped** (nothing is lost but what arrived on the new version during the upgrade window), then starts the old tag. The migration undo stays a documented manual tool (`--manifest`, never automatic `--force`). The production smoke test must compare the `migrations` table with the running image's manifest so a mismatch is caught.

## 10. Addendum — Phase 7 report facts (task 7.1, 22 Oct 2026)
| Fact | Finding | Source |
|---|---|---|
| Run rows | `flow_run`: `projectId`, `flowId`, `flowVersionId`, `environment` (`PRODUCTION` / test runs), `status`, `created`, `startTime`, `finishTime`, `archivedAt` (set by "archive" in the Runs page; the row stays), `parentRunId` | `packages/server/api/src/app/flows/flow-run/flow-run-entity.ts` |
| Run retention | `AP_EXECUTION_DATA_RETENTION_DAYS` (default 30) deletes the run **log files** only; run rows stay | `system.ts`, `file/file.service.ts` (`deleteStaleBulk`) |
| Deleted flows | `flow_run.flowId` and `flowVersionId` are `ON DELETE CASCADE`: deleting a flow deletes its runs | `flow-run-entity.ts` relations |
| Statuses | `SUCCEEDED`; failed = `FAILED`, `INTERNAL_ERROR`, `TIMEOUT`, `MEMORY_LIMIT_EXCEEDED`, `QUOTA_EXCEEDED`, `LOG_SIZE_EXCEEDED`; other = `CANCELED`, `PAUSED`, `RUNNING`, `QUEUED` | `packages/core/execution/.../flow-execution.ts` |
| Active flows | `flow.status = 'ENABLED'`, published version via `flow.publishedVersionId` → `flow_version.displayName`, `flow_version.trigger` (JSON: `settings.pieceName`, `triggerName`, nested actions' `pieceName`) | `flow.entity.ts`, `packages/core/piece-types/src/lib/flow-contracts.ts` |
| Read-only role | `opskit_ro` reads `flow`, `flow_version`, `flow_run`, `project` only (no connections, no users) | `opskit/templates/readonly-role.sql` |
| Uptime source | Uptime Kuma 2.5.5 keeps raw heartbeats (`heartbeat` table: time UTC, status 0 down / 1 up / 2 pending / 3 maintenance) for `keepDataPeriodDays` (default 365); socket `getMonitorBeats(monitorID, hours)` returns them. `getMonitorChartData` only gives UTC-day buckets beyond 720 h, so month edges in the client's time zone would be blurred. A paused monitor writes no beats (planned upgrade downtime is not counted) | `/app/server/server.js`, `socket-handlers/chart-socket-handler.js`, `uptime-calculator.js`, `jobs/clear-old-data.js` in the image |
| Backups | Each backup's `status.json` lives only as long as the backup (14 days local, 30 remote); a failed night leaves nothing. A month report needs an append-only per-run history on the host | `opskit/agent/backup.sh` |
| Restore tests, upgrades | `clients/<id>/restore-tests.jsonl`; client.yaml `history` (`upgraded`, `upgrade_failed`, `rolled_back`, `deployed`) | Phases 3, 6 |
