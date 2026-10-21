# Checklist — example

- [ ] `opskit flows validate example` passes
- [ ] Imports into a fresh stack, flow is off after import
- [ ] `test/good.json` → SUCCEEDED; `test/missing-name.json` → FAILED at "Check name"
- [ ] Failed run produced one failed-run alert (production run, within 5 minutes)
