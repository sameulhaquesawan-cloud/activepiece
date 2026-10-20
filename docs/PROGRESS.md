# Progress

## Current status
- **Current phase:** Phase 0 — Fork, set up & explore Activepieces
- **Current task:** `/opskit-explore` (install & explore CE 0.92.3)
- **Last updated:** 2026-10-20 · **Branch:** `claude/funny-keller-x6sgy1`

## Next steps
1. **Owner decision pending:** how to finish Phase 0 flow-building, since containers in the Claude cloud session have no internet (relay denied twice by the session safety check). Options: (a) GitHub Codespaces with a light opskit devcontainer (owner sees the UI in the browser; recommended), (b) owner's laptop (WSL2 + Docker Desktop).
2. Then on that machine: recreate the explore stack (`docs/HANDOFF.md`), confirm pieces load, build 1–2 starter flows (webhook + schedule; branches, loop, delay, code, HTTP; AI step with Gemini free key, practice data), run logs/retries/failure display, flow import/export, templates, 20 test runs + `docker stats`, stored-connection decrypt after restore, hello-world piece in dev mode.
3. Finish `docs/EXPLORATION_REPORT.md`, mark Phase 0 done, run `/opskit-start-phase` (or follow `.agents/skills/opskit-start-phase/SKILL.md`) for Phase 1.

## Phases
| Phase | Name | Status | Verified |
|---|---|---|---|
| 0 | Fork, set up & explore Activepieces | In progress (blocked) | — |
| 1 | Opskit foundation | Not started | — |
| 2 | Client deployment kit | Not started | — |
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
- **2026-10-20 — Phase 0: backup→restore + idle stats.** Restore into fresh stack works (admin/projects/worker); idle ≈ 760 MiB; `flow_run` checked live (read-only). Files: `docs/EXPLORATION_REPORT.md`. Still blocked on container internet for pieces.
- **2026-10-20 — Owner plan decisions applied.** Owner approved R1–R5 and A1–A5 (C1–C6 already accepted). Files: `docs/SPEC.md` (+ Appendix C), `docs/DECISIONS.md` (ADR-012; ADR-006 superseded, ADR-001 image part superseded), `docs/TECH_ARCHITECTURE.md`, `docs/USER_FLOWS.md`, `docs/ENVIRONMENT.md`, `.claude/CLAUDE.md`, `.claude/settings.json` (ledger #2, A3), `README-START-HERE.md`, `opskit/CLAUDE.md`, two opskit skills. Verify: ledger #2 `jq -e` test passes. Owner allowed `cloud.activepieces.com` + `pkg-containers.githubusercontent.com` (host reachable now).
- **2026-10-20 — Phase 0 explore (partial).** CE 0.92.3 running in `explore/stack` (project `ap0`): health OK, worker registered, admin created, CE feature matrix recorded. Files: `docs/EXPLORATION_REPORT.md`. Blocked, see Known issues. Next: once unblocked, build flows, run 20 test runs + `docker stats`, backup→restore, hello-world piece, then finish the report.
- **2026-10-20 — Setup pushed; owner decisions recorded.** Branch `claude/funny-keller-x6sgy1` pushed to origin (GitHub App now installed). Owner decisions: (1) agent stops only at the end of each phase or when blocked; (2) work stays on `claude/funny-keller-x6sgy1`, owner merges finished phases to `main` by PR. The agent gives plain-language, numbered steps whenever the owner has to do something in GitHub. Plan-review picks C1–C6 accepted (no objection); R1–R5 and A1–A5 approved later the same day (see next entry).

## Known issues
<!-- Bugs or gaps found outside current task scope. -->
- ~~BLOCKER (cloud session network)~~ resolved 20 Oct 2026: owner allowed `cloud.activepieces.com` + `pkg-containers.githubusercontent.com`.
- **BLOCKER (containers have no internet):** in the cloud session, Docker containers can't resolve or reach the internet (only the host goes through the agent proxy), so the app still can't sync pieces. Giving containers proxy access was denied by the session safety check; needs owner permission.
- **BLOCKER (session permissions):** auto-mode safety classifier denied `docker` commands and a container→proxy relay. Owner decides whether to allow Docker commands.
- `.claude/hooks/session-start.sh` starts `dockerd` without proxy env, so image pulls fail. Fix: pass `HTTPS_PROXY`/`NO_PROXY` to dockerd (`.claude/` edit → needs approval).
- Upstream `main.ts` listens on `::` only; crash-loops on IPv6-less kernels (cloud sandbox). Explore-only shim in `explore/stack`; real hosts unaffected.

## Phase verification reports
<!-- Output of /opskit-verify-phase goes here. -->
