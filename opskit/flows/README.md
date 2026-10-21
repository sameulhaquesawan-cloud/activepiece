# Flow template library

Ready-made Activepieces flows we import into a client's stack during onboarding (SPEC 11). Each one
starts switched off; the client connects their own accounts, we test it, then switch it on.

| Template | What it does | Connections the client creates |
|---|---|---|
| `lead-capture/` | website form → Google Sheet row → owner email → auto-reply | Google Sheets, Gmail |
| `invoice-reminder/` | weekday mornings: overdue unpaid invoices in a sheet → reminder email, row marked | Google Sheets, Gmail |
| `review-request/` | paid order webhook → wait 7 days → review request email, once per order | SMTP |
| `ai-email-sorter/` | new Gmail email → client's own AI model → label; urgent → Slack | Gmail, OpenAI Compatible (BYOK), Slack |
| `example/` | test template (webhook → greeting); not for clients | none |

Still to come (Phase 5): lead-ad alert (5.9).

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
