# Runbook — upgrade a client to a new Activepieces release

Commands run on your machine (Codespace, WSL, cloud AI session) from the repo folder. The tick list
for each upgrade is `docs/runbooks/upgrade-checklist.md`. Design: ADR-018 in `docs/DECISIONS.md`.

## When to upgrade
- Only to a release our fork is synced to and CI has run (`docs/UPSTREAM_SYNC.md`).
- Security releases: within the week. Others: when a client needs something, or every couple of months.
- Never on a Friday evening; inside the client's quiet hours (`alerts.quiet_hours` in client.yaml).

## What you need
- The owner age key pair on this machine (private key: `OPSKIT_OWNER_AGE_KEY` or
  `~/.config/opskit/owner.key`; public key: `opskit/keys/owner.age.pub`).
- Internet for pieces, Docker, about 5 GB free disk here.
- A fresh backup (last night's counts) and a passed restore test from the last 35 days
  (`opskit restore-test <id>`).

## 1. Plan (changes nothing)
```bash
opskit/bin/opskit upgrade acme --to 0.93.0 --plan
```
Read every line. `[fail]` lines are gates: fix them first (the line says how). The breaking-change list
comes from Activepieces' own notes: for each item ask "does acme use this?" and note what to test.
"cannot be undone by Activepieces" means a rollback has to restore the database copy taken right before
the switch, so runs and edits after the switch would be lost: keep the window short.

## 2. Upgrade
```bash
opskit/bin/opskit upgrade acme --to 0.93.0 --yes
```
Type the client id when asked. Outside the client's quiet hours it refuses; add `--now` when you agreed a
time with the client. What happens, in order (each step prints `[ok]`/`[fail]`):
1. Gates again, lock (no second upgrade, nightly backup waits), image pulled here and on the server.
2. **Staging** (3–5 minutes): a fresh backup is restored into a temporary copy on this machine running
   the new version; all checks run on the copy, including a test webhook flow and a 1-minute schedule.
   The copy is deleted. If anything fails here, the client was never touched.
3. **Switch** (the client's downtime, usually under a minute): Uptime Kuma monitor paused, app stopped,
   encrypted database copy taken, new version started.
4. **Checks** on the client: health, containers, worker, HTTPS, database schema, counts, enabled flows,
   connections decrypt, no engine errors.
5. **Follow-ups**: the output ends with a numbered list (re-install our AI piece, templates to re-pin,
   what to test). Again any time: `opskit/bin/opskit upgrade acme --after`.

## 3. Afterwards
Work through the follow-ups and the "After" part of the checklist, then tell the client it is done and
what changed for them (one or two sentences, no version numbers unless they ask).

## If it rolled back
Any failure after the app was stopped rolls back on its own: the database copy from right before the
switch is restored, the old version starts, the checks run again, and you get one critical alert (owner
only). The client lost at most what happened during the few minutes of the attempt. Then:
1. Read the attempt's logs: `opskit/clients/<id>/upgrades/<time>/` (`state.json`, `stage-*.log`).
2. Do not retry the same day. Fix the cause or wait for the next release, then plan again.
3. Tell the client only if they noticed the downtime.

The alert says **the rollback failed** (rare): the client may be down. Run
`opskit/bin/opskit upgrade acme --rollback --yes`; if that fails too, restore the latest backup
(`docs/runbooks/backup-restore.md`).

## Undo a finished upgrade by hand
Within 7 days: `opskit/bin/opskit upgrade acme --rollback --yes` (type the id). Everything since the switch
is lost, so prefer fixing forward after the first hours.

## Interrupted (laptop closed, connection lost)
`opskit/bin/opskit upgrade acme --to <x.y.z> --plan` names the next safe step: `--resume --yes` or
`--unlock` before the switch, `--rollback --yes` after it.

## History
Every attempt is in client.yaml `history` (`upgraded`, `upgrade_failed`, `rolled_back`, with duration and
downtime) and in `opskit/clients/<id>/upgrades/`. The monthly care report reads it.
