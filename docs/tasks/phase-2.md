# Phase 2 — Client deployment kit (Improvement 1)

SPEC: Section 17 Phase 2, Sections 3, 6, 7, 15; ADR-012 (dedicated hosts now, shared later); Phase 0 findings.
Owner (20 Oct 2026): "start next phase and finish it"; Phase 1 owner tests (CI 1.8, real-key 1.12) done together later.

## Design (recorded in ADR-014)
- Registry: `opskit/clients/<id>/client.yaml` + `secrets.env` (600, generated once, never regenerated) + `rendered/`; hosts in `opskit/hosts/<host>.yaml`.
- Host side: `<opskit_root>/clients/<id>/{compose.yml,.env}` (default `/opt/opskit`), Caddy container `opskit-caddy` on Docker network `opskit_edge`, one site file per client in `<opskit_root>/caddy/sites/<id>.caddy`.
- Only Caddy publishes ports; the app joins `opskit_edge` with alias `<id>-app`. Postgres/Redis only on the client's private network.
- Host transport `ssh` (real servers) or `local` (practice host / selftest, same code path minus SSH).
- Uptime Kuma registration → Phase 4; cron install, final backup and flow export on offboard → Phase 3.

## Tasks

### [x] 2.1 — Registry + `opskit client new`
- **Goal:** `lib/registry.sh` (paths, load client/host with yq, validate first); `client.yaml.tmpl`; `opskit client new <id> --domain --host [--contact --name]`; host schema gains `transport`, `opskit_root`, `edge` ports/TLS, `practice_quirks`.
- **Tests:** new client file validates; refuses existing id; bad id/domain rejected.

### [x] 2.2 — Secrets
- **Goal:** `lib/secrets.sh`: generate once with `openssl rand` (API key hex 64, Postgres hex 32, JWT hex 32, encryption key hex 16 = 32 chars), mode 600, abort on any empty/malformed value, never print values.
- **Tests:** stubbed empty `openssl` aborts; existing secrets are kept on re-run; permissions 600; format checks.

### [x] 2.3 — Templates + `opskit render <id>`
- **Goal:** `templates/compose.yml.tmpl`, `env.tmpl`, `caddy-site.tmpl`, `cron.tmpl` → `clients/<id>/rendered/`.
- **Acceptance:** compose: pinned image tag, `AP_EDITION=ce` + telemetry off, worker `AP_FRONTEND_URL=http://app`, `replicas` from config, memory limits, healthchecks, no `ports:` on app/worker/postgres/redis, no `container_name`, volumes `postgres`/`redis` (→ `<id>_postgres`, `<id>_redis`).
- **Tests:** bats on rendered output for each rule; unresolved var fails.

### [x] 2.4 — Host transport `lib/host.sh`
- **Goal:** `host_run`, `host_put` (local vs ssh via `lib/ssh.sh`), `host_load` (host file + defaults).
- **Tests:** local runs commands; ssh mode calls stubbed ssh/scp with the host's user/ip/port.

### [ ] 2.5 — `opskit host bootstrap <host>`
- **Goal:** `agent/bootstrap.sh` (standalone, idempotent; Ubuntu 24.04: docker + compose plugin, ufw 22/80/443, unattended-upgrades, swap ≤ 4 GB RAM, sshd key-only/no-root check) + edge setup (network `opskit_edge`, pinned Caddy container, sites dir). Local transport runs edge setup only.
- **Tests:** script shellcheck + `--dry-run` plan output; edge setup tagged docker.

### [ ] 2.6 — `opskit deploy <id>`
- **Goal:** validate → render → push files → `docker compose -p <id> up -d` → wait app healthy → worker registered (app log `Poll request received`) → write Caddy site + reload → HTTPS health through Caddy → record `status: deployed` + history.
- **Acceptance:** re-running deploy changes nothing (same container IDs).

### [ ] 2.7 — `opskit client pause|resume|offboard`
- **Goal:** pause/resume = compose stop/start + status; offboard = stop + status `offboarded` + `offboarded_at`; `--purge` (only after `offboard_retention_days`, `--yes` + typed id) removes the stack and its volumes.
- **Tests:** status transitions; purge refused before retention / without confirmation.

### [ ] 2.8 — `opskit selftest`
- **Goal:** demo client on a local practice host (high edge ports, Caddy internal CA, `*.localhost`): render → deploy → health + worker → re-deploy idempotent → teardown (selftest-owned project only).
- **Acceptance:** passes in the cloud session; bats test tagged docker.

### [ ] 2.9 — Docs
- **Goal:** operator steps in `docs/HANDOFF.md`/`docs/USER_FLOWS.md` (O1 onboard dedicated), ADR-014, PROGRESS.
