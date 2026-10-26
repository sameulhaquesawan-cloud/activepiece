# 3-minute demo (script + preparation)

Goal: in 3 minutes a prospect sees that (1) their automations run on their own system, (2) when something
fails they hear about it in minutes with a link, (3) backups are real and tested, (4) the price is simple.
Everything shown exists today (Phases 1–4). Record one good run as a video (e.g. Loom) as the fallback for
slow networks, and send that video after cold emails.

## The script (spoken text in quotes, actions in brackets)

**0:00 – 0:20 · Hook**
"Most small teams pay Zapier or Make per task and find out about broken automations from an angry customer.
I'll show you the alternative in three minutes: your own system, watched around the clock."
[Screen: the one-page site, hero section.]

**0:20 – 0:55 · It's your own builder**
"This is the automation builder, running on a private server for one client only, on their own domain."
[Open the Activepieces builder → Flows list → open "Lead capture". Point at the trigger and the steps.]
"Same idea as Zapier — triggers, steps, branches, code — and hundreds of app connectors. No per-task fees."
Fallback: `docs/phase0-screenshots/` (builder screenshot).

**0:55 – 1:45 · Something breaks — you know in minutes**
"Now let's break something on purpose."
[Click *Test* / send the prepared webhook for the "Demo — deliberate failure" flow → the run fails.]
"Every five minutes the server checks for failed runs. Let me trigger that check now instead of waiting."
[Terminal: `<root>/agent/detect-failed-runs.sh <id> --root <root>` → phone: Telegram message arrives.]
"Here's the alert: which flow, which step, the error, and a link straight to the failed run. One alert per
flow — if it fails fifty times, you get one message, not fifty."
[Open the link / the Runs page → the failed step is highlighted.]
Fallback: screenshot of a real Telegram alert taken during preparation.

**1:45 – 2:20 · Backups that are actually tested**
"Every night the system backs itself up, encrypts the backup and copies it off the server. Once a month we
prove it
works: we restore the backup into a throwaway copy and check that every flow and every saved connection is
there."
[Terminal: `opskit backups <id>` → list with sizes and off-server status; then show the last line of
`opskit/clients/<id>/restore-tests.jsonl`: `"result":"pass"` with flow and connection counts.]
Fallback: show the prepared output from the preparation step (copied into a text file).

**2:20 – 2:40 · The daily summary**
"Each morning you get one message: last backup, runs and failures in the last 24 hours, anything we're
watching." [Phone: the digest message from the preparation run.]

**2:40 – 3:00 · Price and next step**
"Setup is €690, then €159 a month for hosting, backups, monitoring and an hour of fixes — no per-task fees,
your data on your server, and you can take it all with you if you ever leave. Shall we look at what you run
today?"
[Screen: pricing section of the site.]

US version: $749 setup, $179 per month. A sample care report and handover pack may be shown (generate them for your demo client with
`opskit report` / `opskit docs`; never a real client's). Ready-made flows may be shown (`opskit/flows/`),
connected to your own test accounts only.

## Preparation

### Your demo server today (free, Oracle)
You already have one: `https://activepiece.autonyxai.shop` (client id `autonyx-practice`, server
`oracle-mumbai`, user `ubuntu`, opskit root `/opt/opskit`). Use Option A's steps 1–5 with these names:
- builder: `https://activepiece.autonyxai.shop`; uptime page for the "watched around the clock" part:
  `https://status.autonyxai.shop`;
- detector on demand: `ssh -i ~/.ssh/oracle ubuntu@129.154.225.22 /opt/opskit/agent/detect-failed-runs.sh autonyx-practice --root /opt/opskit`;
- fresh summary: `ssh -i ~/.ssh/oracle ubuntu@129.154.225.22 /opt/opskit/agent/digest.sh autonyx-practice --root /opt/opskit --now`;
- backup proof: `opskit/bin/opskit backups autonyx-practice` and `opskit/bin/opskit restore-test autonyx-practice`;
- a sample report/pack: `opskit/bin/opskit report autonyx-practice` and `opskit/bin/opskit docs autonyx-practice`.
Needs first: Telegram in `opskit/owner/alerts.conf` and Backblaze (otherwise backups show "local only").
The server is in Mumbai: for EU prospects say "your server would be in the EU"; the demo one is ours.

### Option A — a real demo server (recommended, ≈ €20/month)
The best demo is the real thing: a small server at `demo.yourbrand.com`, deployed with opskit exactly like a
client. It also rehearses the first client install. Follow `docs/runbooks/deploy-client.md` (server + client
`demo`), `docs/runbooks/backup-restore.md` and `docs/runbooks/monitoring.md` (section A: your Telegram bot).
Then, once:
1. In the builder at `https://demo.yourbrand.com`, build two flows and switch them *On*:
   "Lead capture" (Webhook trigger → Code step returning the lead) and "Demo — deliberate failure"
   (Webhook trigger → Code step `throw new Error("Customer email is missing")`).
2. `opskit backup demo`, then `opskit restore-test demo` → gives the `restore-tests.jsonl` line you show.
3. On the server the detector runs every 5 minutes by itself; for the call you can run it on demand:
   `ssh ops@<server> /opt/opskit/agent/detect-failed-runs.sh demo --root /opt/opskit`.
4. The daily summary arrives every morning; for a fresh one:
   `ssh ops@<server> /opt/opskit/agent/digest.sh demo --root /opt/opskit --now`.
5. Dry run with a timer; take screenshots of the Telegram alert and digest for the fallbacks.

### Option B — no server yet: Codespace + recorded clips
The practice stacks in a Codespace answer only on `*.localhost` names, so the builder cannot be opened from
your laptop's browser. Use the Phase 0 explore stack (`opskit/bin/explore-stack up`, port 8080, see
`docs/HANDOFF.md`) for the builder part (step 0:20 and the failing run), and show the alert, backup and
summary parts from a kept practice stack in the terminal:
1. `opskit/bin/dev-env`, then `opskit/bin/opskit selftest --keep`; note `OPSKIT_REGISTRY=<dir>` and the client
   id `selftest-xxxxxx` from the last lines.
2. Telegram: write `TELEGRAM_BOT_TOKEN=…` and `TELEGRAM_CHAT_ID=…` into `<dir>/host-root/agent/alerts.conf`
   with your editor (never paste the token into chat). Test:
   `<dir>/host-root/agent/alert.sh --root <dir>/host-root --client <id> --severity info --what "Demo test" --action "none"`.
3. Restore test: `OPSKIT_REGISTRY=<dir> OPSKIT_OWNER_AGE_KEY=<dir>/owner.key opskit/bin/opskit restore-test <id>`.
4. Summary: `<dir>/host-root/agent/digest.sh <id> --root <dir>/host-root --now`.
5. The selftest itself proves a failing flow gives exactly one alert; record that terminal output.
6. Afterwards remove the stack with the command printed by `selftest --keep`; stop the Codespace.

## Questions prospects ask (short answers)
- *"What if your server goes down?"* — "A separate monitoring server checks yours every minute and alerts
  us; backups live in a second location; we can restore onto a new server."
- *"Can I still edit flows myself?"* — "Yes, it's your builder. We fix what breaks; your own edits are
  supported at the hourly rate."
- *"What about my Zapier zaps?"* — "We rebuild them one by one and run both side by side before switching
  the old one off (migration checklist)."
- *"Where is my data?"* — "On your server, EU or US, with backups in a private second location; EU clients get a data-processing
  agreement."
