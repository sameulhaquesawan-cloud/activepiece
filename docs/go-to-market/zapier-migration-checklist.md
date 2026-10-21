# Zapier / Make → Activepieces migration checklist

Used in sales calls (what moves easily, what needs work) and in the setup (step by step). Applies to
Activepieces Community Edition 0.92.3 as installed by opskit. Mappings below were checked against the
pinned source (`packages/pieces/core/*`) on 21 Oct 2026.

## 1. Inventory (before the proposal)
For every Zap / Make scenario, write one row:

| Name | On? | Trigger (app + event) | Steps (apps) | Runs per month | Business impact if it stops | Owner | Notes |
|---|---|---|---|---|---|---|---|

- Export the list: Zapier → *Zaps* page (and Zap history for run counts); Make → *Scenarios* (operations used).
- Mark switched-off or duplicate ones: don't migrate what nobody uses.
- Sort by impact; migrate the top three in the setup.

## 2. Check each app exists as a piece
Open the Activepieces builder → *+ step* → search the app. 771 pieces were listed on a 0.92.3 install with
internet access (Phase 0). If an app is missing: use the **HTTP** piece with the app's API (needs the app's
API key/token and its documentation) — price it as a *medium* flow.

## 3. Map the building blocks
| Zapier / Make | Activepieces | Note |
|---|---|---|
| Trigger (app event) | piece trigger (polling or instant) | polling interval set by the app piece |
| Webhooks by Zapier / Make custom webhook | **Webhook** trigger | **new URL** — the sending system must be changed at switch-over |
| Schedule by Zapier / Make scheduling | **Schedule** trigger | time zone set in the trigger |
| Filter / Paths / Router | **Router** (branches) | conditions per branch; fallback branch |
| Looping by Zapier / Iterator | **Loop** | |
| Delay by Zapier / Sleep | **Delay** piece | long delays survive restarts (stored in the database) |
| Formatter (text, numbers, dates) | **Text Helper**, **Math Helper**, **Date Helper**, **Data Mapper** pieces, or a **Code** step | |
| Code by Zapier / Make custom functions | **Code** step (TypeScript/JavaScript) | |
| Storage by Zapier / Make data store | **Store** piece (key-value) or **Tables** | Tables are included in Community Edition |
| Approval / human in the loop | **Approval** piece; **Forms** | |
| Sub-Zaps / Make "call scenario" | **Subflows** | |
| Email by Zapier | **SMTP** piece (client's own mailbox/SMTP) | |
| AI by Zapier / OpenAI modules | AI pieces with the **client's own AI keys** | never the owner's keys |
| Zapier Tables / Interfaces / Chatbots, Make apps marketplace | — | not migrated; discuss alternatives |

## 4. What the Community Edition does not do (say it in the sales call)
Several team members with roles, single sign-on, audit logs, custom branding of the builder, Git sync,
several projects, global (shared) connections, secret managers, API keys for the platform. One admin login
per client. If the client needs these, Activepieces' paid plans or another tool fit better — say so.

## 5. Rebuild and test (per flow)
1. Client creates the app connections in the builder (OAuth logins must be done by the client's account
   owner; API keys are pasted by the client — never sent to you in chat or email).
2. Rebuild the flow; name it like the old Zap; add a note with the old Zap's name/ID.
3. Error handling: set *retry on failure* where the app is flaky; decide *continue on failure* per step.
4. Test with real sample data (*Test step*); compare output fields with the old Zap's history.
5. Publish (switch *On*). Failed production runs now alert you within 5 minutes.

## 6. Side by side, then switch over
- Run old and new in parallel for a few days where it is safe (read-only or idempotent flows); for flows
  that create or send things, run the new one on a test target or in dry-run first.
- Switch-over per flow: change webhook URLs in the source systems → turn the old Zap/scenario **off** (not
  deleted) → watch the first runs in *Runs* and the alerts.
- Keep the old Zaps off but not deleted for 30 days, then the client cancels/downgrades Zapier/Make.

## 7. Handover
- List of migrated flows with what each does (one line each) and who to call.
- Show the client where to see runs, pause a flow and read alerts.
- Record the date of switch-over and the Zapier/Make plan the client can now cancel (that saving is your
  best testimonial).
