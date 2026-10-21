# Phase 5 — Flow template library (Improvement 4)

SPEC: Section 17 Phase 5, Section 11, Section 10 (failure notifications), Section 15 (client-owned credentials); Phase 0 findings (`docs/EXPLORATION_REPORT.md`: API `IMPORT_FLOW`, `GET /api/v1/flows/<id>/template`, 771 pieces with internet); ASSUMPTIONS #14 (pieces offline in the cloud session → CI/Codespace run the real imports).
**Accept (SPEC 17):** each template imports into a fresh local stack and passes its sample-run instructions (free/test accounts; where a paid third-party account is required, documented as a manual test); `flows validate` catches malformed JSON and missing placeholders.

## Open questions for the owner (recommended defaults in brackets — "ok" accepts them)
**Answered 21 Oct 2026:** owner dropped template 6 (Elmo) and everything related to it (SPEC App. C P2) → five templates, task 5.10 removed; Q2–Q6 defaults accepted.
- **Q1 — Template 6 "Elmo monthly report"** (SPEC 11): Elmo is a paid HR/payroll product with no Activepieces piece and needs a client's Elmo account. [Replace with a generic **monthly summary report** (schedule → rows from Google Sheets or any API via HTTP → summary email); add an Elmo variant when a client needs it.]
- **Q2 — AI provider in template 2** (AI email sorter): [Our own `openai-compatible` piece (ADR-013, any provider, client's own key, reasoning default high) — `flows import` installs it on the client stack; the official OpenAI piece is the fallback.]
- **Q3 — Shop in template 3** (review request): [A generic "order paid" **webhook** (works with Shopify, WooCommerce and Stripe webhooks) so it is testable without a shop; a Shopify-trigger variant later.]
- **Q4 — CRM and channel in template 5** (lead alert): [Facebook Lead Ads → **HubSpot** (free CRM) → email to the client; WhatsApp stays a later paid add-on.]
- **Q5 — How `opskit flows import` logs in:** Community Edition has no API keys. [It asks for the client's admin email and password at the prompt, uses them once to get a session, stores nothing; `--print-steps` instead prints click-by-click UI import steps.]
- **Q6 — Real-account tests:** Google, Slack, HubSpot and Meta need accounts. [CI proves every template imports and runs with webhook/mock data; the full run with real apps is a written manual checklist per template, done once by you (or me with you) in the Codespace using your free test accounts.]

## Design (to confirm in ADR-017)
- One folder per template: `flow.json` (Activepieces' own export format, so it also imports in the UI), `template.yaml` (manifest: name, description, pieces + versions, placeholders, connections the client creates), `README.md`, `CHECKLIST.md`, `test/` payloads. `template.yaml` is a fifth file beyond SPEC 11 — needed to validate placeholders and pieces.
- Placeholders look like `{{OPSKIT:OWNER_EMAIL}}`; `flows import --set OWNER_EMAIL=…` fills them; unknown or missing ones stop the import.
- **Failure convention:** a template never hides errors — a failing step fails the run, so the Phase 4 detector alerts within 5 minutes; where a step must continue on failure, a branch sends the client's own notification and the run is still marked failed. Documented in `opskit/flows/CONVENTIONS.md`.
- Imported flows start **switched off**; the client connects their own accounts, then the flow is tested and switched on.

## Tasks

### [x] 5.1 — Verify template facts (no code)
- **Goal:** on 0.92.3 with pieces (Codespace or CI): exact export format (`GET /api/v1/flows/<id>/template`) and that the UI import accepts it; how to import via API (create flow + `IMPORT_FLOW`) and what happens to piece versions that differ; how Google/Gmail/Slack/HubSpot/Facebook connections work on self-hosted CE (own OAuth app needed or not); piece names + versions for Google Sheets, Gmail, Slack, HubSpot, Facebook Lead Ads, Delay, Schedule, Webhook, SMTP; installing our `openai-compatible` piece by archive.
- **Spec refs:** 11 (*verify* import/export), 0 (never invent APIs)
- **Files likely touched:** `docs/ASSUMPTIONS.md`, `docs/EXPLORATION_REPORT.md` (addendum)
- **Acceptance checks:** each fact has a source/test reference; blockers (e.g. OAuth apps needed) listed for the owner.
- **Result (21 Oct 2026):** `docs/EXPLORATION_REPORT.md` §8, ASSUMPTIONS #16–18. No blocker for 5.2–5.8. Template 5 needs a Meta app per client + `AP_APP_WEBHOOK_SECRETS` (added to 5.9).

### [x] 5.2 — Template format, manifest schema and conventions
- **Goal:** `opskit/flows/README.md` (how the library works), `opskit/flows/CONVENTIONS.md` (placeholders, naming, failure convention, client-owned credentials, flows start off), `opskit/schema/template.schema.json` for `template.yaml`, one tiny `example/` template used by tests.
- **Spec refs:** 11, 10, 15
- **Tests required:** schema validation of good/bad manifests.

### [x] 5.3 — `opskit flows list` and `opskit flows validate`
- **Goal:** `list` shows every template with description and required connections; `validate [<template>]` checks: valid JSON in the export format, manifest valid, every `{{OPSKIT:…}}` used is declared and every declared one is used, pieces in `flow.json` match the manifest, no real-looking secrets/emails/URLs/IDs, README/CHECKLIST/test present.
- **Spec refs:** 17 Phase 5 accept ("validate catches malformed JSON and missing placeholders")
- **Files likely touched:** `opskit/lib/commands/flows.sh`, `opskit/lib/flows.sh`, `opskit/tests/flows_validate.bats`, `opskit/tests/fixtures/flows/*`
- **Tests required:** malformed JSON, undeclared placeholder, unused placeholder, piece mismatch, leaked email/key — each fails with a clear message; all real templates pass (runs in `check`).

### [x] 5.4 — `opskit flows import <template> <client> [--set K=V…]`
- **Goal:** validate → fill placeholders → sign in to the client's builder (Q5) → install required custom pieces (Q2) → create the flow (switched off) → print the connections the client must create and the next steps; `--print-steps` for UI-only import.
- **Spec refs:** 11, USER_FLOWS (import templates during onboarding)
- **Files likely touched:** `opskit/lib/flows.sh`, `opskit/lib/commands/flows.sh`, tests
- **Tests required:** mock API (sign-in, create, import) for argument/placeholder/error handling; password never written to disk or printed; docker-tagged import of `example/` on a selftest stack (pieces required in CI).

### [x] 5.5 — Template 1: lead capture
- **Goal:** webhook form → Google Sheets row → email to the owner → auto-reply to the lead; based on the Phase 0 flow (`docs/phase0-flows/lead_capture.py`); invalid email → run fails (detector alerts).
- **Tests required:** validate passes; CI import; sample run with `test/` payloads (Sheets/email steps as manual checklist).

### [x] 5.6 — Template 4: invoice reminder
- **Goal:** schedule → unpaid rows from Google Sheets → loop → reminder email → mark "reminded"; based on Phase 0 `invoice_reminder.py`.

### [x] 5.7 — Template 3: review request
- **Goal:** "order paid" webhook (Q3) → wait 7 days (Delay; shortened by a placeholder for testing) → review-request email; duplicate orders ignored.

### [x] 5.8 — Template 2: AI email sorter
- **Goal:** new Gmail email → AI classifies (Q2, client's own key) → Gmail label + Slack message for urgent ones; never sends email content anywhere else.

### [x] 5.9 — Template 5: lead-ad alert
- **Goal:** Facebook Lead Ads (Q4) → HubSpot contact → email to the client's sales person; test via webhook variant. Optional `client.yaml` field naming a host secret renders `AP_APP_WEBHOOK_SECRETS` for the Facebook Lead Ads piece (ASSUMPTIONS #18); CHECKLIST covers the Meta app (webhook URL `https://<domain>/api/v1/app-events/facebook-leads`, verify token `activepieces`).

### ~~5.10 — Template 6~~ dropped by the owner (Elmo, SPEC App. C P2)

### [ ] 5.11 — Import acceptance test for all templates
- **Goal:** CI (pieces required): every template validates, imports into a fresh selftest stack, and its webhook/mock sample run behaves as its README says; manual real-account checklist results recorded per template (Q6).
- **Tests required:** docker-tagged, mandatory in CI (`OPSKIT_REQUIRE_PIECES=1`), skipped with a warning offline.

### [ ] 5.12 — Docs and phase close
- **Goal:** `docs/runbooks/flow-templates.md` (import for a client, connect accounts, test, switch on, pause), update `docs/go-to-market/` (offer: template library no longer "coming"; demo script), ADR-017, PROGRESS + phase verification report.
- **Manual verification:** owner imports one template into the Codespace stack following the runbook.
