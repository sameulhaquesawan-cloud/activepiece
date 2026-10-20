# Operator Flows — Automation Ops Kit

> Derived from `docs/SPEC.md`. ⭐ = must be covered by `selftest` or an integration test.

### O1. Explore (Phase 0) ⭐
Fork → clone in WSL → pin tag → official CE install → worker fix → explore builder, webhooks (ngrok), schedules, logic, AI step, logs, import/export, CE admin → build 6 starters → local backup/restore → report.

### O2. Onboard a client (dedicated host) ⭐
`client new acme` → edit `client.yaml` → `host bootstrap acme-vps` → `render acme` → `deploy acme` → import templates → connect client-owned accounts → test checklist → `docs acme` → go live.
Edge: DNS not propagated (HTTPS fails → retry guidance) · port 80 blocked · worker not registered (worker URL check).

### O3. Onboard onto a shared host ⭐
Same, `host.mode: shared`; ports/routes auto-allocated; `host capacity` must pass.

### O4. Nightly backup + monthly restore test ⭐
Cron backup → off-server copy → heartbeat; monthly restore into temp stack → smoke → report line.
Edge: remote unreachable (alert, keep local) · disk full (alert, prune).

### O5. Failure alert at night ⭐
Flow fails → detector (≤ 5 min) → ops-hub → owner Telegram + client channels (quiet hours respected for non-critical) → owner fixes → resolved note.

### O6. Upgrade a client ⭐
Sync fork to new release → CI image → `upgrade acme --to <tag>` → staging smoke → prod → smoke → report entry; rollback path.

### O7. Monthly care report
Day 1 → `report acme --month` (or scheduled) → ops-hub emails client → owner invoices.

### O8. Custom piece
Create in `packages/pieces/custom/` → tests → CI image → deploy → use in client flow.

### O9. Offboard
Final backup → export flows + docs → stop stack → delete after retention with approval.
