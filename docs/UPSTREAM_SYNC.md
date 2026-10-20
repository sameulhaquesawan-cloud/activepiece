# Upstream sync (manual, optional) — run in WSL

1. Read release notes + breaking changes for every version between the pinned tag and the target.
2. `git fetch upstream --tags`
3. `git switch main` then `git switch -c sync/<tag>`
4. `git merge <tag>` — resolve conflicts: upstream wins in upstream files; re-apply ledger patches; never touch `packages/ee`.
5. Re-verify Phase 0 *(verify)* facts that the kit depends on (run tables, env vars, piece loading) and update ADRs/ASSUMPTIONS.
6. `opskit/bin/check`, `opskit/bin/opskit selftest`; push branch → CI builds a test image.
7. Test the image on a staging demo client (`opskit upgrade demo --to <tag>`).
8. Merge to `main`, tag image `<tag>-ops.<n>`, update `docs/UPSTREAM_CHANGES.md` and PROGRESS.
If anything fails: stay on the old tag, log in PROGRESS "Known issues".
