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
