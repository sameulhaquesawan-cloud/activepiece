# Flow template library

Ready-made Activepieces flows we import into a client's stack during onboarding (SPEC 11). Each one
starts switched off; the client connects their own accounts, we test it, then switch it on.

| Template | What it does | Connections the client creates |
|---|---|---|
| `lead-capture/` | website form → Google Sheet row → owner email → auto-reply | Google Sheets, Gmail |
| `invoice-reminder/` | weekday mornings: overdue unpaid invoices in a sheet → reminder email, row marked | Google Sheets, Gmail |
| `review-request/` | paid order webhook → wait 7 days → review request email, once per order | SMTP |
| `ai-email-sorter/` | new Gmail email → client's own AI model → label; urgent → Slack | Gmail, OpenAI Compatible (BYOK), Slack |
| `lead-ad-alert/` | Facebook/Instagram lead ad → HubSpot contact → email to sales (needs a Meta app per client) | Facebook Lead Ads, HubSpot, Gmail |
| `lead-capture-tables/` | same, but leads go into a built-in Activepieces table and mail goes through SMTP — no Google | SMTP |
| `invoice-reminder-tables/` | same, invoices live in a built-in table — no Google | SMTP |
| `example/` | test template (webhook → greeting); not for clients | none |


## Where the client's data lives
| Option | Templates | Needs | Pick it when |
|---|---|---|---|
| **Built-in Tables** (default) | `*-tables` | nothing but a mail account (SMTP) | no Google account, EU / own-server data, simplest setup; the rows are in the client's own database and backups |
| **Google Sheets** | `lead-capture`, `invoice-reminder` | Google account **with 2-step verification** + Google Cloud service account (`CONNECTIONS.md`) | the client already works in Sheets and wants to see/edit rows there |
| Other clouds (Airtable, Microsoft Excel 365, Notion) | not built | Airtable: a free personal access token; Excel 365: Microsoft sign-in; Notion: integration token | on request: copy a `*-tables` template and swap the storage steps (the pieces exist in the catalog; about half a day each, plus a real-account test) |

## One folder per template
| File | Purpose |
|---|---|
| `flow.json` | Activepieces' own export format (`{name, flows:[…]}`), with `{{OPSKIT:KEY}}` placeholders. Also imports in the builder once the placeholders are filled. |
| `template.yaml` | manifest checked against `opskit/schema/template.schema.json`: name, pinned pieces, placeholders, connections, failure mode, sample runs |
| `README.md` | what it does, placeholders, connections (with the no-third-party option), sample run |
| `CHECKLIST.md` | the manual test with real accounts, done once per template version |
| `test/` | sample webhook payloads named in `template.yaml` `test.runs` |

## Commands
- `opskit flows list` — templates, descriptions, connections the client creates.
- `opskit flows validate [<template>]` — everything below plus the manifest schema; runs in `opskit/bin/check`.
- `opskit flows import <template> <client> [--set KEY=value]…` — fills placeholders, asks for the
  client's builder admin password (used once, never stored), installs our custom pieces, creates the
  flow switched off and prints the connections to create. Same flow name already there → nothing
  changes (`--again` for a copy). `--print-steps` writes the filled file to `clients/<id>/flows/` and
  prints the click-by-click builder import instead.
- `opskit selftest` imports every template into its practice stack and replays the `test/` payloads of
  templates that need no accounts (needs pieces: CI, Codespaces).

Rules for writing a template: [`CONVENTIONS.md`](CONVENTIONS.md). Facts behind them:
`docs/EXPLORATION_REPORT.md` §8.
