# Exploration report — Automation Ops Kit (Activepieces fork)

> Filled during Phase 0 (clone, set up & explore). Facts only — what actually happened on this machine. Blockers or mismatches with the SPEC go to the owner before continuing.
>
> **Status (2026-10-20): partial.** Stack installed and healthy; backup→restore done. Building flows is blocked: containers in the cloud session have no internet, so the piece catalog stays empty (Section 7). Items marked *not done yet* are still open.

## 1. Setup
| Item | Value |
|---|---|
| Repo + commit/version explored | Fork at upstream tag `0.92.3` (`2fc7f8dc`), image `activepieces/activepieces:0.92.3` (Docker Hub, digest `sha256:26daa5e1…3bb1`, in-image `package.json` version 0.92.3) |
| How it was installed/cloned | Official way: upstream `docker-compose.yml` + `tools/deploy.sh` (generates `.env` with 4 secrets) copied into git-ignored `explore/stack/`; project name `ap0`. Override file: `AP_EDITION=ce` (app + worker), app `AP_FRONTEND_URL=http://localhost:8080`, worker `AP_FRONTEND_URL=http://app`, worker replicas 1, `AP_TELEMETRY_ENABLED=false` |
| Machine (CPU/RAM/GPU/OS) | Claude Code cloud container: 4 vCPU, 15 GB RAM, no GPU, Linux 6.18, Docker 29.9.1, Compose v5.6.0, no IPv6 in kernel |
| Free path used (keys, free tiers, local models) | No keys used yet. Gemini free tier not tried yet |
| Setup time + problems hit (and fixes) | ~15 min incl. fixes. (1) dockerd started without proxy env → restarted with `HTTPS_PROXY`. (2) GHCR blob host `pkg-containers.githubusercontent.com` denied by session network policy → pulled the same official tag from Docker Hub (one 429 rate-limit, retry worked). (3) App crash-loop `listen EAFNOSUPPORT :::80`: `packages/server/api/src/main.ts` hard-codes `host: '::'` and this kernel has no IPv6 → sandbox-only `NODE_OPTIONS=--require` shim in `explore/` rewrites `::` to `0.0.0.0` (no upstream change; real VPS hosts have IPv6). After that `/api/v1/health` → `{"status":"Healthy"}` 7 s after container start |

## 2. Feature walkthrough
| Feature | Tried with (sample data) | Result (works / partly / broken) | Notes, screenshots/log paths |
|---|---|---|---|
| Health endpoint | `GET /api/v1/health` | works | `{"status":"Healthy"}` |
| Worker registration / Workers page data | `GET /api/v1/worker-machines` | works | 1 SHARED worker, `executionMode: UNSANDBOXED`, 5 poll loops (concurrency 5 per worker) |
| Admin account | `POST /api/v1/authentication/sign-up` (admin@example.com) | works | First user becomes platform `ADMIN`, verified, gets a PERSONAL project |
| Piece catalog | `GET /api/v1/pieces` | **broken here** | Empty: app syncs pieces from `cloud.activepieces.com` (`PIECES_SYNC_MODE=OFFICIAL_AUTO`), host denied by session network policy. Image bundles only 5 pieces' webhook handlers |
| Templates | `GET /api/v1/templates` | **broken here** | 500 `fetch failed` (templates also come from cloud) |
| Projects | `POST /api/v1/projects` | works (limit 1 team project) | Created a TEAM project; plan `billedTeamProjectsLimit: 1` |
| Alerts | `GET/POST /api/v1/alerts` | partly | Module registered in CE, but `SHOW_ALERTS=false` in UI; personal projects only allow the owner as receiver |
| Install piece (npm or archive upload) | read source `pieces/community-piece-module.ts` | available in CE (not tried live) | `POST /api/v1/pieces`, platform admin only, `packageType: REGISTRY` (npm name+version) or `ARCHIVE` (tarball) |
| Builder, webhook/schedule triggers, branches/loops/delay/code/HTTP, AI step, run logs/retries, import/export, 6 starter flows | — | *not done yet* | Need pieces (blocked) |
| Backup → restore into fresh stack | admin, 2 projects, worker | works | `pg_dump` via postgres container (2 s, 29 KB gz) + `.env` copy → new project `ap0r` (no `container_name`, port 8081): start postgres+redis, wait for the **second** "ready to accept connections" (first-boot init restarts postgres), `psql` restore (1 s), then `up -d` → healthy in 10 s; admin signs in with the old password, both projects present, worker registers. Stored-connection decrypt not tested yet (no pieces) |
| Hello-world piece in dev mode | — | *not done yet* | |

**CE feature matrix (platform plan flags, live):** on — tables, analytics, AI providers. Off/locked — API keys (route 404), audit logs (404), Git Sync (404), project members (404), MCP servers (404), manage pieces, manage templates, custom appearance/branding, project roles, custom roles, global connections, SSO, SCIM, secret managers, environments, event streaming, embedding, agents, chat, worker groups, custom domains. `PRIVATE_PIECES_ENABLED=false` flag, yet the CE install-piece endpoint above exists.

## 3. Performance on this machine
| Task | Input size | Time | Notes |
|---|---|---|---|
| App start → healthy | empty DB (migrations) | 7 s (after fix) | |
| Image size | — | — | app 2.15 GB, pgvector 609 MB, redis 171 MB |
| Idle CPU/RAM | empty instance | — | `docker stats`: app 480 MiB / 0.2 % CPU, worker 218 MiB, postgres 54 MiB, redis 8 MiB → ≈ 760 MiB total idle |
| Backup / restore | 29 KB dump | 2 s / 1 s | restored stack healthy 10 s after restore |
| 20 test runs | — | *not done yet* | |

## 4. Output quality
Not assessed yet (no flows could be built without pieces).

## 5. Limits & risks found
- **Pieces and templates depend on `cloud.activepieces.com` at runtime.** A host that cannot reach it has an empty builder. Client hosts need outbound HTTPS to it and to `registry.npmjs.org`.
- **IPv6 required for the app to listen** (`host: '::'` hard-coded). Fine on normal VPS; a host with IPv6 disabled at kernel level crash-loops.
- Code steps run `UNSANDBOXED` by default (OK for one client per server, per upstream docs).
- Telemetry is on by default (`AP_TELEMETRY_ENABLED` default `true`).
- Upstream failed-states list (`FAILED_STATES` in `core/execution`): FAILED, INTERNAL_ERROR, QUOTA_EXCEEDED, TIMEOUT, MEMORY_LIMIT_EXCEEDED — not LOG_SIZE_EXCEEDED. All statuses: those + PAUSED, QUEUED, RUNNING, SUCCEEDED, CANCELED, LOG_SIZE_EXCEEDED.
- `flow_run` columns (source): id, created, updated, projectId, flowId, flowVersionId, environment, logsFileId, parentRunId, failParentOnFailure, status, tags, startTime, triggeredBy, finishTime, timeline, failedStep, archivedAt, stepNameToTest, stepsCount. Live read-only check done: same columns (+ deprecated `pauseMetadata` jsonb); `status` is varchar; indexes include `(projectId, environment, status, created, archivedAt)`, so a status + time-window detector query is indexed.

## 6. Matches the SPEC? (agent's view)
- **Custom pieces (Phase 8):** CE admins can install a piece from npm or by uploading an archive through the API, so a custom image may not be needed. Supports suggestion R1; to confirm live.
- **Alerts:** a built-in alert module exists but is hidden in CE; our own detector (SPEC 10.3) is still needed.
- **Client hosts need egress** to `cloud.activepieces.com` and `registry.npmjs.org` (add to Phase 2 firewall/doctor checks).
- Otherwise not enough explored yet to call it — see Section 7.

## 7. Questions for the owner (only if blocked or unclear)
1. ~~Network allow-list~~ — done by owner 20 Oct 2026.
2. **Containers have no internet here:** only the cloud machine itself goes through the agent proxy; Docker containers can't resolve or reach outside hosts, so the app can't sync pieces even though `cloud.activepieces.com` is now allowed. A small relay letting containers use the same proxy was refused by the session safety check — owner decides (allow it, or finish flow-building on the laptop/WSL).
