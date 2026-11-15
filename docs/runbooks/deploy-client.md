# Runbook — onboard a client on a dedicated server

Any Linux machine with the repo (Codespace, WSL, cloud AI session). Run `opskit/bin/opskit doctor` first.

## 1. Server (once per server)
1. Buy an Ubuntu 24.04 VPS (≥ 2 vCPU / 4 GB). In the provider's create-server form, paste the output of
   `opskit host cloud-init --user ops --key ~/.ssh/id_ed25519.pub` into the "cloud config" / "user data"
   box: it creates the non-root user `ops` with your SSH key and **passwordless sudo**, and turns off root
   and password login. (Server already exists? Create that user by hand.)
2. Point the client's domain (e.g. `auto.acme.com`) at the server's IP (DNS A record).
3. Describe the server in `opskit/hosts/<host>.yaml` (git-ignored):
   ```yaml
   host_id: acme-vps
   ip: 203.0.113.10
   ssh_user: ops
   mode: dedicated
   cpus: 2
   ram_gb: 4
   edge: { acme_email: you@yourbrand.com }
   ```
   `opskit validate opskit/hosts/acme-vps.yaml`
4. `opskit host preflight acme-vps` (read-only: SSH, sudo, Ubuntu 24.04, memory, disk, IPv6, outbound
   HTTPS, and every client domain's A record). Fix any `[fail]`.
5. `opskit host bootstrap acme-vps --dry-run` (read the plan), then `opskit host bootstrap acme-vps`.
   If it reports the SSH check: confirm you can log in with your key, then re-run with `--harden-ssh`.
   Server shared with another app (its own Docker and web server): see ADR-020 (`firewall: keep`,
   `edge.join_networks`, `swap`).

## 2. Client
1. `opskit client new acme --domain auto.acme.com --host acme-vps --contact owner@acme.com --name "Acme Dental" --timezone Europe/London`
2. Adjust `opskit/clients/acme/client.yaml` if needed (worker replicas, memory, alert channels), then `opskit validate opskit/clients/acme/client.yaml`.
3. `opskit deploy acme` — prints one `[ok]` line per step; ends with `[ok] deployed acme`.
4. Open `https://auto.acme.com`, create the client's admin account.
5. Backups: `opskit deploy` installs the nightly backup (database + `.env` encrypted to your age key, off-server copy). Run `opskit backup acme` once now and check `opskit backups acme`. See `docs/runbooks/backup-restore.md`.

## Everyday
- Update after editing `client.yaml`: `opskit deploy acme` (safe to re-run; unchanged stacks are not restarted).
- Pause / resume: `opskit client pause acme` / `opskit client resume acme`.
- Offboard: `opskit backup acme` + flow export → `opskit client offboard acme --yes` (type `acme`). After `offboard_retention_days` (30): `opskit client offboard acme --purge --yes`.

## When something fails
| Message | Meaning / first action |
|---|---|
| `DNS: A record of … points at …` / `has no A record yet` | deploy stopped before touching the server: fix the DNS record, wait a few minutes, re-run. Behind a proxy such as Cloudflare: `OPSKIT_SKIP_DNS_CHECK=1 opskit deploy <id>` |
| `HTTPS health check failed` | DNS not pointing at the server yet, or port 80/443 blocked — check DNS, wait, re-run deploy |
| `app not healthy after …` | `ssh ops@<ip> docker compose -p acme logs app` |
| `no worker poll seen` | `ssh ops@<ip> docker compose -p acme logs worker` |
| `edge … not running` | `opskit host bootstrap <host>` |
| `refusing to regenerate secrets` | restore `secrets.env` from escrow — never delete it |

## Practice without a server
`opskit selftest` runs the whole flow on this machine and cleans up. For a hands-on practice host, copy `opskit/tests/fixtures/hosts/local-practice.yaml` to `opskit/hosts/`, set `opskit_root` to a folder you own, then use the same commands with `--host local-practice` and a `*.localhost` domain.
