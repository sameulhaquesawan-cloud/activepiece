# Checklist — invoice reminder (built-in table) (real account, once per template version)

Date: ____  Tested by: ____  Stack version: 0.92.3

- [ ] `opskit flows validate invoice-reminder-tables` passes
- [ ] Imported with `opskit flows import`; **Invoices** table exists with 7 columns; flow off
- [ ] SMTP connection picked in "Send reminder email"; no step "Incomplete"
- [ ] Test: one reminder for the overdue open row, owner in bcc, "Reminded at" filled, others unchanged
- [ ] Second test: nothing sent
- [ ] Broken email row → reminders for valid rows sent, run FAILED naming the invoice, alert received
- [ ] Rows added through "Import CSV" are read correctly (Due date as text)
- [ ] Published; first scheduled run at 08:00 client time on a weekday
- [ ] Results noted in `docs/PROGRESS.md`
