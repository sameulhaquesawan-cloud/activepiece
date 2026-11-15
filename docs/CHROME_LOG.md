# Chrome log — tasks for the local browser session

Two sessions share the branch named in `docs/PROGRESS.md`:
- **Cloud session**: code, Bash, Docker, tests. Writes tasks here, owns every other file.
- **Local session** (owner's Windows laptop, Claude in Chrome): browser work only. Writes **only this file**.

## Protocol
1. Before work: `git pull`. After work: commit only this file, `git pull --rebase`, `git push`.
2. Cloud adds a task under **Open tasks** (`### T<n> — title`, steps, report format).
3. Local does it in Chrome, moves it to **Done** with a report: what was done, results, problems, screenshots described in words.
4. **Never write secrets here** (passwords, API keys, tokens, private keys, `.env` values). Write `[stored by owner]` instead. IPs, hostnames, record names and error text are fine.
5. Stop and ask the owner before anything destructive, paid, or that changes a live client system.

## Open tasks

## Done

### T0 — Round-trip test
- **Date:** 2026-11-15
- **Machine:** owner's Windows laptop, Microsoft Windows 10 Pro 10.0.19045
- **Claude in Chrome connected:** yes. Checked by opening a new tab in its own tab group, going to https://github.com/sameulhaquesawan-cloud/activepiece and reading the page title: "sameulhaquesawan-cloud/activepiece". The GitHub header showed a signed-in user avatar. Tab closed afterwards; no other tabs touched.
- **`git --version`:** `git version 2.47.0.windows.1`
- **Clone:** `%USERPROFILE%\Documents\activepiece`, branch `claude/ecstatic-keller-dxgivp`
- **Problems:** none.
