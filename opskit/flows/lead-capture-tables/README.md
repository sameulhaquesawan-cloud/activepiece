# Lead capture (built-in table)

The same flow as `lead-capture`, but leads are saved in an **Activepieces table** and the emails go out
through the business's own **SMTP** mail account. No Google account, Google Cloud project or sign-in
service is involved — the table lives in the client's own database (it is in their backups), and the
only account is their mail provider.
**Use it when:** the client has no Google account, wants everything on their own server (EU clients),
or you want the simplest setup. Prefer `lead-capture` when the client already lives in Google Sheets.

**What it does:** the form posts to a webhook → the lead is checked → a row is added to the **Leads**
table → the owner gets an email → the lead gets an auto-reply.
**If something is wrong:** a lead without a valid email fails the run ("Invalid email in field
"email""); an SMTP error fails the run. The failed-run alert reaches you within 5 minutes with the run
link. Nothing is retried automatically, so no lead is saved or emailed twice.

## Placeholders (`--set KEY=value`)
| Key | Meaning | Default |
|---|---|---|
| `OWNER_EMAIL` | who gets each lead; replies to the auto-reply go there too | — |
| `BUSINESS_NAME` | sender name and signature | — |
| `FROM_EMAIL` | sender address (the SMTP account must be allowed to use it) | — |
| `LEAD_SOURCE` | source saved when the form sends none | `website` |
| `REPLY_SUBJECT` | auto-reply subject | `Thanks for getting in touch` |
| `REPLY_TEXT` | auto-reply text | `We received your message and will get back to you within one business day.` |

## Import
```bash
opskit flows import lead-capture-tables <client> --set OWNER_EMAIL=… --set BUSINESS_NAME="…" --set FROM_EMAIL=…
```
The import creates the **Leads** table (columns Received at, Name, Email, Phone, Message, Source) if it
does not exist yet. Do not rename or delete those columns: the flow fills them by name.

## Connection (the client's own account — `../CONNECTIONS.md`)
**SMTP** — host, port, user, password of the client's mail provider (Gmail: `smtp.gmail.com`, port 465,
TLS on, an app password). In the flow: both "Email …" / "Auto-reply …" steps → pick it. Nothing else.

## Hooking up the form
Publish the flow, copy the **production** webhook URL from the trigger and point the form at it (JSON
or a normal form post) with fields `name`, `email`, `phone`, `message`, optionally `source`.

## Sample run
1. Test the trigger with `test/good-lead.json` (use your own address as `email`), then **Test Flow**.
2. A row appears in the table (Tables in the left menu → Leads); the owner email and the auto-reply
   (starting "Hi Jane,") arrive.
3. Publish and send `test/bad-email.json` to the production URL → the run fails at "Check lead", no row.
