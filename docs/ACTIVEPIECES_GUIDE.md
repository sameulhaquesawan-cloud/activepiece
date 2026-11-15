# Activepieces — a beginner's guide

For you, the owner: what Activepieces is, how to use your own builder at
`https://activepiece.autonyxai.shop`, what it can and cannot do in the free Community Edition, and how
that turns into a service you sell. Running servers, backups and alerts is in `OPERATOR_GUIDE.md`.

Screen names below are from version 0.92; if a button is named slightly differently, look for the
closest match.

## 1. What it is, in one minute
Activepieces is a free, open-source alternative to **Zapier** and **Make**. You build small automations
("when X happens, do Y, then Z") by clicking boxes together instead of writing code. It runs on **your**
server, so there are no per-task fees and the data stays with you (or your client).

Example: *when someone fills in the website contact form → save them in a table → email the owner →
send the person a "thanks, we'll be in touch" email.* That is one **flow**.

## 2. The words you need
| Word | Means | Zapier calls it |
|---|---|---|
| **Flow** | one automation, from trigger to last step | Zap |
| **Trigger** | the first box: what starts the flow (a form sent, a new email, every morning at 8) | Trigger |
| **Step** (action) | each box after the trigger: send an email, add a row, ask an AI, call a website | Action |
| **Piece** | an app integration (Gmail, Slack, Google Sheets, HubSpot, OpenAI …). Your builder lists hundreds | App |
| **Connection** | your login to an app, saved once and reused by steps. Stored encrypted | Connected account |
| **Publish** | switch the flow on with its current version. Edits do nothing until you publish again | Turn on |
| **Run** | one execution of a flow. Every run is logged: succeeded or failed, with each step's data | Task history |
| **Webhook** | a private web address that starts a flow when something is sent to it (forms, shops, other tools) | Webhook |
| **Table** | a simple built-in spreadsheet inside Activepieces, for data flows read and write | Zapier Tables |
| **Code step** | a step where you (or an AI) write a few lines of JavaScript for anything the pieces cannot do | Code by Zapier |
| **Router / branch** | "if this, go left; otherwise go right" | Paths |
| **Loop** | repeat steps for each item in a list (each invoice, each row) | Looping |

## 3. Your first 15 minutes
1. Open `https://activepiece.autonyxai.shop` and sign in with the admin account you created.
2. **Look around** (left menu): **Flows** (your automations), **Runs** (history of every run),
   **Connections** (saved app logins), **Tables**. Settings and the admin area sit at the bottom/left.
3. **Build a test flow without any account:**
   1. Flows → **New flow** (or "Create flow" → start from scratch).
   2. Click the trigger box → choose **Schedule** → "Every X minutes" → 5 minutes. (Or **Webhook** →
      "Catch webhook" if you want to trigger it yourself from a browser or form.)
   3. Click **+** under it → choose **Code** → leave the example or write
      `export const code = async () => ({ hello: "world", time: new Date().toISOString() });`
   4. Click **Test** on each step: you see what each box produced. Testing never counts as a real run.
   5. Click **Publish**. It now runs on its own; check **Runs** after 5 minutes.
   6. Switch it off again (the toggle on the flow) so it does not run forever.
4. **Try one of our ready-made flows** (section 6) instead of starting from zero.

When a step needs an app (Gmail, Slack …), the step asks you to **create a connection**: you sign in
to that app once (or paste its key), and every flow can reuse it.

## 4. What you can do with it
Anything that is "when something happens in one tool, do something in others", for example:
- **Leads:** website form, Facebook/Instagram lead ads or a booking tool → table/CRM → instant email
  or Telegram/Slack message to the owner → automatic reply to the lead.
- **Follow-ups:** a paid order → wait 7 days → ask for a review; an overdue invoice → reminder email.
- **Email triage with AI:** new email → AI decides "urgent / invoice / spam" → label it, alert someone.
- **Reports:** every Monday → collect numbers from tools → send one summary email.
- **Glue between tools:** new customer in the shop → add to the newsletter, the CRM and the accounting tool.
- **AI steps:** summarise, classify, translate or draft replies with OpenAI, Claude, Gemini or a local
  model (your own key; we also ship an "OpenAI compatible" piece for any provider with that API).
- **Waiting and timing:** delays ("wait 3 days"), schedules ("weekdays at 8"), loops over lists.
- **Your own data:** built-in Tables, so small businesses don't need Google Sheets at all.

How to judge an idea: if a person does the same clicks more than a few times a week, and each tool
involved has a piece (or a web API), it can almost always be automated.

## 5. What you cannot do (free Community Edition)
These are paid-only features, checked on our version (`docs/EXPLORATION_REPORT.md` §2). Do not promise
them to clients:
- **Your logo/branding** in the builder (white-label) — the builder says "Activepieces". Fine for our
  service: the client mostly sees results, and our own reports and handover pack carry your brand.
- **More than one team project**, project members and roles: in practice **one login per client
  server** (the admin). Clients who want their own login get the admin login or none.
- **SSO, audit logs, Git sync, API keys, environments (dev/prod), embedding**, managed templates,
  global connections, secret managers, MCP servers and "agents" features.
- **Built-in failure alerts** are hidden in this edition → that is exactly why opskit has its own
  failed-run alerts (Telegram/email within 5 minutes).

Other limits to know:
- Every piece and the template gallery need internet access to `cloud.activepieces.com` (fine on a
  normal server).
- Some apps need extra setup on their side, e.g. Google (a Cloud project + 2-step verification),
  Meta/Facebook lead ads (a Meta app). The flow READMEs say exactly what.
- It is not a database or a website builder: heavy data or a full customer portal belongs elsewhere.
- Code steps run directly on the server: fine because each client has their own server, but only run
  code you understand.

## 6. Our ready-made flows (the template library)
Each one is tested, starts switched off, and comes with a README (what to set up) and a checklist.
| Template | What it does | Client needs |
|---|---|---|
| `lead-capture-tables` | website form → Leads table → email to owner → auto-reply | a mail account (SMTP) |
| `invoice-reminder-tables` | weekday mornings: overdue invoices in a table → reminder email | a mail account (SMTP) |
| `lead-capture` / `invoice-reminder` | the same with Google Sheets + Gmail | Google account (2-step verification) |
| `review-request` | paid order → wait 7 days → review request, once per order | a mail account (SMTP) |
| `ai-email-sorter` | new Gmail email → AI label; urgent → Slack | Gmail, AI key, Slack |
| `lead-ad-alert` | Facebook/Instagram lead ad → HubSpot → email | Meta app, HubSpot, Gmail |

To put one into your builder, in the Codespace terminal:
```bash
opskit/bin/opskit flows import lead-capture-tables autonyx-practice \
  --set OWNER_EMAIL=you@example.com --set BUSINESS_NAME="Autonyx" --set FROM_EMAIL=you@example.com
```
It asks for your builder admin email and password (type them yourself; used once, never stored). Then
in the builder: open the flow → create the **SMTP** connection when a step asks → **Test** → **Publish**.
Details per template: `opskit/flows/<template>/README.md`; general steps: `docs/runbooks/flow-templates.md`.

## 7. Everyday use
- **Runs page:** green = succeeded, red = failed. Click a run to see every step's input and output.
  A failed run shows which step failed and why.
- **Fix and retry:** fix the cause (often an expired connection → reconnect it, or bad data from a
  form), then **Retry** the failed run.
- **Change a flow:** edit, **Test**, then **Publish** again. The running version only changes on publish.
- **Pause:** switch the flow off. History stays.
- **Connections:** if an app password changes, update the connection once; all flows use the new one.
- **You get told about failures:** opskit sends a Telegram/email alert with the flow name and a link to
  the failed run (once Telegram is set up — `OPERATOR_GUIDE.md` §4).

## 8. How this becomes your business
The software is free; clients pay you for **setting it up, running it safely and fixing it** — the
"care" part Zapier customers do not get. Your offer, prices and scripts are in `docs/go-to-market/`
(`offer.md`, `pricing.md`, `demo-script.md`). What you deliver per client:
1. Their own server with their own builder (opskit deploys it in minutes).
2. A few flows from the library, adjusted to them, tested with real data.
3. Nightly encrypted backups, a monthly restore test, monitoring and alerts.
4. Safe version upgrades with automatic rollback.
5. A handover pack (how each flow works and how to pause it) and a monthly care report.

## 9. Learning more
- Official docs: https://www.activepieces.com/docs (building flows, pieces, webhooks).
- Templates in the builder's gallery: good to copy ideas from.
- Practice on your own builder: it is yours, nothing there is a client's data. Delete test flows when done.
