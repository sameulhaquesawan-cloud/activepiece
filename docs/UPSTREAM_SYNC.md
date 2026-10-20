# Upstream sync (manual, only when the owner asks)

Runs on any Linux machine with the repo (Codespace, WSL, cloud AI session). Clients keep running official images; this only moves the fork's pin.

1. Read the release notes and `docs/install/reference/breaking-changes.mdx` for every version between the pinned tag (`docs/UPSTREAM_CHANGES.md`) and the target.
2. `git remote add upstream https://github.com/activepieces/activepieces.git` (once; fetch-only — never push to it), then `git fetch upstream --tags`.
3. `git switch main && git switch -c sync/<tag>`
4. `git merge <tag>` — resolve conflicts: upstream wins in upstream files; then re-apply every row of the patch ledger:
   - #1 `.claude/settings.json`: `hooks.SessionStart` → `.claude/hooks/session-start.sh`
   - #2 `.claude/settings.json`: `ponytail@ponytail` and `craftspace@craftspace` = `false`, no `mcpServers`
   - #3 `.devcontainer/opskit/` is ours — check upstream didn't add a folder with that name
   Never touch `packages/ee/` or `packages/server/api/src/app/ee/`.
5. New upstream GitHub workflows: list `.github/workflows/` changes (`git diff --name-status <old tag> <tag> -- .github/workflows`) and keep them disabled in the fork (Actions tab → workflow → ⋯ → Disable workflow).
6. Update the pin table in `docs/UPSTREAM_CHANGES.md` (tag, SHA, date) and the image tag default in `opskit/schema/client.schema.json` fixtures if needed.
7. Re-verify the Phase 0 facts the kit depends on and record changes in `docs/ASSUMPTIONS.md`: `flow_run` columns/statuses (`FAILED_STATES`), health endpoint, worker registration, the 4 secrets in `tools/deploy.sh`, IPv6 listen address, piece sync source, `POST /api/v1/pieces` (archive install for `openai-compatible`).
8. `opskit/bin/check` (includes the fork check against the new tag) and, from Phase 2, `opskit/bin/opskit selftest`.
9. Upgrade a demo client on the new tag (`opskit upgrade demo --to <tag>`, Phase 6); re-install and smoke-test the `openai-compatible` piece.
10. Push `sync/<tag>`; the owner merges it into `main` by PR. Update PROGRESS.

If anything fails: stay on the old tag and log it in PROGRESS "Known issues".
