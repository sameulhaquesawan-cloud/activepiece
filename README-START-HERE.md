# Start here — Automation Ops Kit (Claude Code version)

This repo = Activepieces Community Edition (upstream, pinned release, see `docs/UPSTREAM_CHANGES.md`) + our ops kit (`opskit/`, `docs/`, `packages/pieces/custom/`). Upstream files stay unchanged except entries in the patch ledger. Nothing updates from upstream automatically.

## New session or another AI?
Read **`docs/HANDOFF.md`** first: a copy-paste prompt, reading order, machine setup (`opskit/bin/dev-env`) and how to continue. Nothing requires Claude.

## How work happens
- **Cloud (default):** open the repo in a Claude Code session at claude.ai/code. `.claude/hooks/session-start.sh` runs `opskit/bin/dev-env` (installs shellcheck/bats/rclone/age, starts Docker). Claude works on its `claude/...` branch; you merge finished phases into `main` by pull request.
- **Laptop (optional):** WSL2 Ubuntu + Docker Desktop, repo cloned inside WSL, any AI tool. Run `opskit/bin/dev-env`. Same commands.

## Commands (slash skills in `.agents/skills/opskit-*`)
| Command | What it does |
|---|---|
| `/opskit-explore` | Phase 0: install Activepieces CE as it is, explore, fill `docs/EXPLORATION_REPORT.md` |
| `/opskit-start-phase` | Break the next phase into tasks (`docs/tasks/phase-N.md`) |
| `/opskit-next-task` | Do the next task, test, commit |
| `/opskit-verify-phase` | Check the phase against its acceptance criteria |
| `/opskit-security-review` | Security pass over the phase's changes |
| `/opskit-fix-bug` | Reproduce → root cause → fix with a test |
| `/opskit-resume` | Rebuild context in a new session |

## Rules in one breath
Source of truth: `docs/SPEC.md`. Agent rules: `.claude/CLAUDE.md`. Community Edition only — never set `AP_EDITION=ee` or use anything in `packages/ee/` or `packages/server/api/src/app/ee/`. No secrets in git. Upstream remote is fetch-only; upstream GitHub workflow files are deleted from the fork (only `opskit-*` workflows run).
