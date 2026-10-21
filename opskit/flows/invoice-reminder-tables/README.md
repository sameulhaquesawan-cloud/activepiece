# Invoice reminder (built-in table)

The same flow as `invoice-reminder`, but the invoices live in an **Activepieces table** and reminders
go out through the business's own **SMTP** account. No Google account is needed, and dates are plain
text (`2026-01-10`), so there is no spreadsheet date-format trap.

**What it does:** every weekday at 08:00 (client time zone) it reads the **Invoices** table, picks
invoices that are open, `OVERDUE_DAYS` past due and not reminded in the last `REPEAT_DAYS`, emails each
customer (owner in bcc) and writes the time into "Reminded at".
**If something is wrong:** a row with a broken email or due date is skipped, the others are still
reminded, and the run then fails naming the invoices ("1 invoice(s) skipped - invalid email or due
date: INV-4") so the failed-run alert reaches you. Reading and marking are retried automatically;
sending is not, so nobody gets a double reminder.

## Placeholders (`--set KEY=value`)
| Key | Meaning | Default |
|---|---|---|
| `OWNER_EMAIL` | bcc of every reminder; replies go there | — |
| `BUSINESS_NAME` | sender name and signature | — |
| `FROM_EMAIL` | sender address (the SMTP account must be allowed to use it) | — |
| `TIMEZONE` | time zone of the 08:00 run, e.g. `Europe/Berlin` | — |
| `PAYMENT_INFO` | how to pay, one paragraph | — |
| `OVERDUE_DAYS` | days after the due date before the first reminder | `3` |
| `REPEAT_DAYS` | days between reminders for the same invoice | `7` |

## The table
The import creates **Invoices** with the columns Invoice, Customer, Email, Amount, **Due date**,
Status, Reminded at (all text). Fill it in the app (Tables → Invoices → add rows, or Import CSV):
- Due date as `YYYY-MM-DD`;
- Status `paid` or `cancelled` stops reminders, anything else counts as open;
- leave "Reminded at" empty; the flow fills it. Do not rename the columns.

## Import
```bash
opskit flows import invoice-reminder-tables <client> --set OWNER_EMAIL=… --set BUSINESS_NAME="…" \
  --set FROM_EMAIL=… --set TIMEZONE=Europe/Berlin --set PAYMENT_INFO="…"
```

## Connection
**SMTP** (`../CONNECTIONS.md`). In the flow: "Send reminder email" → pick it.

## Sample run
1. Add two rows with your own address: one overdue and open, one `paid`.
2. **Test Flow** → one reminder arrives (owner bcc), "Reminded at" of the open row is filled; the paid
   row is untouched. Test again → nothing is sent.
3. Add a row with `not-an-email` → the run fails at "Report invoices that could not be reminded"
   naming that invoice, after the valid reminders went out.
