# Upstream sync (manual, only when the owner asks)

Runs on any Linux machine with the repo (Codespace, WSL, cloud AI session). Clients keep running official images; this only moves the fork's pin.

1. Read the release notes and `docs/install/reference/breaking-changes.mdx` for every version between the pinned tag (`docs/UPSTREAM_CHANGES.md`) and the target.
2. `git remote add upstream https://github.com/activepieces/activepieces.git` (once; fetch-only — never push to it; `git remote set-url --push upstream DISABLED`), then `git fetch upstream --tags` (about 15 s). Newest releases: `git tag -l '[0-9]*' --sort=-v:refname | head`. Sync to a **release tag only, never `upstream/main`**: release tags live on release branches, not on `main`.
3. `git switch main && git switch -c sync/<tag>`
4. `git merge <tag>` — resolve conflicts: upstream wins in upstream files; then re-apply every row of the patch ledger.
   Expected conflicts (rehearsal 22 Oct 2026, 512 upstream commits): our deleted workflows ("deleted in HEAD and modified in upstream") and upstream-deleted files → `git rm <file>`; version files that differ between release branch and `main` (`package.json`, `bun.lock`, `docker-compose.yml`, `deploy/activepieces-helm/Chart.yaml`, `brain/…`) → `git checkout --theirs -- <file> && git add <file>`. List them with `git diff --name-only --diff-filter=U`; nothing under `opskit/`, `docs/` or `packages/pieces/custom/` should conflict (if it does, stop and ask). Ledger rows:
   - #1 `.claude/settings.json`: `hooks.SessionStart` → `.claude/hooks/session-start.sh`
   - #2 `.claude/settings.json`: `ponytail@ponytail` and `craftspace@craftspace` = `false`, no `mcpServers`
   - #3 `.devcontainer/opskit/` is ours — check upstream didn't add a folder with that name
   Never touch `packages/ee/` or `packages/server/api/src/app/ee/`.
5. Upstream GitHub workflows (ledger #4): delete them again — `find .github/workflows -type f ! -name 'opskit-*' -print0 | xargs -0 git rm -q` — so only `opskit-*` workflows exist.
6. Update the pin table in `docs/UPSTREAM_CHANGES.md` (tag, SHA, date) and the image tag default in `opskit/schema/client.schema.json` fixtures if needed.
7. `opskit/bin/opskit sync-check --image <tag>`: re-verifies every upstream fact the kit depends on (flow run statuses, health route, worker poll line, deploy secrets, IPv6 listen, piece sync source and archive install, piece release bounds, Tables API, user identity table, connection encryption, migrations table, rollback tool, breaking-changes page, migration manifest in the image, ledger #1, #2, #4). Any `[fail]`: fix opskit and record the change in `docs/ASSUMPTIONS.md` before going on.
8. `opskit/bin/check` (includes the fork check against the new tag) and `opskit/bin/opskit selftest`. The selftest's upgrade rounds (`opskit/lib/e2e_upgrade.sh`) go from `E2E_UPGRADE_PROMOTE_FROM` and `E2E_UPGRADE_ROLLBACK_FROM` to the new pin: set the first to the old pin, the second to an older release with database migrations.
9. Upgrade a demo client to the new tag (`opskit upgrade demo --to <tag> --plan`, then `--yes`; `docs/runbooks/upgrade.md`); its follow-ups list says whether templates need re-pinning or the `openai-compatible` piece a re-install.
10. Push `sync/<tag>`; the owner merges it into `main` by PR. Update PROGRESS.

If anything fails: stay on the old tag and log it in PROGRESS "Known issues".
