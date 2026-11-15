# Activepieces 101 — owner learning track

For the owner, learning while the local session works in Chrome. Practise only on **staging**
(`staging-activepiece.autonyxai.shop`), never on a client stack. Official docs: https://www.activepieces.com/docs

## Words you need
**Flow** — one automation: a trigger plus the steps after it. Has a draft you edit and a published version that runs.
**Trigger** — the first step, what starts the flow: a webhook (an app calls a URL), a schedule, or an app event (new email, new row).
**Step / action** — one thing the flow does: send an email, add a row, ask an AI, call an API.
**Piece** — an integration (Gmail, Google Sheets, Telegram, OpenAI…). Each piece offers triggers and actions.
**Connection** — your saved login/API key for a piece. Stored encrypted with the stack's `AP_ENCRYPTION_KEY` — lose that key and every connection is lost.
**Data selector** — how a step uses earlier output, e.g. the email address that arrived in the trigger.
**Run** — one execution of a flow. Succeeded or failed; the run log shows every step's input and output.
**Branch / Router, Loop, Code** — if/else, repeat per item, a small JavaScript step.
**Tables** — built-in spreadsheet-like storage, so a flow needs no Google Sheets.
**Publish** — makes the draft the live version; a flow must also be switched on to run.

## Practice ladder (one per day, in staging)
1. Log in, find Flows, Runs, Connections, Tables. Open an imported template and read it step by step.
2. Build: Webhook trigger → Telegram "send message" → publish. Call the webhook URL from the browser; see the run.
3. Add a Tables step that stores the webhook data; add a branch that only alerts when `amount > 100`.
4. Break it on purpose (wrong Telegram chat id), find the failed run, read the error, fix, re-run.
5. Import a template with `opskit flows import`, connect your own Gmail, run its sample payload.
6. Do the 3-minute demo (`docs/go-to-market/demo-script.md`) out loud on prod.

## What opskit adds around Activepieces (what clients pay for)
Own server + HTTPS (`host bootstrap`, `deploy`), nightly encrypted backups + monthly restore test (`backup`,
`restore-test`), uptime + failed-run alerts within 5 minutes (`monitor`, host agent), ready flows (`flows`).
