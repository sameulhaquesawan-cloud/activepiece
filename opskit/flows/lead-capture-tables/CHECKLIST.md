# Checklist — lead capture (built-in table) (real account, once per template version)

Date: ____  Tested by: ____  Stack version: 0.92.3

- [ ] `opskit flows validate lead-capture-tables` passes
- [ ] Imported with `opskit flows import`; the **Leads** table exists with 6 columns; flow off
- [ ] Only the two email steps need the SMTP connection; no step "Incomplete" after picking it
- [ ] Test Flow with `test/good-lead.json`: row in the table (all 6 cells filled), owner email and
      auto-reply ("Hi Jane,") received
- [ ] Published; `test/bad-email.json` → run FAILED at "Check lead", no new row, alert received
- [ ] Table exported with the app's backup/restore? (`opskit restore-test` keeps the rows) — note result
- [ ] Results noted in `docs/PROGRESS.md`
