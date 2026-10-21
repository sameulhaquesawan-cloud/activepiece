# Technical and organisational measures (Annex 2 of the DPA)

*Template — have it reviewed before use. Describes what the opskit setup does today (21 Oct 2026); each line
names where it is implemented so it can be checked. No certifications (ISO 27001, SOC 2) are claimed.*

## Separation
- One dedicated server per client; no client data is shared between clients (`opskit deploy`, ADR-014).
- Each client has its own database, cache, settings file and backups.

## Access control
- Server login with SSH keys only; password login and root login disabled (`agent/bootstrap.sh --harden-ssh`).
- Firewall allows only SSH (22) and web (80/443) (`agent/bootstrap.sh`, ufw).
- Database and cache are never reachable from the internet (no published ports; `templates/compose.yml.tmpl`).
- Monitoring scripts read the database with a separate read-only role that cannot change data, cannot read
  stored app connections and cannot log in over the network (`templates/readonly-role.sql`, checked by
  `opskit selftest`).
- Activepieces itself: one admin login per client, chosen by the client.

## Encryption
- In transit: HTTPS for the client's site (Caddy, automatic certificates); SSH for administration;
  backups are copied off the server over TLS (rclone).
- Stored app credentials (connections) are encrypted by Activepieces with the client's own encryption key
  (AES-256-CBC, `AP_ENCRYPTION_KEY`).
- The settings file containing that key is encrypted with the provider's public key before it is backed up
  (age encryption; the private key is kept offline by the provider, never on servers).
- The database backup (flow definitions, run history and the already-encrypted credentials) is encrypted
  with the provider's public key on the server, right after its readability check; no unencrypted copy is
  kept or sent off the server (`agent/backup.sh`, `db.dump.age`). Restores decrypt it on the provider's own
  computer (`opskit restore`).
- Server disks: as provided by the hosting company (not additionally encrypted by us).

## Availability and resilience
- Nightly database backup, checked for readability, copied to a second location; kept 14 days on the server
  and 30 days off the server (`agent/backup.sh`).
- Monthly test restore of the latest backup into a separate temporary system, including a check that all
  stored credentials can still be decrypted (`opskit restore-test`).
- Monitoring: the site is checked every minute from a separate monitoring server; a missing nightly backup
  raises an alert after 26 hours; failed runs, disk, memory, container and certificate problems raise alerts
  (`agent/detect-failed-runs.sh`, `agent/health.sh`, Uptime Kuma).
- Automatic operating-system security updates (`unattended-upgrades`).
- Software version pinned; updates applied after a backup.

## Data minimisation in alerts
- Alerts contain the client name, the flow name, the failing step and an error excerpt of at most 300
  characters. The excerpt comes from the error message and may in rare cases contain a fragment of the data
  being processed (for example an invalid email address).

## Deletion
- At the end of the contract the server and its backups are deleted after a 30-day grace period
  (`opskit client offboard`, then `--purge` after the retention period); off-server backups expire after
  30 days.

## Organisational
- Access to client systems only by the provider [and named staff]; support access only when needed to
  operate or fix the system or on the client's request.
- Secrets are never stored in the code repository or sent by chat/email.
- Personal data breaches are reported to the client without undue delay (see DPA §7).
