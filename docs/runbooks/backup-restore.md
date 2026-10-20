# Runbook — backups, restore and the monthly restore test

Commands run on your machine (Codespace, WSL, cloud AI session) unless a step says "on the server".
Design and reasons: ADR-015 in `docs/DECISIONS.md`.

## How backups work (nothing to do day to day)
- Every night (default 02:30 server time, `backup.schedule` in `client.yaml`) the server runs
  `<root>/agent/backup.sh <id>`: database dump (`pg_dump -Fc`, checked with `pg_restore --list`),
  the client's `.env` encrypted to **your** age public key (`env.age`), a copy of `compose.yml` and
  `status.json`, in `<root>/backups/<id>/<UTC time>/`.
- Then it copies that folder off the server with rclone (`backup.remote`) and checks the sizes.
- Kept: 14 days on the server, 30 days off-server (`backup.retention_days`); the newest good backup
  is never deleted.
- Success → heartbeat to the client's Uptime Kuma push URL (`backup.heartbeat_url`).
  Failure → alert to you (and the client's channels): `[CRITICAL]` when there is no usable backup,
  `[WARN]` when it exists only on the server.
- Redis is not backed up on purpose (ASSUMPTIONS #8): schedules and delays are rebuilt from the database.

## One-time setup for you (the owner)

### A. Your age key (about 5 minutes, once for all clients)
Your key pair locks every client's secrets file. The **public** half goes into the repo and onto
servers; the **private** half never leaves you. Without it no backup can be restored.
1. In your Linux terminal (Codespace or WSL): `age-keygen -o ~/owner.key`
   It prints `Public key: age1…`.
2. Save the public key in the repo: `age-keygen -y ~/owner.key > opskit/keys/owner.age.pub`, then
   commit and push that one file (it is safe to share).
3. Open `~/owner.key` (`cat ~/owner.key`), copy all three lines into your password manager as a
   secure note named "opskit age private key". Make a second copy (printed paper or a USB stick in
   a drawer).
4. Keep a working copy where opskit looks for it:
   `mkdir -p ~/.config/opskit && mv ~/owner.key ~/.config/opskit/owner.key && chmod 600 ~/.config/opskit/owner.key`
5. Re-run `opskit deploy <id>` for each client so servers get the new public key.
If you ever lose the private key: make a new pair (steps 1–5) and run a backup for every client
right away — older backups stay locked forever.

### B. Off-server storage
Pick one rclone remote (Backblaze B2 recommended, 10 GB free). On your machine:
`rclone config --config opskit/owner/rclone.conf` → create a remote (e.g. `b2`). Then in each
`client.yaml`: `backup.remote: b2:<bucket>/clients`. `opskit deploy` copies the rclone config to
the server (mode 600). `opskit/owner/` is git-ignored.

### C. Alerts
`opskit/owner/alerts.conf` (git-ignored, mode 600):
```
TELEGRAM_BOT_TOKEN=<from @BotFather>
TELEGRAM_CHAT_ID=<your chat id>
```
`opskit deploy` copies it to each server. Without it, failures are only written to the server log.

## Everyday commands
| Task | Command |
|---|---|
| Back up now | `opskit backup <id>` (exit 0 complete, 2 server only, 1 failed) |
| List backups | `opskit backups <id>` |
| Restore a copy next to the client | `opskit restore <id> --target <id>-copy --domain copy.example.com` |
| Restore a specific backup | add `--from 20261020T023000Z` (name from `opskit backups`) |
| Restore onto another server | add `--host <other host>` (backup comes from the old server, or off-server if it is gone) |
| Replace the client's data with a backup | `opskit restore <id> --target <id> --overwrite --yes` and type the client id |
| Monthly restore test | `opskit restore-test <id>` or `opskit restore-test --all` |

A copy (`--target <new id>`) is a full client in the registry with no backup schedule. Remove it
when you are done: `opskit client offboard <copy> --yes`, and the next day
`opskit client offboard <copy> --purge --yes` (copies keep data for 1 day only).

A restore always uses the client's **original** secrets (decrypted from `env.age` with your private
key), so saved connections keep working. It finishes with the normal deploy checks (health, worker,
HTTPS) and checks that every saved connection decrypts.

## Monthly restore test
`opskit restore-test --all` (on the 1st of the month, or set a reminder) restores each deployed
client's latest backup into a temporary stack **on your machine** (needs Docker; about 1 minute
per client), runs the checks, deletes the temporary stack and appends one line per client to
`opskit/clients/<id>/restore-tests.jsonl` (`result`, backup name, flow/connection/run counts). The
care report shows the latest line. The client's server is not touched.
Optional automation on a machine that is always on (WSL with cron):
`0 9 1 * * cd ~/activepiece && opskit/bin/opskit restore-test --all >> ~/opskit-restore-test.log 2>&1`

## Disaster: the server is gone
1. Create and bootstrap a new server (`docs/runbooks/deploy-client.md` step 1), e.g. host `acme-vps2`.
2. Point the client's domain at the new server's IP and wait until it resolves (the restore ends
   with an HTTPS check).
3. `opskit restore acme --target acme --host acme-vps2 --overwrite --yes` (type `acme`).
   The latest backup is fetched from the off-server remote; `client.yaml` now points at the new host.
   If only the HTTPS check failed (DNS still moving), re-run `opskit deploy acme` later.

## When something fails
| Message | Meaning / first action |
|---|---|
| `owner age private key not found` | put the key at `~/.config/opskit/owner.key` (section A step 4) or set `OPSKIT_OWNER_AGE_KEY` |
| `env.age does not decrypt` | wrong private key; the backup was made with another public key |
| `no backup 'latest'` | no backup yet (`opskit backup <id>`) or the remote is not configured |
| `pg_restore failed` | the dump is damaged: try the previous backup with `--from` |
| `stored connections do not decrypt` | the restored `AP_ENCRYPTION_KEY` does not match the data — never use that stack; report it |
| `[WARN] … local only` alert | off-server copy failed: check `opskit backups <id>` and the rclone remote |
