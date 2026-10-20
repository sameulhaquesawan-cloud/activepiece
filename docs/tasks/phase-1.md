# Phase 1 — Opskit foundation (+ owner request: OpenAI-compatible BYOK piece)

SPEC: Section 17 Phase 1, Sections 3, 6, 15, 16; owner request 20 Oct 2026 (ADR-013).
Owner check-ins: only at phase end or when blocked (ASSUMPTIONS #1).

## Open questions for the owner
- **Q1 (blocks 1.4):** JSON-schema validator for `client.yaml` / `hosts/*.yaml`. Recommended: `ajv-cli` pinned via `npx` on the operator machine (Node is already needed for pieces; nothing on hosts). Alternative: `check-jsonschema` (Python). New dependency → owner approval.
- **Q2 (1.7):** `opskit doctor` needs mikefarah `yq` v4; the apt package in the cloud session reports `0.0.0`. Plan: `dev-env` installs the pinned v4 binary from GitHub releases (verify download host is allowed).

## Tasks

### [x] 1.1 — Skeleton, dispatcher, logging
- **Goal:** `opskit/` layout per TECH_ARCHITECTURE §3; `bin/opskit` dispatcher (`--help`, unknown command → exit 1); `lib/log.sh` (`[ok]`/`[warn]`/`[fail]`, die); `.gitignore` for `opskit/clients/`, `opskit/hosts/`, logs.
- **Spec refs:** 3.1, 3.10; TECH_ARCHITECTURE §3–4
- **Files:** `opskit/bin/opskit`, `opskit/lib/log.sh`, `opskit/tests/*.bats`, `.gitignore` (our block), nested `CLAUDE.md`
- **Acceptance:** `opskit --help` lists commands; unknown command exits 1 with `[fail]`; ignored paths really ignored (`git check-ignore`).
- **Tests:** bats for dispatcher help/unknown/exit codes and log helpers.

### [x] 1.2 — `opskit/bin/check` (+ `--quick`)
- **Goal:** shellcheck every opskit Bash file + run bats; `--quick` skips Docker-tagged tests; non-zero on any failure.
- **Files:** `opskit/bin/check`, `opskit/tests/check.bats`
- **Acceptance:** passes on clean tree; a deliberately broken fixture script makes it fail.
- **Tests:** bats with a temp fixture tree.

### [x] 1.3 — `lib/confirm.sh` + `lib/validate.sh` basics
- **Goal:** destructive-confirm helper (`--yes` + typed client id); validators for slug, domain, email, port, positive int.
- **Spec refs:** 3.8; rules "Client safety"
- **Tests:** bats: wrong typed id aborts, `--yes` alone isn't enough for destructive, validators accept/reject fixtures.

### [ ] 1.4 — Schemas + `opskit validate` *(blocked on Q1)*
- **Goal:** `opskit/schema/client.schema.json` (SPEC 6 fields; Phase 0 values: `AP_EDITION` fixed `ce`, worker replicas default 1, alert channels telegram/email/slack) and `host.schema.json`; `opskit validate <file>` prints field-level messages.
- **Tests:** valid + ≥ 6 invalid fixtures (missing field, bad slug, bad domain, unknown channel, replicas 0, bad mode) each with the expected message.

### [ ] 1.5 — `lib/render.sh`
- **Goal:** envsubst/yq render helper that fails on any unresolved `${...}` and never prints secret values.
- **Tests:** bats: complete vars render; missing var fails naming the variable (not its value).

### [ ] 1.6 — `lib/ssh.sh`
- **Goal:** `ssh_run`/`scp_put` wrappers: BatchMode, `StrictHostKeyChecking=accept-new`, ConnectTimeout, ServerAlive, key-only.
- **Tests:** bats with a stub `ssh`/`scp` on PATH asserting the exact options.

### [ ] 1.7 — `opskit doctor`
- **Goal:** checks OS (Linux/WSL), Docker + Compose v2, tools (shellcheck, bats, jq, yq v4 flavor, age, rclone, curl, openssl, envsubst, ssh), egress to `cloud.activepieces.com` + `registry.npmjs.org` + image registry; `[ok]/[warn]/[fail]` per line.
- **Tests:** bats with PATH stubs for present/missing/wrong-yq.

### [ ] 1.8 — CI `opskit-ci.yml`
- **Goal:** GitHub Actions: shellcheck + bats on push/PR touching our paths. Owner disables upstream workflows (step-by-step in PROGRESS).
- **Acceptance:** green run on the branch.

### [ ] 1.9 — Fork hygiene check + docs
- **Goal:** `opskit/bin/check` includes "only our paths changed vs pinned tag" (allow-list from SPEC 3.1 + ledger rows); `docs/UPSTREAM_SYNC.md` completed.
- **Acceptance:** `git diff 0.92.3 --stat` shows only our paths + ledger files; check fails on an unledgered upstream edit (fixture).

### [ ] 1.10 — Piece: `openai-compatible` scaffold + auth (owner request)
- **Goal:** `packages/pieces/custom/openai-compatible` via upstream piece CLI/conventions; auth = Base URL + API key (+ optional extra header name); auth `validate` calls `GET {baseUrl}/models`.
- **Spec refs:** ADR-013; `packages/pieces/CLAUDE.md`
- **Tests:** vitest: URL normalisation, validate success/401/unreachable (HTTP mocked).

### [ ] 1.11 — Piece actions: Ask model (live model dropdown, reasoning default high)
- **Goal:** action "Ask model" (chat/completions): model dropdown loaded live from `{baseUrl}/models` on open/refresh; reasoning effort dropdown defaulting to `high` (+ `minimal/low/medium`, "don't send" for endpoints that reject it, optional custom value); system prompt, prompt, max output tokens (blank = model max), temperature. "List models" action too.
- **Tests:** vitest: dropdown options from mocked `/models`, request body carries `reasoning_effort` by default and omits it on "don't send", error mapping.

### [ ] 1.12 — Ship the piece into CE without an own image
- **Goal:** build → package archive → install via CE admin `POST /api/v1/pieces` (`packageType: ARCHIVE`) on the Codespace; flow test against a real endpoint with the owner's key (owner enters the key in the connection, not in git).
- **Acceptance:** piece visible in the builder; model dropdown lists live models; run succeeds with reasoning `high`; documented in `packages/pieces/custom/openai-compatible/README.md`.
