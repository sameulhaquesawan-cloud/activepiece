# Testing guide — everything, on your real server

Work through this when you have time, in order. Each test says what to do, what you should see, and
what to do if not. Tick the boxes as you go. Two ways to run it:
- **Yourself**, in the Codespace terminal, typing the commands.
- **With the Codespace Claude** (`claude --continue`): paste one test at a time and say "run this test,
  show me the result, change nothing else". It must `git pull` first.

Never paste passwords, tokens or keys into any chat. Type them into the files or websites named.
`opskit` below means `opskit/bin/opskit` run from the repo folder in the Codespace.

Words: **client id** `autonyx-practice` · **builder** `https://activepiece.autonyxai.shop` ·
**Kuma** `https://status.autonyxai.shop` · **server** `oracle-mumbai` (`ubuntu@129.154.225.22`,
key `~/.ssh/oracle`).

---

## Part 0 — Before testing (setup, once)
- [ ] **0.1 Codespace up to date.** Open the Codespace → terminal: `git pull` → no errors.
- [ ] **0.2 SSH key present.** `ls -l ~/.ssh/oracle` shows `-rw-------`. Missing? Ask Claude: "re-create
  ~/.ssh/oracle from the ORACLE_SSH_KEY_PRIVATE secret, mode 600, never print it".
- [ ] **0.3 Telegram, Backblaze, UptimeRobot, Spaceship auto-renew.** Do the Cowork prompt from the chat
  (or `OPERATOR_GUIDE.md` §4 by hand). Result: `opskit/owner/alerts.conf` and `opskit/owner/rclone.conf`
  exist (mode 600).
- [ ] **0.4 Email (for email alerts and care reports).** Brevo free account → SMTP key, or a Gmail app
  password. Add to `opskit/owner/alerts.conf` yourself (open it with `code opskit/owner/alerts.conf`):
  ```
  SMTP_URL=smtp://smtp-relay.brevo.com:587
  SMTP_USER=<your Brevo login>
  SMTP_PASSWORD=<SMTP key>
  SMTP_FROM=<an address you verified in Brevo>
  OWNER_EMAIL=<your email>
  ```
  (Gmail instead: `SMTP_URL=smtps://smtp.gmail.com:465`, user = your Gmail, password = app password.)
- [ ] **0.5 Your business details.** `cp opskit/templates/business.example.yaml opskit/owner/business.yaml`,
  edit name / support email / website, then `opskit validate opskit/owner/business.yaml` → `[ok]`.
- [ ] **0.6 Server gets the new settings and fixes.**
  `opskit host bootstrap oracle-mumbai` → every line `[ok]`, including `log rotation`.
  Then set the off-server target: in `opskit/clients/autonyx-practice/client.yaml` put
  `backup.remote: b2:<your bucket>/clients` (Claude can do it), and `opskit deploy autonyx-practice` →
  ends `[ok] deployed autonyx-practice`.

## Part 1 — Server and sites
- [ ] **1.1 Read-only server check.** `opskit host preflight oracle-mumbai` → ends
  `[ok] preflight of oracle-mumbai passed`; DNS lines for `status.autonyxai.shop` and
  `activepiece.autonyxai.shop` are `[ok]`.
- [ ] **1.2 All three sites open** in the browser with a padlock: builder, Kuma, `https://mychat.autonyxai.shop`.
- [ ] **1.3 Only web ports are open.** From the Codespace:
  `for p in 22 80 443 5432 6379 3001; do timeout 3 bash -c "</dev/tcp/129.154.225.22/$p" && echo "$p open" || echo "$p closed"; done`
  → 22, 80, 443 open; 5432, 6379, 3001 closed.
- [ ] **1.4 Root login refused.** `ssh -i ~/.ssh/oracle root@129.154.225.22 true` → "Permission denied"
  (or a message telling you to log in as ubuntu).
- [ ] **1.5 Memory.** `ssh -i ~/.ssh/oracle ubuntu@129.154.225.22 'free -h; sudo docker stats --no-stream'`
  → the "available" column well above 2 GB; no container near its limit.

## Part 2 — Alerts and monitoring
- [ ] **2.1 Test alert.**
  `ssh -i ~/.ssh/oracle ubuntu@129.154.225.22 /opt/opskit/agent/alert.sh --root /opt/opskit --client autonyx-practice --severity info --what "test" --action "none"`
  → a Telegram message (and an email if 0.4 is done) within a minute.
- [ ] **2.2 Kuma monitors.** `opskit monitor sync autonyx-practice` → `[ok]` lines; in Kuma (login from
  `opskit/hosts/oracle-mumbai.monitor/admin.env`) you see "autonyx-practice uptime" green and
  "autonyx-practice backup".
- [ ] **2.3 Down alert.** On the server: `ssh -i ~/.ssh/oracle ubuntu@129.154.225.22 sudo docker stop autonyx-practice-app-1`
  (name from `sudo docker ps`). Within ~2 minutes: Telegram "🔴 Down". Then
  `... sudo docker start autonyx-practice-app-1` → "🟢 Up" a minute later.
- [ ] **2.4 UptimeRobot** shows your 3 monitors Up.
- [ ] **2.5 Daily summary.** `ssh ... /opt/opskit/agent/digest.sh autonyx-practice --root /opt/opskit --now`
  → one Telegram summary message. (It also arrives every morning at 08:00 by itself.)

## Part 3 — Your builder (no client accounts needed)
Follow `docs/ACTIVEPIECES_GUIDE.md` §3.
- [ ] **3.1 First flow.** Schedule (every 5 min) → Code step → Test → Publish. After 5 minutes the Runs page
  shows a green run. Switch it off afterwards.
- [ ] **3.2 Failure alert.** New flow: Webhook trigger → Code step
  `export const code = async () => { throw new Error("test failure"); };` → Publish. Copy the
  **production** webhook URL from the trigger and open it in a browser tab (or
  `curl -X POST <url> -d '{}' -H 'content-type: application/json'`). Within 5 minutes: one Telegram
  alert naming the flow and the step, with a link that opens the failed run. Trigger it again: **no**
  second alert within 30 minutes (de-duplication). Delete the flow afterwards.

## Part 4 — Ready-made flows (needs an SMTP account for the flows, e.g. the one from 0.4)
- [ ] **4.1 Import.** `opskit flows import lead-capture-tables autonyx-practice --set OWNER_EMAIL=<you> --set BUSINESS_NAME="Autonyx" --set FROM_EMAIL=<sender>`
  → asks for the builder admin email + password (type them), prints the flow link and "SMTP" as the
  connection to create. A **Leads** table exists in the builder.
- [ ] **4.2 Connect and publish.** Open the flow → a step asks for a connection → create **SMTP** (your
  mail account's host/port/user/password) → pick it in both email steps → Publish.
- [ ] **4.3 Good lead.** Send `opskit/flows/lead-capture-tables/test/good-lead.json` to the production
  webhook URL (`curl -X POST <url> -H 'content-type: application/json' -d @opskit/flows/lead-capture-tables/test/good-lead.json`)
  after changing the email in a copy of that file to one of yours → a row in Leads, an email to you
  (owner), an auto-reply to the lead address.
- [ ] **4.4 Bad lead.** Same with `test/bad-email.json` → the run fails at "Check lead", no row, a Telegram
  alert within 5 minutes.
- [ ] **4.5 Second template.** `invoice-reminder-tables` the same way (README in its folder): one overdue
  invoice row with your email → a reminder email on the next scheduled run.

## Part 5 — Backups and restore
- [ ] **5.1 Backup now.** `opskit backup autonyx-practice` → ends with "complete (local + off-server)"
  (needs 0.6). In Backblaze you see a folder for today.
- [ ] **5.2 List.** `opskit backups autonyx-practice` → the backup on the server and off-server, sizes > 0.
- [ ] **5.3 Restore test.** `opskit restore-test autonyx-practice` → `[ok]` lines, your flows and the SMTP
  connection counted, "pass". (Runs a copy on the Codespace; takes a few minutes.)
- [ ] **5.4 Nightly backup.** Next morning: Kuma's "backup" monitor is green and `opskit backups
  autonyx-practice` shows a backup from ~02:30 server time.
- [ ] **5.5 Owner key copy.** Your password manager holds the 3-line owner key (without it no backup can
  be restored).

- [ ] **5.6 Your own settings backup.** `opskit registry backup --to b2:<your bucket>/registry` →
  "encrypted, checked with your private key" and "copied off this machine"; the file shows in Backblaze.
  Practice restore without touching your real folders:
  `OPSKIT_REGISTRY=$(mktemp -d) opskit registry restore latest` → "registry restored into /tmp/…".

## Part 6 — Safe upgrade (0.92.2 → 0.92.3)
- [ ] **6.1 Plan.** `opskit upgrade autonyx-practice --to 0.92.3 --plan` → "Plan only: nothing was
  changed", no `[fail]` (needs a complete backup < 26 h and a passed restore test ≤ 35 days: Part 5).
- [ ] **6.2 Upgrade.** `opskit upgrade autonyx-practice --to 0.92.3 --yes --now`, type the client id.
  → "staging … passed", short downtime, all checks `[ok]`, "upgraded to 0.92.3", a follow-up list.
  Kuma sent **no** down alert (monitor paused). Your flows and the Leads rows are still there.
- [ ] **6.3 After a restart, editing still works.** Edit and publish any flow right after the upgrade:
  it publishes within a minute (known issue to watch: publishing right after restarts was slow in CI).
- [ ] **6.4 Undo by hand.** `opskit upgrade autonyx-practice --rollback --yes` → "back on 0.92.2 (path:
  restore)"; builder works; then upgrade again (6.2) so you stay on 0.92.3.
- [ ] **6.5 mychat untouched** after all of this (opens, chats work).

## Part 7 — Handover pack and care report
- [ ] **7.1 Notes.** Create `opskit/clients/autonyx-practice/notes.yaml` (example in
  `docs/runbooks/handover-and-report.md`), `opskit validate` it.
- [ ] **7.2 Pack.** `opskit docs autonyx-practice` → open `opskit/clients/autonyx-practice/docs/handover.html`
  (VS Code: right-click → "Open with Live Server", or download it) → every active flow with "To pause
  it" steps, your business name, no passwords/keys/IDs. Print to PDF.
- [ ] **7.3 Hours and incident.** `opskit hours autonyx-practice add 1 "testing"` and
  `opskit incident autonyx-practice add "test incident"`.
- [ ] **7.4 Report.** `opskit report autonyx-practice --month $(date +%Y-%m)` → open
  `opskit/clients/autonyx-practice/reports/<month>.html`: run counts match the Runs page, availability
  from Kuma, backups, the upgrade, the incident, "1 of 1" hours.
- [ ] **7.5 Email.** Put your email in `report.recipients` of the client.yaml, then
  `opskit report autonyx-practice --month $(date +%Y-%m) --send` → in your inbox (check spam), formatted;
  sending again says "already sent".

## Part 8 — Watchdog and safety nets (optional, a bit technical)
- [ ] **8.1 Re-deploy is safe.** `opskit deploy autonyx-practice` twice → no container restarted the second
  time; mychat stays up.
- [ ] **8.2 Deploy refuses a bad DNS.** Temporarily set `domain: wrong.autonyxai.shop` in the client.yaml,
  `opskit deploy autonyx-practice` → stops with "has no A record yet", nothing touched; set it back.
- [ ] **8.3 Logs rotate.** `ssh ... sudo logrotate -d /etc/logrotate.d/opskit` → mentions
  `/opt/opskit/logs/*.log`, no errors.
- [ ] **8.4 Automated test suite.** In the Codespace: `opskit/bin/opskit selftest` (≈ 20–35 min) → ends
  `[ok] selftest passed`.

## When you're done
Send the Claude session a short summary: which boxes passed, which failed (with the exact `[fail]` line).
Then Phase 9 can be closed (costs, final verification report, your decision to keep the server).

## If something fails
| Symptom | First step |
|---|---|
| a `[fail]` line | copy that line and the command into Claude: "investigate read-only, propose a fix" |
| builder doesn't open | wait 5 min (watchdog); then `ssh ... sudo docker ps` and ask Claude |
| mychat broken | on the server: `sudo docker stop opskit-caddy && sudo docker start anythingllm-caddy` (old setup back), then ask Claude |
| no Telegram messages | check `opskit/owner/alerts.conf` has both lines, re-run `opskit deploy autonyx-practice`, then 2.1 |
| backup "local only" | `backup.remote` missing or Backblaze key wrong: `rclone --config opskit/owner/rclone.conf lsd b2:` must list your bucket |
