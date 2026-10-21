# Lead capture

**For:** any business with a website contact or quote form.
**What it does:** the form posts to a webhook → the lead is checked → a row is added to the client's
Google Sheet → the owner gets an email → the lead gets a friendly auto-reply.
**If something is wrong:** a lead without a valid email fails the run ("Invalid email in field
"email""); a Google or Gmail error fails the run too. Either way the failed-run alert reaches you within
5 minutes with the run link; retry the run from the builder once fixed. Nothing is retried
automatically, so no lead is saved or emailed twice.

## Placeholders (`--set KEY=value`)
| Key | Meaning | Default |
|---|---|---|
| `OWNER_EMAIL` | who gets each lead; replies to the auto-reply go there too | — |
| `BUSINESS_NAME` | sender name and signature | — |
| `LEAD_SOURCE` | source written when the form sends none | `website` |
| `REPLY_SUBJECT` | auto-reply subject | `Thanks for getting in touch` |
| `REPLY_TEXT` | auto-reply text | `We received your message and will get back to you within one business day.` |

## Before importing
1. The client creates a Google Sheet (e.g. "Leads") with these headers in row 1, columns A–F:
   `Received at | Name | Email | Phone | Message | Source`.
2. Decide how they connect Google (see Connections) — EU clients: the no-third-party options.

## Import
```bash
opskit flows import lead-capture <client> --set OWNER_EMAIL=… --set BUSINESS_NAME="…"
```

## Connections (the client's own accounts)
- **Google Sheets** — "OAuth2 (Recommended)" (sign in with Google through Activepieces' sign-in service), or
  "Service Account (Advanced)": share the sheet with the service account's email (no third party).
- **Gmail** — "OAuth2 (Recommended)", or "Custom OAuth2 App (Advanced)" with the client's own Google Cloud
  app (redirect URL `https://<domain>/redirect`), or a Workspace service account with domain-wide
  delegation.

Then in the flow: step "Add lead to sheet" → pick the Sheets connection, the spreadsheet and the sheet;
both Gmail steps → pick the Gmail connection.

## Hooking up the form
Publish the flow, open the trigger and copy the **production** webhook URL. Point the form at it
(JSON or a normal form post; both are parsed) with fields `name`, `email`, `phone`, `message` and
optionally `source`. Most form tools can send submissions to a webhook URL, natively or with a plugin;
map their field names to these. Check the field names once in the sample run.

## Sample run
1. With the flow open, use **Test** on the trigger and send `test/good-lead.json`:
   `curl -X POST <test webhook url> -H 'content-type: application/json' -d @test/good-lead.json`
2. Test the flow → a row appears in the sheet, the owner gets "New lead: Jane Example", the auto-reply
   goes to the test address (use your own address instead of `Jane@Example.com` for a real check).
3. Send `test/bad-email.json` to the production URL after publishing → the run fails at "Check lead"
   and the failed-run alert arrives.
