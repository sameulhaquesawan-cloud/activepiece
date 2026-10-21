# Invoice reminder

**For:** businesses that track invoices in a Google Sheet (or export them there) and chase late payers
by hand.
**What it does:** every weekday at 08:00 (client time zone) it reads the invoices sheet, picks open
invoices that are `OVERDUE_DAYS` past due and were not reminded in the last `REPEAT_DAYS`, sends each
customer a polite reminder (owner in bcc) and writes the time into "Reminded at".
**If something is wrong:** a row with a broken email or due date is skipped, the others are still
reminded, and the run then fails naming the sheet rows ("2 invoice row(s) skipped - invalid email or
due date in sheet rows 6, 9") so the failed-run alert reaches you. A Google error fails the run at that
step. Reading and marking are retried automatically; sending is not, so nobody gets a double reminder.

## Placeholders (`--set KEY=value`)
| Key | Meaning | Default |
|---|---|---|
| `OWNER_EMAIL` | bcc of every reminder; replies go there | — |
| `BUSINESS_NAME` | sender name and signature | — |
| `TIMEZONE` | time zone of the 08:00 run, e.g. `Europe/Berlin` (use the client's `timezone`) | — |
| `PAYMENT_INFO` | how to pay, one paragraph | — |
| `OVERDUE_DAYS` | days after the due date before the first reminder | `3` |
| `REPEAT_DAYS` | days between reminders for the same invoice | `7` |

The run hour (08:00) and "weekdays only" are set in the trigger; change them in the builder if needed.

## The sheet
Row 1 holds these headers (any order for reading, but **"Reminded at" must be column G**, because
marking writes column G):

| A Invoice | B Customer | C Email | D Amount | E Due date | F Status | G Reminded at |
|---|---|---|---|---|---|---|
| INV-1001 | Sam Example | sam@example.com | €120.00 | 2026-01-10 | open | |

- Due date: format column E as `YYYY-MM-DD` (Format → Number → Custom date and time). Other formats
  can be misread: `01/02/2026` is read as 2 January.
- Status `paid` or `cancelled` (any case) stops reminders; anything else counts as open.
- Empty "Invoice" cells are ignored (blank rows).

## Import
```bash
opskit flows import invoice-reminder <client> --set OWNER_EMAIL=… --set BUSINESS_NAME="…" \
  --set TIMEZONE=Europe/Berlin --set PAYMENT_INFO="…"
```

## Connections (the client's own accounts)
How-to: `../CONNECTIONS.md`.
- **Google Sheets** — Try another method → **Service Account (Advanced)**, sheet shared with the service
  account as Editor (our default; "Connect" failed with "insufficient authentication scopes" in our test).
- **Gmail** — **Connect** (tick every box), or Try another method → Custom OAuth2 App (client's own Google Cloud app,
  redirect `https://<domain>/redirect`), or a Workspace service account.

In the flow: "Read invoices sheet" and "Mark invoice as reminded" → pick the Sheets connection, the
spreadsheet and the sheet (the same in both); "Send reminder email" → pick the Gmail connection.

## Sample run
1. Make a copy of the sheet with two test rows whose Email is your own address: one overdue and open,
   one `paid`.
2. Test the flow in the builder → one reminder arrives (bcc to the owner), column G of the open row
   gets the time; the paid row is untouched. Test again → nothing is sent (reminded less than
   `REPEAT_DAYS` ago).
3. Put `not-an-email` into a third open overdue row and test → the run fails at "Report rows that could
   not be reminded" naming that row, after the valid reminders went out.
