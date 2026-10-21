# Phase 6 — Safe upgrades (Improvement 5)

SPEC: Section 12 (`opskit upgrade <id> --to <tag>`), 9 (backups/restore, reused), 10 (alerts), 15 (security), 17 Phase 6; USER_FLOWS O6; `docs/UPSTREAM_SYNC.md` step 9; upstream `docs/install/configure-operate/rollback.mdx` (the image ships `npm run rollback -- --to <version>`, run with the **newer** image; releases with non-reversible migrations are flagged) and `docs/install/reference/breaking-changes.mdx`.
**Accept (SPEC 17):** upgrading a demo client from the previous to the pinned release passes staging and production smoke tests; an injected smoke-test failure triggers rollback and the client is back on the old tag with data intact; upgrade history recorded.
**Rule from `.claude/CLAUDE.md`:** tasks that touch backup/restore/upgrade logic wait for the owner's approval of the plan before code. This file is that plan.

## Open questions for the owner (recommended defaults in brackets — "ok" accepts them)
**Answered 22 Oct 2026:** owner said "ok" — all six defaults accepted, plan approved (incl. fetch-only access to `upstream` for 6.11).
- **Q1 — Where does staging run?** [On the operator machine (Codespace / WSL), exactly like the monthly restore test: the client's server is not loaded (a 4 GB VPS cannot hold a second stack), the new image gets real internet for pieces. Client data lands on your machine briefly and is removed — same as `restore-test`, so the DPA/privacy text already covers it. Option `--staging-host <host>` later if a client forbids that.]
- **Q2 — How is a failed upgrade rolled back?** [1) stop the app, run upstream's `npm run rollback -- --to <old>` with the new image (keeps data created since the backup); 2) if that fails or the release is marked non-reversible, restore the pre-upgrade backup into the same stack (loses at most the minutes since the backup). The old image tag is always started last. You are told which path ran.]
- **Q3 — What does the production smoke test do?** [No login to the client's builder (we do not hold the admin password): health endpoint, worker registered, all containers healthy, HTTPS, read-only database checks (flow/connection/run counts not lower than before, every stored connection still decrypts, enabled flows still enabled) and no failed-run alert in the first 5 minutes. The richer test (create a webhook flow, run it, scheduled dry run) runs in staging, where we can set a throwaway admin password in the restored copy.]
- **Q4 — Downtime and timing:** [An upgrade restarts the app (about 1–3 minutes; webhooks sent in that window may be lost). The command shows this, asks for `--yes` and the typed client id, and refuses outside the client's quiet hours unless `--now` is given. No automatic scheduling in V1.]
- **Q5 — Which "previous release" for the demo/acceptance?** [The newest published tag older than the pinned 0.92.3 that exists as an image (found in task 6.1); CI upgrades a throwaway stack from it to 0.92.3.]
- **Q6 — Pieces after an upgrade:** [The openai-compatible piece is re-installed from its committed archive and every flow template's pinned versions are re-checked (`flows check-pieces`) as part of the post-upgrade checklist; an upgrade never changes client flows.]

## Tasks

### [x] 6.1 — Verify upgrade facts (no code)
- **Goal:** on the pinned release and the previous one (CI or Codespace, pieces online): which image tags exist (ghcr + Docker Hub); what `npm run rollback -- --to` needs (env file, DB reachable, which container), what it prints for a non-reversible release (`breaking = true` migrations, `--force`), exit codes; what changes in the DB schema between the two tags; that `docker compose pull && up -d` with a new `AP_IMAGE` tag is enough (volumes, `cache`); how long an app restart takes; whether the previous tag runs against a DB migrated by the newer one without rollback (expected: no).
- **Spec refs:** 12, 0 (never invent commands), ASSUMPTIONS conventions
- **Files likely touched:** `docs/ASSUMPTIONS.md`, `docs/EXPLORATION_REPORT.md` (addendum)
- **Acceptance checks:** each fact has a source file or a run; the previous tag for the demo is named; blockers listed.
- **Tests required:** none (facts).
- **Result (22 Oct 2026):** EXPLORATION_REPORT §9, ASSUMPTIONS #24–26. Upstream undo is unreliable (stopped half way) → 6.7 restores the pre-switch dump instead; smoke checks the schema against the image manifest; demo 0.92.2 → 0.92.3, rollback round 0.91.4 → 0.92.3.

### [x] 6.2 — Upgrade plan and gates (`opskit upgrade <id> --to <tag> --plan`)
- **Goal:** read-only: validates the target tag (exists as an image, newer than current, only official repos), prints current → target, the upstream breaking-change entries between them (parsed from `docs/install/reference/breaking-changes.mdx` of the target tag, link otherwise), flags non-reversible migrations, shows the expected downtime, the pre-flight (latest backup younger than 26 h, off-server copy present, restore-test result of the last 35 days passed, disk and memory headroom, no upgrade lock) and prints the manual checklist `docs/runbooks/upgrade-checklist.md`. Changes nothing.
- **Spec refs:** 12.1
- **Files likely touched:** `opskit/lib/commands/upgrade.sh`, `opskit/lib/upgrade.sh`, `opskit/lib/upgrade_notes.sh`, `docs/runbooks/upgrade-checklist.md`, tests, fixtures (sample breaking-changes text)
- **Acceptance checks:** unknown/older/same tag, repo not official, missing backup, failed last restore-test each stop with a clear `[fail]`; a plan for a valid tag lists the breaking changes between the versions.
- **Tests required:** bats with fixture release notes and a mock registry check; no docker needed.
- **Result (22 Oct 2026):** `opskit/lib/upgrade.sh`, `commands/upgrade.sh`, `docs/runbooks/upgrade-checklist.md`, `upgrade_plan.bats` (11, one docker-tagged). Tag check via the registry API (ghcr / Docker Hub, no download); official repo enforced by the client schema; new migrations and the ones marked `breaking = true` are listed when both images are local (live: 0.91.4 → 0.92.3 = 11, `NullOrphanFolderReferences1846000000000`), otherwise counted at staging. The "no upgrade lock" gate is added with the lock in 6.3.

### [x] 6.3 — Image pre-check and upgrade lock/state
- **Goal:** `docker pull` of the target image on the **operator machine** and on the host (so the downtime is not spent downloading), checked by digest; a per-client lock (`<root>/state/<id>/upgrade.lock`, stale-lock rules) so two upgrades or an upgrade during a backup cannot overlap; `clients/<id>/upgrades/<ts>/state.json` records every step so an interrupted upgrade can be resumed or rolled back (`opskit upgrade <id> --resume|--rollback`).
- **Spec refs:** 12, 3 (idempotent scripts)
- **Files likely touched:** `opskit/lib/upgrade.sh`, `opskit/lib/commands/upgrade.sh`, tests
- **Acceptance checks:** `--plan` also fails when a lock is held; second concurrent upgrade refused; killed upgrade leaves a state file that names the next safe action; lock released on success/rollback.
- **Tests required:** bats with a fake host root (local transport).
- **Result (22 Oct 2026):** `opskit/lib/upgrade_run.sh` (lock dir `<root>/state/<id>/upgrade.lock` taken with `mkdir`, run id inside; waits up to 15 min for a running backup; `state.json` per step; pull here + on the host, same registry digest; `--resume`, `--unlock`; `--rollback` comes with 6.7), `opskit/agent/backup.sh` skips while a lock younger than 12 h exists (`--during-upgrade` for the upgrade's own backup). Tests: `upgrade_run.bats` (8), `backup_agent.bats` +1, shared `helpers/upgrade.bash`. Staging/switch/verify steps stop the run with "not available yet" until 6.5–6.6 (lock released, nothing changed).

### [x] 6.4 — Smoke-test library (`opskit/lib/smoke.sh`)
- **Goal:** reusable checks returning `[ok]/[fail]` lines: `smoke_health`, `smoke_containers`, `smoke_worker`, `smoke_https`, `smoke_counts` (flows/connections/runs not lower than a baseline file), `smoke_connections_decrypt`, `smoke_enabled_flows` (enabled flow count unchanged), `smoke_no_failed_runs` (read-only role, since a timestamp), `smoke_schema` (database `migrations` vs the running image's `migration-manifest.json`); and the richer staging-only checks needing a login: `smoke_webhook_flow` (create flow via API, publish, POST webhook, wait for SUCCEEDED, delete) and `smoke_schedule_dry_run` (every-minute schedule flow runs once). Reuses `verify.sh`, `deploy.sh` and `e2e.sh` helpers; an injectable failure (`OPSKIT_SMOKE_FAIL=<check>`) for tests.
- **Spec refs:** 12.2, 12.3
- **Files likely touched:** `opskit/lib/smoke.sh`, `opskit/lib/verify.sh`, tests
- **Acceptance checks:** every check passes on a selftest stack and fails with a precise message when its condition is broken (container stopped, wrong encryption key, lowered baseline).
- **Tests required:** docker-tagged bats; pieces-dependent checks skipped offline, mandatory in CI.
- **Result (22 Oct 2026):** `opskit/lib/smoke.sh` (production set `smoke_production`, `smoke_baseline`), `opskit/lib/smoke_flows.sh` (webhook and every-minute schedule flows, deleted afterwards), `opskit/lib/e2e_smoke.sh` in selftest: all checks pass on the selftest stack, then a lowered baseline, a stopped worker, a connection stored with another key and an unknown migration row are each detected with their own message and the stack is put back. Unit tests `smoke.bats` (8, stubbed stack). Failed-run check counts engine errors only and the schema rule allows the manifest's unnamed entries (ASSUMPTIONS #27–28). Flow checks not run here (pieces offline): CI.

### [x] 6.5 — Staging stack on the operator machine
- **Goal:** `upgrade_stage`: take a fresh backup (existing `backup.sh`), restore the latest backup into a temporary local stack (`restore_client` / `restore-test` machinery) **with the target image tag**, set a throwaway admin password in the restored copy only (bcrypt through the stack's own Postgres), run the full smoke set (6.4) incl. webhook and scheduled flow, record the result, tear down. Staging failure stops the upgrade before the client is touched.
- **Spec refs:** 12.2, 9.5
- **Files likely touched:** `opskit/lib/upgrade.sh`, `opskit/lib/restore.sh` (image override), `opskit/lib/practice.sh`, tests
- **Acceptance checks:** staging of the demo client on the target tag passes; with an injected smoke failure the run stops with exit ≠ 0 and the production stack is untouched (same container ids, same image); temp stack and data removed.
- **Tests required:** docker-tagged bats; part of `opskit selftest`.
- **Result (22 Oct 2026):** `opskit/lib/upgrade_stage.sh` (baseline → `backup.sh --during-upgrade` → `temp_stack_restore` on the target tag → `smoke_production` + temporary owner password via pgcrypto in the copy → webhook/schedule flows, required unless `OPSKIT_REQUIRE_PIECES=0` → teardown; logs in `upgrades/<run>/`). `temp_stack_restore`/`temp_stack_remove` moved to `practice.sh` and reused by `restore-test`. Plan gate: owner key readable. Verified live on a kept selftest stack (0.92.2 → 0.92.3 label): staging passed in 41 s incl. sign-in to the copy; with `OPSKIT_SMOKE_FAIL=schema` it stopped with exit 1, production containers and image unchanged, lock released, temp stack gone, no password in the logs. Automated docker coverage comes with the selftest upgrade rounds (6.10); flow checks need pieces (CI).

### [x] 6.6 — Production switch
- **Goal:** `upgrade_promote`: `docker compose pull` (new image), stop app + worker, take the **pre-switch dump** (`pg_dump -Fc`, encrypted like backups, kept in `clients/<id>/upgrades/<ts>/` on the host), re-render with the new `image.tag` (client.yaml is the source of truth), push files, `up -d`, wait for health + worker, publish site, run production smoke (6.4) against the baseline taken just before; on success update `client.yaml` `image.tag`/`ap_version`, redeploy agents/crons if templates changed. Confirmation: typed client id + `--yes`; quiet-hours gate (Q4).
- **Spec refs:** 12.3, 6
- **Files likely touched:** `opskit/lib/upgrade.sh`, `opskit/lib/stack.sh`, `opskit/lib/deploy.sh`, tests
- **Acceptance checks:** demo client ends on the new tag, healthy, with unchanged flow/connection counts; `client.yaml` shows the new tag; a failing production smoke hands over to 6.7.
- **Tests required:** docker-tagged bats; selftest step.
- **Result (22 Oct 2026):** `opskit/lib/upgrade_switch.sh`: quiet-hours gate (`alerts.quiet_hours` in the client's time zone, `--now` overrides; no quiet hours → `--now` required) and `--yes` + typed id before the lock (also on `--resume`); switch = stop app + worker → pre-switch dump on the host (`pg_dump -Fc`, `pg_restore --list` check, age-encrypted, plain file removed) → baseline with the app stopped → `image.tag` + `ap_version` → `deploy_client`; verify = `smoke_production` against that baseline. New plan gate: owner public key present (else deploy would drop the nightly backup; Known issues). Verified live on a kept selftest stack 0.92.2 → 0.92.3: 65 s total, ~15 s downtime, counts 3/1/0 unchanged, client.yaml + history on 0.92.3, pre-switch dump decrypts to a valid dump, lock released. Tests: `upgrade_run.bats` +1 (confirmation, quiet hours), `upgrade_plan.bats` (key gate). A failing production check currently stops with the `--rollback` instruction (automatic in 6.7). Docker bats/selftest round: 6.10.

### [x] 6.7 — Automatic rollback
- **Goal:** `upgrade_rollback` on any failure after the client was touched: stop app + worker, restore the **pre-switch dump** (taken in 6.6 with app + worker stopped) into the same database (drop + `pg_restore`, nothing else touched), start the old tag, run production smoke again incl. the schema check (ASSUMPTIONS #24, #26; upstream's undo is not used automatically); alert the owner (critical) with what failed, which path ran and what to do next; keeps the failed attempt's logs in `clients/<id>/upgrades/<ts>/`. Also `opskit upgrade <id> --rollback` for a manual rollback of the last upgrade within its retention.
- **Spec refs:** 12.3, 10 (alerts), 9.5
- **Files likely touched:** `opskit/lib/upgrade.sh`, `opskit/agent/alert.sh` use, tests
- **Acceptance checks:** injected production-smoke failure → client back on the old tag, same flow/connection counts, data created before the upgrade present; migration-rollback path and restore path both exercised; owner alert sent once.
- **Tests required:** docker-tagged bats (injected failures, both paths); selftest.
- **Result (22 Oct 2026):** `opskit/lib/upgrade_rollback.sh`. Two paths (ASSUMPTIONS #24 replaces "upstream undo"): **restore** (pre-switch dump decrypted here → `dropdb --force` + `createdb` + `pg_restore` in the same postgres) and **restart** (failure before the dump: database untouched); both then set the old tag, deploy, run the smoke set and send one critical alert to the owner only (new `alert.sh --owner-only`). Failed rollback keeps the lock (`rollback_failed`; plan and `--unlock` refuse). `opskit upgrade <id> --rollback --yes` (typed id) for the newest run that reached the switch, finished runs only within 7 days; pre-switch dumps older than that are pruned after the next successful upgrade. Scoped injection `OPSKIT_SMOKE_FAIL=production:<check>`, `OPSKIT_UPGRADE_FAIL=pre-switch-dump`. Verified live: 0.91.4 → 0.92.3 with `production:counts` → 11 migrations ran, rollback restored 0.91.4 (428 migrations), sign-in + 3 flows + connection intact, exactly 1 Telegram (mock) alert, exit 1; restart path back on 0.91.4 in 17 s; manual rollback of a finished 0.92.2 → 0.92.3 upgrade removed a row written after the switch. Tests: `upgrade_run.bats` +2, `alert_channels.bats` +1, `smoke.bats` +1. Docker bats/selftest rounds: 6.10.

### [ ] 6.8 — History and monitoring hooks
- **Goal:** `client.yaml` history gets `upgraded` / `upgrade_failed` / `rolled_back` events (tag, note, duration) — schema + `client_history_add`; Uptime Kuma maintenance note or monitor pause during the switch so the owner gets no false "Down"; failed-run detector and health agent keep running; `opskit client status` (if present) shows the running tag and last upgrade.
- **Spec refs:** 12.4, 10.1
- **Files likely touched:** `opskit/schema/client.schema.json`, `opskit/lib/registry.sh`, `opskit/lib/monitor_sync.sh`, tests
- **Acceptance checks:** history shows the sequence for a successful, a rolled-back and a staging-failed attempt; no false uptime alert during a planned upgrade (mock Kuma).
- **Tests required:** schema tests, bats with the mock channel.

### [ ] 6.9 — Post-upgrade steps: pieces and templates
- **Goal:** after a successful promote: re-install our `openai-compatible` piece from its archive if present on the client, run `flows check-pieces` against the new release's catalog and list templates whose pinned versions need re-pinning; print the owner's checklist (re-test affected flows, tell the client). Never edits client flows.
- **Spec refs:** 12, 11, 14, UPSTREAM_SYNC step 9
- **Files likely touched:** `opskit/lib/upgrade.sh`, `opskit/lib/flows_pieces.sh`, tests
- **Acceptance checks:** upgrade output ends with the exact list of follow-ups; piece re-install is idempotent.
- **Tests required:** bats with mocks; CI covers the real catalog.

### [ ] 6.10 — `opskit upgrade` end to end in selftest and CI
- **Goal:** `opskit selftest` gains an upgrade round: deploy the demo client on the previous tag (Q5), seed data, upgrade to the pinned tag (plan → stage → promote → smoke), then a second round with an injected smoke failure that must roll back; verify data and tag after each. Mandatory in CI.
- **Spec refs:** 17 Phase 6 accept
- **Files likely touched:** `opskit/lib/commands/selftest.sh`, `opskit/lib/roundtrip.sh`, `opskit/tests/selftest.bats`, CI timeout
- **Acceptance checks:** both rounds pass on CI; the old-tag stack never reaches the pinned tag in the failure round.
- **Tests required:** selftest + bats; CI timeout raised if needed (currently 40 min).

### [ ] 6.11 — Fork sync rehearsal
- **Goal:** rehearse `docs/UPSTREAM_SYNC.md` on a branch against the next real upstream tag (or a recent one if none is newer): merge, re-apply the patch ledger, delete upstream workflows, `check`, `selftest`, `upgrade` of the demo client; record every undocumented step and fix the procedure/scripts (e.g. a `opskit/bin/sync-check` that automates the verification list in step 7). The merge is not pushed to `main`.
- **Spec refs:** 12 (last paragraph), UPSTREAM_SYNC
- **Files likely touched:** `docs/UPSTREAM_SYNC.md`, `docs/UPSTREAM_CHANGES.md`, maybe `opskit/bin/sync-check`
- **Acceptance checks:** rehearsal log in PROGRESS lists the commands and timings; procedure has no step that needed guessing.
- **Tests required:** `fork.bats` still green; sync-check tested if added.
- **Needs the owner:** approval to fetch from `upstream` (fetch-only).

### [ ] 6.12 — Runbook, ADR-018 and phase close
- **Goal:** `docs/runbooks/upgrade-checklist.md` + `docs/runbooks/upgrade.md` (when to upgrade, plan → stage → promote, reading the output, what to tell the client, rollback, what to do if the alert says rollback happened), ADR-018, PROGRESS + phase verification report, go-to-market text (upgrades "staged with automatic rollback" is real only when 6.10 is green in CI).
- **Spec refs:** 12, 17
- **Files likely touched:** `docs/runbooks/`, `docs/DECISIONS.md`, `docs/PROGRESS.md`, `docs/go-to-market/*`
- **Acceptance checks:** owner can run a demo upgrade from the runbook alone.
- **Manual verification:** owner upgrades the Codespace demo client with the runbook.
