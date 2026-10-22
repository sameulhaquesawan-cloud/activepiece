# Phase 7 — Handover docs & care report (Improvements 6, 7)

SPEC: Section 13 (`opskit docs`, `opskit report`), 5 (actors), 6 (`report`, `support` fields), 15 (read-only role, no personal data), 17 Phase 7; Appendix C A4 (privacy note), A5 (Zapier checklist); existing material in `docs/go-to-market/` (`zapier-migration-checklist.md`, `eu/privacy-notice.md`, `eu/subprocessors.md`, `offer.md`).
**Accept (SPEC 17):** report numbers for a demo month match fixture DB counts exactly; generated handover docs list every active flow with pause instructions; report email is delivered to a test inbox; handover docs include the privacy note and Zapier checklist.
**Rule from `.claude/CLAUDE.md`:** reports read client data, so this plan waits for the owner's "ok" before code.

## Open questions for the owner (recommended defaults in brackets — "ok" accepts them)
**Answered 22 Oct 2026:** owner said "ok, go with your recommendations" — all seven defaults accepted, plan approved.
- **Q1 — How is the report sent?** SPEC 13 says "emailed by an owner-side cron", the phase line also names a `monthly-report-sender` flow. [`opskit report --all --send` on your machine (by hand on the 1st, or a cron line on an always-on WSL/Codespace), through your SMTP account with `curl` exactly like alerts — no msmtp, no Activepieces flow (that would need the ops-hub we ruled out, ADR-012). Each month is sent once; re-running says "already sent".]
- **Q2 — What format?** [One HTML email with inline styles that also prints cleanly to PDF from any browser; the same file is kept in `opskit/clients/<id>/reports/YYYY-MM.html`. No PDF tool to install.]
- **Q3 — "Hours used vs included": where do hours come from?** [You log work as you go: `opskit hours <id> add 1.5 "changed the invoice flow"`. Included hours per client in `client.yaml` (`support.included_hours`: Care 1, Care Plus 3). Unused hours do not roll over (as in the offer).]
- **Q4 — What counts as an incident?** [Counted automatically: Uptime Kuma down periods, nights without a complete backup, upgrade rollbacks. Plus anything you log: `opskit incident <id> add "…"`. Failed flow runs are reported per flow, not as incidents (they are usually the client's data).]
- **Q5 — Which flows are "active" in the handover pack?** [Read from the client's own database with the read-only role: every switched-on flow by name, with its trigger type. If it came from our library, the template's description and "how it works" are added. You can add one sentence per flow in `opskit/clients/<id>/notes.yaml`. No run data, no personal data.]
- **Q6 — Language and branding?** [English only for now; your business name, website and support email come from a small `opskit/owner/business.yaml` (placeholder "YourBrand" until you choose, Appendix B Q1). Never the Activepieces logo.]
- **Q7 — How much detail goes to the client?** [Totals only: runs, succeeded, failed per flow; uptime %; backups; upgrades; incidents; hours. No error texts, no customer data from runs.]

## Tasks

### [x] 7.1 — Verify report facts (no code)
- **Goal:** On the pinned version: columns and statuses for per-flow monthly counts (`flow_run.created`/`finishTime`, `environment = PRODUCTION`, `flowId` → `flow_version.displayName`, statuses), month boundaries in the client's time zone, `flow.status = ENABLED` + trigger type from the published version, what the read-only role can read (no connections), Uptime Kuma 2.5.5: how to get exact monthly uptime (socket `getMonitorBeats` / `getMonitorChartData`, or its `stat_daily` table) and how long it keeps data; what backups/restore tests/history already record.
- **Spec refs:** 13, 15, 0 (never invent tables)
- **Files likely touched:** `docs/ASSUMPTIONS.md`, `docs/EXPLORATION_REPORT.md` (addendum)
- **Acceptance checks:** each fact names its source file or a run; uptime method chosen with its accuracy.
- **Tests required:** none (facts).
- **Result (22 Oct 2026):** EXPLORATION_REPORT §10, ASSUMPTIONS #29–31. Runs: production runs created in the client-time-zone month, archived included; run rows survive log retention but die with their flow. Uptime: Kuma raw heartbeats (365 days) via `getMonitorBeats`, exact at month edges. Backups: no month-long record exists → 7.7 adds an append-only `history.jsonl` written by the backup agent.

### [x] 7.2 — Owner business profile and client fields
- **Goal:** `opskit/owner/business.yaml` (name, website, support email, signature; placeholder values allowed) with a schema; `client.yaml`: `support.included_hours`, `report.recipients` (existing), `notes.yaml` per client (one sentence per flow, contacts for credentials). `opskit validate` covers both.
- **Spec refs:** 6, 13
- **Files likely touched:** `opskit/schema/*.json`, `opskit/templates/client.yaml.tmpl`, `opskit/lib/validate.sh`, tests
- **Acceptance checks:** missing/invalid fields fail with a clear message; existing clients stay valid (defaults).
- **Tests required:** `validate.bats` cases.
- **Result (22 Oct 2026):** `opskit/schema/business.schema.json` (`business_name`, `support_email` required; `website` https, `phone`, `support_hours`, `signature`), `opskit/schema/notes.schema.json` (`notes_for`, `flows`/`accounts` one sentence each, `welcome`), `opskit/templates/business.example.yaml`, `opskit/lib/business.sh` (`business_get` with placeholders + one warning on stderr), client `support.included_hours` (0–40, default 1, in the client template), `opskit validate` detects both new types. Tests: `validate.bats` +3, `business.bats` (2).

### [x] 7.3 — Read-only client data layer
- **Goal:** `opskit/lib/clientdata.sh`: `clientdata_active_flows` (name, trigger piece/type, last run) and `clientdata_month_runs` (per flow: total, succeeded, failed, other) for a month in the client's time zone, through `opskit_ro` only (read-only SQL).
- **Spec refs:** 13, 15
- **Files likely touched:** `opskit/lib/clientdata.sh`, `opskit/tests/fixtures/`, tests
- **Acceptance checks:** on a fixture database with hand-counted runs (incl. runs at the month edges in another time zone, test runs, deleted flows) every number matches exactly.
- **Tests required:** docker-tagged bats with a fixture Postgres (like `detect_failed_runs.bats`).
- **Result (22 Oct 2026):** `opskit/lib/clientdata.sh`: `clientdata_active_flows` (published name, trigger piece/name, every piece used via `jsonb_path_query($.**.pieceName)`, last production run) and `clientdata_month_runs` (per flow: total/succeeded/failed/other; month in the client's time zone via `AT TIME ZONE`; grouped by flow, current published name), both through `opskit_ro` only. `clientdata.bats` (5, docker): hand-counted fixture incl. Berlin/UTC month edges, test runs excluded, archived included, renamed versions, `opskit_ro` cannot read connections. SQL also ran on the real 0.92.3 schema (Phase 0 stack, no data there); real runs are checked in 7.10.

### [x] 7.4 — Handover pack `opskit docs <id>`
- **Goal:** renders `opskit/clients/<id>/docs/` (Markdown + one printable HTML): welcome and how to log in; active flows (7.3) with what each does and **how to pause it**; credential ownership checklist (which accounts each flow uses, who owns them, how to rotate); support promise (response hours, how to reach you); backups and data location (server region, backup copies, retention, restore tests); **data & privacy note**; **Zapier → Activepieces migration checklist**; what to do if something breaks. Templates in `opskit/templates/docs/`, white-labelled from `business.yaml`.
- **Spec refs:** 13, A4, A5
- **Files likely touched:** `opskit/lib/commands/docs.sh`, `opskit/lib/docs.sh`, `opskit/templates/docs/`, tests
- **Acceptance checks:** every active flow appears with pause steps; privacy note and Zapier checklist present; no secrets, ids or personal data in the output; unresolved placeholder fails the render.
- **Tests required:** bats with a stubbed data layer; leak check like `flows validate`.
- **Result (22 Oct 2026):** `opskit docs <id>` → `clients/<id>/docs/handover.html`, one printable page (8 sections: welcome + builder address, active flows with what/starts/accounts/last run/**pause steps**, accounts and owners, support, backups and data location, **data & privacy**, **moving from Zapier or Make**, if something breaks). `opskit/lib/docs.sh` (data object), `opskit/templates/docs/handover.jq` (renderer, every value `@html`-escaped), host schema gains optional `location`. Pause wording from the 0.92.3 web source (Automations page, switch tooltip "Flow is on/off"). Refuses output with unfilled values or secret-looking strings. Tests: `docs.bats` (6); html-validate clean; screenshot checked.

### [x] 7.5 — Hours and incident log
- **Goal:** `opskit hours <id> add <h> "<note>"|list [--month]` and `opskit incident <id> add "<what>" [--at]|list` (JSON lines in the client registry); notes cut to 300 chars, no secrets.
- **Spec refs:** 13
- **Files likely touched:** `opskit/lib/commands/{hours,incident}.sh`, schema, tests
- **Acceptance checks:** totals per month correct; bad input refused.
- **Tests required:** bats.
- **Result (22 Oct 2026):** `opskit/lib/worklog.sh`, `opskit hours <id> add|list`, `opskit incident <id> add|list` (`clients/<id>/hours.jsonl` with local dates, `incidents.jsonl` in UTC, month filters in the client's time zone; notes one line ≤ 300 chars, key-like text refused). `worklog_hours_month` / `worklog_incidents_month` feed the report. Tests: `worklog.bats` (4).

### [x] 7.6 — Uptime for a month from Uptime Kuma
- **Goal:** `monitor_uptime <id> <from> <to>` through Kuma's own socket API (method from 7.1), plus the down periods (start, length) for incidents.
- **Spec refs:** 13, 10
- **Files likely touched:** `opskit/templates/monitor/uptime.js`, `opskit/lib/monitor_sync.sh`, tests
- **Acceptance checks:** a monitor with a forced down period reports it and a matching percentage; no Kuma host → "uptime not measured" (not 100 %).
- **Tests required:** docker-tagged bats with real Kuma (extend `monitor.bats`).
- **Result (22 Oct 2026):** `opskit/templates/monitor/uptime.js` (socket: login, find "<id> uptime", `getMonitorBeats`, beats inside the window), `opskit/templates/monitor/uptime-stats.jq` (up/down counts, uptime % with 3 decimals rounded down, down periods with start/end/minutes), `monitor_uptime` in `monitor_sync.sh` (`{"measured": false, …}` without Kuma host or monitor). Tests: `uptime_stats.bats` (4), `monitor.bats` +1 with real Kuma (70 s outage shows as a down period and < 100 %).

### [x] 7.7 — Report data collector
- **Goal:** backup agent appends one line per run to `<root>/backups/<id>/history.jsonl` (ASSUMPTIONS #31); `report_collect <id> <YYYY-MM>` → one JSON: runs per flow (7.3), uptime + down periods (7.6), backups (nights complete/incomplete from that history, last success, off-server state), last restore test, upgrades and rollbacks (history), incidents (auto + logged), hours used vs included.
- **Spec refs:** 13
- **Files likely touched:** `opskit/lib/report.sh`, tests
- **Acceptance checks:** fixture month (DB + backup folders + restore tests + history + logs) gives exactly the expected JSON.
- **Tests required:** bats (docker for the DB part).
- **Result (22 Oct 2026):** backup agent writes `<root>/backups/<id>/history.jsonl` (complete / local_only / failed / skipped, never pruned; `backup_agent.bats` +1). `opskit/lib/report.sh` `report_collect <id> <YYYY-MM>`: runs per flow and totals (7.3), uptime (7.6), backup nights with a complete backup counted per local day from local noon (DST-safe), missing nights, failed runs, last complete; last restore test before the month's end; upgrade events; incidents = down periods + missing nights + rollbacks + owner-logged; hours used vs included. "No record" / "not measured" instead of zeros. `business_get` is silent now; commands warn once through `business_check`. Tests: `report_collect.bats` (3, one exact-match fixture month incl. a backup across the UTC/local date line).

### [x] 7.8 — Report rendering `opskit report <id> --month YYYY-MM`
- **Goal:** HTML (inline CSS, readable in mail clients, prints to PDF), plain-text alternative, saved under `clients/<id>/reports/`; wording a non-technical client understands; white-labelled.
- **Spec refs:** 13
- **Files likely touched:** `opskit/lib/commands/report.sh`, `opskit/templates/report/`, tests
- **Acceptance checks:** golden-file test of the fixture month; no error texts or personal data; numbers identical to 7.7.
- **Tests required:** bats golden files; html check.
- **Result (22 Oct 2026):** `opskit report <id> [--month YYYY-MM]` (default last month in the client's time zone) writes `clients/<id>/reports/<month>.{html,txt,json}`; `opskit/templates/report/report.jq` renders both versions from the same data (six headline numbers, flows table, availability + interruptions, backups + restore test, updates, incidents, support hours; local dates; inline styles for mail clients). html-validate clean apart from the deliberate inline styles; screenshot checked. Tests: `report_render.bats` (4, golden text file `opskit/tests/fixtures/report/2026-09.txt`), `report_collect.bats` +2.

### [x] 7.9 — Sending the report
- **Goal:** `opskit report --all --send [--month]` (default: last month): one email per client to `report.recipients`, copy to you, through your SMTP (curl, like alerts); sent log so a month is never sent twice; a cron line example for an always-on machine.
- **Spec refs:** 13
- **Files likely touched:** `opskit/lib/report_send.sh`, `opskit/lib/commands/report.sh`, docs, tests
- **Acceptance checks:** the mock SMTP inbox receives the email with HTML + text parts and the right recipients; second run sends nothing.
- **Tests required:** bats with `mock_smtp`.
- **Result (22 Oct 2026):** `opskit/lib/report_send.sh`: multipart/alternative email (text + HTML, base64 parts, UTF-8 encoded subject/sender name), To = `report.recipients`, Cc = owner (`OWNER_EMAIL`, else the business support email), SMTP settings from `owner/alerts.conf` (same keys as alerts; password via curl config on stdin, backslashes and quotes escaped), `clients/<id>/reports/sent.jsonl` so a month goes out once (`--resend`). `opskit report <id> --send`, `opskit report --all [--send]` (deployed clients, keeps going after a failure). Cron line for the runbook (7.11). Tests: `report_send.bats` (5, mock SMTP: recipients, auth, decoded parts equal the files, send-once, missing settings).

### [ ] 7.10 — Selftest and CI round
- **Goal:** selftest seeds a demo month on its throwaway client (runs created through flows), generates the handover pack and the report, checks the numbers against the database and that the email reaches the mock inbox.
- **Spec refs:** 17 Phase 7 accept
- **Files likely touched:** `opskit/lib/e2e_report.sh`, `opskit/lib/commands/selftest.sh`, `opskit/tests/selftest.bats`
- **Acceptance checks:** green locally and in CI.
- **Tests required:** selftest + bats.

### [ ] 7.11 — Runbook, ADR-019 and phase close
- **Goal:** `docs/runbooks/handover-and-report.md` (when to send the pack, how to log hours/incidents, monthly routine), ADR-019, PROGRESS + verification report, go-to-market: handover pack and care report move from "coming" to included.
- **Spec refs:** 13, 17
- **Files likely touched:** `docs/runbooks/`, `docs/DECISIONS.md`, `docs/PROGRESS.md`, `docs/go-to-market/*`
- **Acceptance checks:** you can produce a client's pack and month report from the runbook alone.
- **Manual verification:** you read one generated pack and one report and say whether a client would understand them.
