# Assumptions

Decisions the agent made where `docs/SPEC.md` was silent or ambiguous. The owner reviews these regularly.

| # | Date | Phase/Task | Spec section | Assumption | Approved? |
|---|---|---|---|---|---|
| 1 | 2026-10-20 | Setup | 17 (phases) | Owner check-ins happen only at the end of each phase or when blocked, not after each phase's task list | Yes (owner, 20 Oct 2026) |
| 2 | 2026-10-20 | Setup | Git rules | Work on `claude/funny-keller-x6sgy1`; owner merges each finished phase into `main` by PR, guided by plain-language steps from the agent | Yes (owner, 20 Oct 2026) |
| 3 | 2026-10-20 | Phase 0 (tooling) | 4, 16 | Dev-machine setup lives in tool-neutral `opskit/bin/dev-env` (tools + Docker daemon with proxy, stale pid cleanup); the Claude hook only calls it. Dev tooling, not product code | Yes (owner, 20 Oct 2026: "2. yes" + AI-neutral handoff request) |
