# AI email sorter

**For:** a business whose shared Gmail inbox mixes customer mail, invoices and newsletters.
**What it does:** for every new email → the subject, sender and first `MAX_CHARS` characters of the
text go to the client's own AI model (our `openai-compatible` piece, ADR-013) → it answers one of
`urgent`, `customer`, `invoice`, `newsletter`, `other` plus a one-line summary → the email gets the
matching Gmail label; urgent ones are also posted to a Slack channel (sender, subject, summary — never
the email text).
**Where the email goes:** only to the AI provider the client chose with their own key. Nothing is
stored outside the client's server and mailbox. EU clients: pick an EU-hosted provider or a local
model and list it in their sub-processors.
**If something is wrong:** an AI answer that is not the expected JSON or names an unknown category
fails the run at "Read the AI answer"; Gmail, AI or Slack errors fail at their step. The email then has
no label yet, the failed-run alert reaches you, and you retry the run after fixing. The AI call and
the labelling are retried automatically; the Slack post is not.
The AI is told to treat the email as data and ignore instructions inside it; a crafted email can at
worst get the wrong label.

## Placeholders (`--set KEY=value`)
| Key | Meaning | Default |
|---|---|---|
| `BUSINESS_NAME` | whose inbox (used in the AI instructions) | — |
| `BUSINESS_CONTEXT` | one or two sentences that help decide what is urgent | `A small business.` |
| `MAX_CHARS` | characters of the body sent to the AI | `4000` |

## Before importing
1. In Gmail create five labels, e.g. `AI/Urgent`, `AI/Customer`, `AI/Invoice`, `AI/Newsletter`,
   `AI/Other`.
2. The client has an AI account and key (OpenAI, OpenRouter, Mistral, …) or a local model server.
3. A Slack channel for urgent mail; with the bot-token option, invite the bot to it.

## Import
```bash
opskit flows import ai-email-sorter <client> --set BUSINESS_NAME="…" --set BUSINESS_CONTEXT="…"
```
The import installs our `openai-compatible` piece on the client's server first (platform admin).

## Connections (the client's own accounts)
How-to: `../CONNECTIONS.md`.
- **Gmail** — **Connect** (tick every box), Try another method → Custom OAuth2 App (own Google Cloud app, redirect
  `https://<domain>/redirect`) or a Workspace service account.
- **OpenAI Compatible (BYOK)** — base URL and the client's API key.
- **Slack** — **Connect**, or Try another method → Bot Token from a Slack app the client creates (no third party).

In the flow: trigger → Gmail connection (optionally restrict to a Gmail category or label); "Ask AI for
the category" → connection and model (a small, cheap model is enough; reasoning is set to low); each
"Label: …" step → Gmail connection and its label; "Tell the team on Slack" → connection and channel.

## Sample run
1. Send a test email to the inbox: "I have to cancel tomorrow's appointment, please call me".
2. Test the trigger (loads the newest email), then test the flow → `AI/Urgent` label in Gmail and a
   Slack post with sender, subject and summary.
3. Send a newsletter-like email → `AI/Newsletter`, no Slack post.
4. Publish. New mail is checked every few minutes (polling).
