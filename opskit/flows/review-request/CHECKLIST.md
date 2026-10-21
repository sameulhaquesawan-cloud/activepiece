# Checklist — review request (real accounts, once per template version)

Date: ____  Tested by: ____  Stack version: 0.92.3

- [ ] `opskit flows validate review-request` passes
- [ ] Imported with `opskit flows import` (test values `--set WAIT_AMOUNT=1 --set WAIT_UNIT=minutes`); flow off after import
- [ ] SMTP connection created and picked in "Send review request"
- [ ] Paid order → run paused, email after 1 minute, run SUCCEEDED
- [ ] Same order again → SUCCEEDED, no email
- [ ] Pending order → SUCCEEDED, no email
- [ ] No email in paid order → FAILED at "Read order", alert received
- [ ] App restarted during the wait → email still sent after the wait
- [ ] A real shop webhook (Shopify test order, WooCommerce or Stripe test mode) is read correctly
- [ ] Wait set back to 7 days; flow published
- [ ] Results noted in `docs/PROGRESS.md`
