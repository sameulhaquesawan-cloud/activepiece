# Checklist — lead capture (real accounts, once per template version)

Date: ____  Tested by: ____  Stack version: 0.92.3

- [ ] `opskit flows validate lead-capture` passes
- [ ] Imported with `opskit flows import`; flow is off after import
- [ ] Sheets connection created ("OAuth2 (Recommended)"); spreadsheet + sheet picked
- [ ] Sheets connection with a service account works too (sheet shared with its email)
- [ ] Gmail connection created; both email steps use it
- [ ] Test with own address: row added (6 columns, in order), owner email and auto-reply received,
      auto-reply "reply" goes to the owner address
- [ ] Published; a real form post creates a SUCCEEDED run
- [ ] `test/bad-email.json` → run FAILED at "Check lead", no row added, failed-run alert received
- [ ] Gmail connection removed → run FAILED at "Email the new lead to the owner", alert received
- [ ] Results noted in `docs/PROGRESS.md`
