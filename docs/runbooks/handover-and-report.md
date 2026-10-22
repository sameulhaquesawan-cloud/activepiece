# Runbook — handover pack and monthly care report

Commands run on your machine (Codespace, WSL, cloud AI session) from the repo folder. Design: ADR-019 in
`docs/DECISIONS.md`.

## Once: your business details and email account
1. Copy `opskit/templates/business.example.yaml` to `opskit/owner/business.yaml` and fill in your business
   name, support email, website, support hours and closing line. Check:
   `opskit/bin/opskit validate opskit/owner/business.yaml`. (Until then packs and reports say "YourBrand".)
2. Reports are emailed through the same account as alerts: `opskit/owner/alerts.conf` needs `SMTP_URL`
   (e.g. `smtps://smtp.gmail.com:465`), `SMTP_FROM`, `SMTP_USER`, `SMTP_PASSWORD` (an app password) and
   `OWNER_EMAIL` (your copy). Type the password into the file yourself; never paste it into chat.
3. In each host yaml set `location:` (e.g. `Germany (Falkenstein)`); it appears in the privacy section.

## Per client: notes (optional, 5 minutes)
`opskit/clients/<id>/notes.yaml` adds what only you know:
```yaml
notes_for: acme
welcome: Your website leads and invoice reminders now run on your own server.
flows:
  Lead capture: Website form leads go to the sales sheet and Anna gets an email.
accounts:
  Gmail: Anna owns it; login in the practice password manager.
  Google Sheets: Anna owns it; same login as Gmail.
```
One sentence each; never passwords, keys or customer data. Check: `opskit/bin/opskit validate <file>`.

## Handover pack (at go-live, and after bigger changes)
```bash
opskit/bin/opskit docs acme
```
Opens nothing on the client's side: it reads which flows are switched on (read-only) and writes
`opskit/clients/acme/docs/handover.html`. Open it in a browser, read it once, **Print → Save as PDF**, send
the PDF to the client. "Not recorded yet" in the accounts table means: ask the client who owns that account
and add it to `notes.yaml`.

## During the month: log hours and incidents
```bash
opskit/bin/opskit hours acme add 1.5 "changed the invoice reminder text"
opskit/bin/opskit incident acme add "Gmail was down for 2 hours; failed runs retried"
opskit/bin/opskit hours acme list            # this month, used vs included
```
Downtime, nights without a complete backup and upgrade rollbacks are counted automatically; log only what
the client should know beyond that. Included hours per month: `support.included_hours` in client.yaml
(Care 1, Care Plus 3).

## On the 1st: the care report
```bash
opskit/bin/opskit report --all              # builds last month's report for every deployed client
# read opskit/clients/<id>/reports/<YYYY-MM>.html for each client, then:
opskit/bin/opskit report --all --send       # emails each client once (copy to you)
```
One client, another month: `opskit/bin/opskit report acme --month 2026-10 --send`. Sent again by mistake?
It refuses; `--resend` really sends a second time.

Automatic on an always-on machine (WSL/Linux): `crontab -e` and add (08:05 on the 1st):
```
5 8 1 * * cd ~/activepiece && opskit/bin/opskit report --all --send >> ~/opskit-report.log 2>&1
```
Reading first is better while you have few clients.

## Reading a report before it goes out
- **Availability "not measured"**: the client has no Uptime Kuma monitor yet (`opskit monitor sync <id>`).
- **Backups "no record"**: the host's backup agent predates the history (it records from the next
  `opskit deploy <id>` on).
- **Failed runs** are usually the client's data (a wrong email in a form). Many failures of one flow: look
  at it before sending, add an incident note if you fixed something.
- Numbers come from the client's own database for flows that still exist; a flow deleted during the month
  takes its runs with it.
