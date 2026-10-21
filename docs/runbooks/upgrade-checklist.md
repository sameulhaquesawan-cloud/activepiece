# Upgrade checklist (before every client upgrade)

Print it with `opskit upgrade <id> --to <x.y.z> --plan`; tick it in your notes.

## Before
- [ ] The fork is synced to the target release and CI is green on it (`docs/UPSTREAM_SYNC.md`); never
      upgrade a client to a release our CI has not run.
- [ ] Read the breaking changes the plan prints and the release notes
      (https://github.com/activepieces/activepieces/releases/tag/<x.y.z>). For each item: does the client
      use that piece/feature? Write down what to test afterwards.
- [ ] The plan's gates are all `[ok]` (fresh backup with off-server copy, passed restore test, disk,
      memory).
- [ ] If the plan warns that migrations "cannot be undone": a rollback brings back the copy taken right
      before the switch, so runs and edits made after the switch would be lost. Keep the window short.
- [ ] Choose a time in the client's quiet hours; tell the client the 1–3 minutes downtime if they have
      webhooks from outside (forms, shops).
- [ ] No big import or migration running in the client's builder right now.
- [ ] Run it: `opskit upgrade <id> --to <x.y.z> --yes` and type the client id. Outside the client's
      quiet hours (`alerts.quiet_hours`, client time zone) it refuses unless you add `--now`.

## After
- [ ] The upgrade output ends with `[ok]` for every production smoke check.
- [ ] Open the builder: log in, open two flows, look at the last runs.
- [ ] Test what the breaking-change notes touched (your list from "Before").
- [ ] `opskit flows check-pieces` if templates are in use; re-pin templates if the catalog changed.
- [ ] Watch the failed-run alerts for the next day.
- [ ] Tell the client it is done (and what changed for them, if anything).

## If it was interrupted (laptop closed, connection lost)
Run `opskit upgrade <id> --to <x.y.z> --plan`: it names the next safe action. Before the switch:
`opskit upgrade <id> --resume` (or `--unlock` to give up; nothing changed on the client). After the
switch started: `opskit upgrade <id> --rollback`. Nightly backups skip while an upgrade is running (at
most 12 h).

## If it rolled back
The tool restores the database copy taken right before the switch and starts the old version. The
alert (owner only) says what failed. Changed your mind within 7 days of a finished upgrade?
`opskit upgrade <id> --rollback --yes` does the same by hand (everything since the switch is lost). Do not retry the same day: read the logs in
`opskit/clients/<id>/upgrades/<time>/`, fix or wait for a newer release, then plan again.
