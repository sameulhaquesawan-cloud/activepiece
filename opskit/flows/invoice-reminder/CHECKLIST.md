# Checklist — invoice reminder (real accounts, once per template version)

Date: ____  Tested by: ____  Stack version: 0.92.3

- [ ] `opskit flows validate invoice-reminder` passes
- [ ] Imported with `opskit flows import`; flow is off after import
- [ ] Sheets connection: spreadsheet and sheet picked in both Sheets steps
- [ ] "Read invoices sheet" output: rows with `row` and `values` keyed by header names (the code step
      also accepts `{rows: […]}`) — note the shape here: ____
- [ ] Gmail connection picked in "Send reminder email"
- [ ] Test: exactly one reminder for the overdue open row, owner in bcc, column G filled, other
      columns unchanged
- [ ] Second test: nothing sent
- [ ] Broken email row → reminders for valid rows sent, run FAILED naming the row, alert received
- [ ] Published; first scheduled run at 08:00 client time on a weekday
- [ ] Results noted in `docs/PROGRESS.md`
