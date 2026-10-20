# Assumptions

Decisions the agent made where `docs/SPEC.md` was silent or ambiguous. The owner reviews these regularly.

| # | Date | Phase/Task | Spec section | Assumption | Approved? |
|---|---|---|---|---|---|
| 1 | 2026-10-20 | Setup | 17 (phases) | Owner check-ins happen only at the end of each phase or when blocked, not after each phase's task list | Yes (owner, 20 Oct 2026) |
| 2 | 2026-10-20 | Setup | Git rules | Work on `claude/funny-keller-x6sgy1`; owner merges each finished phase into `main` by PR, guided by plain-language steps from the agent | Yes (owner, 20 Oct 2026) |
| 3 | 2026-10-20 | Phase 0 (tooling) | 4, 16 | Dev-machine setup lives in tool-neutral `opskit/bin/dev-env` (tools + Docker daemon with proxy, stale pid cleanup); the Claude hook only calls it. Dev tooling, not product code | Yes (owner, 20 Oct 2026: "2. yes" + AI-neutral handoff request) |
| 4 | 2026-10-20 | Phase 0 (tooling) | 17 Phase 0 | `opskit/bin/explore-stack` scripts the Phase 0 install (copies upstream compose + official `tools/deploy.sh`, CE override) so any machine/AI recreates it in one command; explore tooling only | Yes (owner: Codespaces + AI-neutral handoff, 20 Oct 2026) |
| 5 | 2026-10-20 | 1.4 | 6, 15 | client.yaml details SPEC 6 leaves open: `image.repo` limited to the two official Activepieces repos; `host.ssh_user` may not be `root`; Slack holds `webhook_secret` (name of a host secret), never the URL; `report.day_of_month` 1–28; `quiet_hours` HH:MM; `host_id` key in host files; validator = ajv-cli (owner-approved) | Validator yes; rest pending owner review |
| 6 | 2026-10-20 | 1.10 | 14, ADR-013 | Piece package name `@opskit/piece-openai-compatible` (not `@activepieces/…`) so it can never clash with an official catalog piece; logo = Activepieces CDN OpenAI logo; `reasoning_effort` default `high` (highest broadly supported; `xhigh` offered for models that accept it); `bun.lock` workspace entry kept local, not committed (avoids an upstream edit) | Pending owner review |
| 7 | 2026-10-20 | 2.3 | 7, TECH_ARCH 6 | Rendered stack: DB/user `activepieces`; Redis limit 256m (TECH_ARCH said 128 MB — BullMQ inline payloads up to 512 KB make 128m risky); Postgres 1g; app/worker from client.yaml; json-file logs 10m×3 per container; shared `cache` named volume (upstream used a bind mount); `TZ` from client timezone; app joins external `opskit_edge` network as `<id>-app`, Postgres/Redis stay on the private network | Pending owner review |
