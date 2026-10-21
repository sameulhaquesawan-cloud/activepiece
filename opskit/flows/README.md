# Flow template library

Ready-made Activepieces flows we import into a client's stack during onboarding (SPEC 11). Each one
starts switched off; the client connects their own accounts, we test it, then switch it on.

| Template | What it does | Connections the client creates |
|---|---|---|
| `example/` | test template (webhook → greeting); not for clients | none |

The five client templates (lead capture, AI email sorter, review request, invoice reminder, lead-ad
alert) are added in Phase 5 tasks 5.5–5.9.

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
- `opskit flows import <template> <client>` — task 5.4.

Rules for writing a template: [`CONVENTIONS.md`](CONVENTIONS.md). Facts behind them:
`docs/EXPLORATION_REPORT.md` §8.
