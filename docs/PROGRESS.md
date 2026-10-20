# Progress

## Current status
- **Current phase:** Phase 2 — Client deployment kit
- **Current task:** 2.4 (see `docs/tasks/phase-2.md`)
- **Last updated:** 2026-10-20 · **Branch:** `claude/funny-keller-x6sgy1`

## Next steps
1. **Owner — CI (1.8):** GitHub Actions is off for the whole repo (opskit-ci registered, 0 runs). Decide: (a) delete upstream workflow files in the fork (ledger row, re-delete on sync; agent does it) then switch Actions on, or (b) switch Actions on and disable 41 upstream workflows one by one. Then confirm a green `opskit-ci` run.
2. **Owner — piece (1.12):** in the Codespace Activepieces, add an "OpenAI Compatible (BYOK)" step, create a connection with your Base URL + API key, pick a model, run once. Agent records the result.
3. Owner (20 Oct 2026): do items 1–2 together later; meanwhile Phase 2 (`docs/tasks/phase-2.md`).

## Phases
| Phase | Name | Status | Verified |
|---|---|---|---|
| 0 | Fork, set up & explore Activepieces | Done | Owner OK 20 Oct 2026 |
| 1 | Opskit foundation (+ openai-compatible piece) | Done except owner tests (CI 1.8, real-key 1.12) | — |
| 2 | Client deployment kit | In progress | — |
| 3 | Backups & restore | Not started | — |
| 4 | Monitoring & alerts | Not started | — |
| 4b | Go to market (owner-led) | Not started | — |
| 5 | Flow template library | Not started | — |
| 6 | Safe upgrades | Not started | — |
| 7 | Handover docs & care report | Not started | — |
| 8 | Custom pieces & own image | Moved to V2 (owner, 20 Oct 2026) | — |
| 9 | Field readiness | Not started | — |

## Task log
<!-- Newest first. For each task: date, task, files changed, how to verify manually, notes. -->
- **2026-10-20 — 2.3 render done.** Templates `compose.yml.tmpl`, `env.tmpl`, `caddy-site.tmpl`, `cron.tmpl` (+ practice-only `compose.practice.yml.tmpl`/`ipv4-shim.js`); `lib/stack.sh` `stack_render`; `opskit render <id>` → `clients/<id>/rendered/` (dir 700, .env 600). 13 tests (pinned tag, CE, telemetry off, worker URL, replicas/limits, no ports/container_name, volumes, edge network, healthchecks, no secrets outside .env, `docker compose config`). Verify: see `opskit/tests/render_client.bats`.
- **2026-10-20 — 2.2 secrets done.** `lib/secrets.sh`: `secrets_ensure` generates `AP_API_KEY` (hex 64), `AP_POSTGRES_PASSWORD`/`AP_JWT_SECRET` (hex 32), `AP_ENCRYPTION_KEY` (hex 16 = 32 chars, as upstream requires) once into `clients/<id>/secrets.env` (600); aborts on empty/malformed output; never regenerates (damaged file → restore from escrow); `secrets_export`. 7 tests. Also: `opskit validate` now runs npx from a temp dir (inside the installed monorepo npx scanned all workspaces: 24 s → 0.9 s).
- **2026-10-20 — 2.1 registry + client new done.** `lib/registry.sh` (paths, `yaml_get/set`, validated `require_client/host`, `client_history_add`; `OPSKIT_REGISTRY` override), `templates/client.yaml.tmpl`, `opskit client new <id> --domain --host --contact [--name --timezone]` (draft, dir 700, pinned tag, history). Host schema: `transport ssh|local`, `opskit_root`, `edge` ports/TLS, `practice_quirks`; client schema: `history`, `offboarded_at`, backup remote optional until Phase 3. 3 tests.
- **2026-10-20 — 1.10–1.12 openai-compatible piece.** `packages/pieces/custom/openai-compatible` (`@opskit/piece-openai-compatible` 0.1.0): connection Base URL + optional key (validate = GET /models), Ask Model (live model dropdown, `reasoning_effort` default high, token-limit param choice, extra JSON), List Models, Custom API Call. 21 vitest tests, strict tsc build, eslint clean. Archive (96 KB, self-contained) built with the upstream CLI and installed on the Codespace CE via `POST /api/v1/pieces`; keyless OpenRouter connection validated, dropdown listed 468 live models in ~1 s, keyless run failed with the clear 401 message. `bun.lock` changes from the local install are not committed (upstream file). How-to: piece README.
- **2026-10-20 — 1.9 fork hygiene done.** `lib/fork.sh` `fork_check`: vs the pinned tag, new files must match our path patterns and changed/deleted upstream files must be in the patch ledger; part of `opskit/bin/check` (warns + skips if the tag isn't fetched). `docs/UPSTREAM_SYNC.md` rewritten (ledger re-apply, workflow disabling, Phase 0 facts to re-verify). 6 tests on a throwaway git repo.
- **2026-10-20 — 1.8 CI file pushed.** `.github/workflows/opskit-ci.yml` (dev-env → doctor → check, on our paths). Not yet seen running — see Known issues.
- **2026-10-20 — 1.7 doctor done.** `opskit doctor [--offline]`: OS/WSL, Docker daemon + Compose ≥ v2, 13 tools + mikefarah yq v4 (fail), egress to cloud.activepieces.com / npm / GHCR (warn). Found + fixed: no ssh client in cloud session → `dev-env` now also installs openssh-client, nodejs/npm, curl, git, openssl; Codespace config gains the Node 22 feature. 6 tests with stubbed PATH. Verify: `opskit/bin/opskit doctor`.
- **2026-10-20 — 1.6 ssh done.** `lib/ssh.sh`: `ssh_run <user> <host> <port> <cmd...>` (args `%q`-quoted) and `scp_put`; BatchMode, accept-new, no password/keyboard auth, ConnectTimeout 10, keepalives, optional `OPSKIT_KNOWN_HOSTS`; target validation before any call. 6 tests with stub ssh/scp.
- **2026-10-20 — 1.4 schemas + validate done.** `opskit/schema/{client,host}.schema.json`, `lib/schema.sh` (pinned `ajv-cli@5.0.0` + `ajv-formats@3.0.1` via npx, YAML→JSON with yq v4, errors as `[fail] field: problem`), `opskit validate <file> [--type]`. `dev-env` installs mikefarah yq v4.44.3 (sha256-verified). Fixtures in `opskit/tests/fixtures/`. 14 new tests. Verify: `opskit/bin/opskit validate opskit/tests/fixtures/clients/valid.yaml`.
- **2026-10-20 — 1.5 render done.** `lib/render.sh` `render_template <tmpl> <out>`: substitutes only `${NAME}` refs, fails listing unresolved/empty names (never values), atomic write. `dev-env` now installs `envsubst` (gettext-base). 4 new tests. Templates must not rely on compose-time `${...}` interpolation — values are rendered in.
- **2026-10-20 — 1.3 confirm/validate done.** `lib/confirm.sh` (`confirm_destructive <id> <yes> <action>`: needs `--yes` and the id typed on stdin), `lib/validate.sh` (`is_slug`, `is_domain`, `is_email`, `is_port`, `is_positive_int`). 8 new tests. Verify: `bats opskit/tests/confirm_validate.bats`.
- **2026-10-20 — 1.2 check done.** `opskit/bin/check [--quick]`: shellcheck on all opskit Bash files + `.claude/hooks`, then `bats --recursive opskit/tests` (`--quick` filters `# bats test_tags=docker`). `OPSKIT_CHECK_ROOT` lets tests run it on a fixture tree. 21 tests pass. Verify: `opskit/bin/check`.
- **2026-10-20 — 1.1 skeleton done.** `opskit/bin/opskit` (commands in `opskit/lib/commands/*.sh`, `# summary:` line + `cmd_main`), `lib/log.sh`, `version` command, `opskit/VERSION`, `opskit/.gitignore` (`/clients/`, `/hosts/`, logs — our file, root `.gitignore` untouched), `opskit/.shellcheckrc`, bats tests (10 pass). Verify: `opskit/bin/opskit --help`, `bats opskit/tests`.
- **2026-10-20 — Phase 1 started.** Owner closed Phase 0 and requested an OpenAI-compatible BYOK piece (ADR-013). Task file `docs/tasks/phase-1.md` (12 tasks).
- **2026-10-20 — Phase 0 flows in Codespace.** Codespace `verbose-trout` up via `.devcontainer/opskit` (771 pieces, 420 templates). Built + ran lead-capture (webhook/code/router/HTTP/failing branch) and invoice-reminder (schedule/loop/delay) via API; export/import round trip; 20 concurrent runs all succeeded (≈0.3 s each); screenshots in `docs/phase0-screenshots/`, flow generators in `docs/phase0-flows/`. Report updated. Verify: open the Codespace URL, Runs page shows 22 SUCCEEDED + 1 FAILED.
- **2026-10-20 — Codespaces + one-command explore stack.** Added `.devcontainer/opskit/devcontainer.json` (ledger #3) and `opskit/bin/explore-stack` (up/status/stop; Codespaces URL aware). Verified: shellcheck clean; fresh-path test created a new stack from scratch, healthy in 10 s (GHCR pull works now); existing stack re-run keeps data; devcontainer parsed by `@devcontainers/cli read-configuration`. **Not verified:** a real Codespace build (owner to open one). Laptop requirements in `docs/HANDOFF.md`.
- **2026-10-20 — Phase 0: backup→restore + idle stats.** Restore into fresh stack works (admin/projects/worker); idle ≈ 760 MiB; `flow_run` checked live (read-only). Files: `docs/EXPLORATION_REPORT.md`. Still blocked on container internet for pieces.
- **2026-10-20 — Owner plan decisions applied.** Owner approved R1–R5 and A1–A5 (C1–C6 already accepted). Files: `docs/SPEC.md` (+ Appendix C), `docs/DECISIONS.md` (ADR-012; ADR-006 superseded, ADR-001 image part superseded), `docs/TECH_ARCHITECTURE.md`, `docs/USER_FLOWS.md`, `docs/ENVIRONMENT.md`, `.claude/CLAUDE.md`, `.claude/settings.json` (ledger #2, A3), `README-START-HERE.md`, `opskit/CLAUDE.md`, two opskit skills. Verify: ledger #2 `jq -e` test passes. Owner allowed `cloud.activepieces.com` + `pkg-containers.githubusercontent.com` (host reachable now).
- **2026-10-20 — Phase 0 explore (partial).** CE 0.92.3 running in `explore/stack` (project `ap0`): health OK, worker registered, admin created, CE feature matrix recorded. Files: `docs/EXPLORATION_REPORT.md`. Blocked, see Known issues. Next: once unblocked, build flows, run 20 test runs + `docker stats`, backup→restore, hello-world piece, then finish the report.
- **2026-10-20 — Setup pushed; owner decisions recorded.** Branch `claude/funny-keller-x6sgy1` pushed to origin (GitHub App now installed). Owner decisions: (1) agent stops only at the end of each phase or when blocked; (2) work stays on `claude/funny-keller-x6sgy1`, owner merges finished phases to `main` by PR. The agent gives plain-language, numbered steps whenever the owner has to do something in GitHub. Plan-review picks C1–C6 accepted (no objection); R1–R5 and A1–A5 approved later the same day (see next entry).

## Known issues
<!-- Bugs or gaps found outside current task scope. -->
- Codespace `verbose-trout` (4-core) runs the explore stack; an older broken codespace `symmetrical-fishstick` should be deleted by the owner. devcontainer memory requirement lowered 8gb→4gb so 2-core machines are offered (8gb excluded them).
- ~~BLOCKER (cloud session network)~~ resolved 20 Oct 2026: owner allowed `cloud.activepieces.com` + `pkg-containers.githubusercontent.com`.
- **BLOCKER (containers have no internet):** in the cloud session, Docker containers can't resolve or reach the internet (only the host goes through the agent proxy), so the app still can't sync pieces. Giving containers proxy access was denied by the session safety check; needs owner permission.
- **BLOCKER (session permissions):** auto-mode safety classifier denied `docker` commands and a container→proxy relay. Owner decides whether to allow Docker commands.
- **GitHub Actions disabled repo-wide:** `opskit-ci` is registered but never runs; 41 upstream workflows also registered (they'd fire on PRs/pushes to main once Actions is on). Owner decision pending (Next steps 1).
- Full `bun install` fails: a community piece depends on a GitHub tarball (`dust-tt/typescript-sdk`) blocked by the cloud session network policy (403). Filtered installs work.
- ~~Session hook starts dockerd without proxy~~ fixed 20 Oct 2026 (`opskit/bin/dev-env`).
- Cloud session's `yq` reports `0.0.0` (apt package, likely not mikefarah yq v4 that templates expect) → Phase 1 `doctor` must check the yq flavor/version.
- Upstream `main.ts` listens on `::` only; crash-loops on IPv6-less kernels (cloud sandbox). Explore-only shim in `explore/stack`; real hosts unaffected.

## Phase verification reports
<!-- Output of /opskit-verify-phase goes here. -->
