# Start here — Automation Ops Kit (Factory Droid version)

This package is added **on top of your fork** of Activepieces. It never overwrites Activepieces' own files (their `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `README.md`, `docs/` stay as they are). Nothing updates from upstream automatically.

All commands run in **WSL2 Ubuntu** (not PowerShell). Open the repo in VS Code via Remote-WSL and run `droid` inside WSL.

1. On GitHub, fork https://github.com/activepieces/activepieces into your account. In the fork: Settings → Actions → disable workflows (upstream CI isn't ours).
2. In WSL: `mkdir -p ~/work && cd ~/work`
3. `git clone https://github.com/<you>/activepieces.git activepieces-ops && cd activepieces-ops`
4. `git remote add upstream https://github.com/activepieces/activepieces.git`
5. `git remote set-url --push upstream DISABLED`
6. Check none of these exist yet: `.factory`, `opskit`, `explore`, `packages/pieces/custom`, and in `docs/`: `SPEC.md`, `DECISIONS.md`, `TECH_ARCHITECTURE.md`, `USER_FLOWS.md`, `ENVIRONMENT.md`, `RESEARCH.md`, `PROGRESS.md`, `ASSUMPTIONS.md`, `UPSTREAM_CHANGES.md`, `UPSTREAM_SYNC.md`, `EXPLORATION_REPORT.md`, `docs/tasks`. If any exists, stop and tell Droid.
7. Unzip this package into the repo root (don't replace existing files).
8. `git add -A && git commit -m "docs(opskit): add specs and droid rules"`
9. In Droid: `/explore` (a project skill) → Phase 0: pin to the latest release, install Activepieces CE locally the official way, explore it as it is, build the starter flows by hand, fill `docs/EXPLORATION_REPORT.md`.
10. Droid continues with `/start-phase` for Phase 1 (the 8 agreed improvements follow in Phases 1–9). It asks you only if something is blocked or unclear.
11. Repeat `/next-task`; end of phase: `/verify-phase` then `/security-review`. New session: `/resume`.

Community Edition only — never set `AP_EDITION=ee` or use anything in `packages/ee/`.
