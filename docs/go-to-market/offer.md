# The offer (draft for owner sign-off)

**One line:** *We set up and run your own private automation system (an open-source Zapier alternative) on
your own server, watch it around the clock, back it up every night and fix it when something breaks — for a
fixed monthly fee and no per-task charges.*

Brand placeholder: **YourBrand** (`yourbrand.com`). Prices: see `pricing.md`. Every promise below is something
the kit does today (Phases 1–6); items marked *coming* are planned (Phase 7) and must not be sold as ready.

## Who it is for
- Small agencies and online stores that already pay for Zapier or Make and want lower, predictable costs
  without losing reliability.
- Service businesses (clinics, coaches, real estate) that need a few important automations to just work.
- EU businesses that want their data on an EU server (Germany/Finland) with a data-processing agreement.

## What the client gets

### 1. Setup (one-time)
| Item | What it means | How we do it |
|---|---|---|
| Your own server | one private server for you only, in the EU or the US | `opskit host bootstrap` (firewall, SSH keys only, automatic security updates) |
| Activepieces on your domain | e.g. `automations.yourcompany.com` with HTTPS | `opskit deploy` (Caddy, pinned version, health checks) |
| Nightly encrypted backups | database + settings, encrypted on your server before they are copied to a second location; kept 30 days | `agent/backup.sh` + off-server copy (Phase 3) |
| Tested restores | a backup is restored into a test copy every month to prove it works | `opskit restore-test` (Phase 3) |
| Monitoring and alerts | site checked every minute; failed runs reported within 5 minutes with a link; daily summary | Uptime Kuma + `agent/detect-failed-runs.sh`, `health.sh`, `digest.sh` (Phase 4) |
| Your alert channels | Telegram, Slack and/or email, with quiet hours | `alerts` in `client.yaml` |
| First flows | up to **3 flows** built for you, moved from Zapier/Make, or started from our ready-made flows: website lead capture, invoice reminders, review requests, AI email sorting, lead-ad alerts | `opskit flows import` (Phase 5); each one is tested with your own accounts during onboarding |
| Handover call | 45 minutes: how to log in, read runs, pause a flow, who to call | owner; written handover pack *coming* (Phase 7) |

### 2. Monthly hosting + care
| | **Care** | **Care Plus** |
|---|---|---|
| Server, backups, monitoring (all of the above) | ✓ | ✓ |
| Monthly restore test | ✓ | ✓ |
| Alerts to you **and** to us; we act on them | ✓ | ✓ |
| Fixes and small changes included | 1 hour / month | 3 hours / month |
| Response time (business days) | 12 h normal, 4 h if everything is down | same, handled first |
| Activepieces version updates (tried on a copy first, checked after, automatic rollback) | quarterly | monthly or on request |
| New flows | billed per flow or hourly | 1 small flow / month included in the hours |
| Monthly care report | *coming* (Phase 7) | *coming* (Phase 7) |

Weekends and holidays: best effort for "everything is down"; normal issues wait for the next business day.
Unused hours do not roll over.

### 3. Add-ons
- **Extra flows** — fixed price per flow (small / medium) or hourly.
- **Zapier/Make migration** — per flow, with a side-by-side test before switching off the old Zap
  (checklist: `zapier-migration-checklist.md`).
- **Extra hours** — at the hourly rate, billed in 15-minute steps.
- **WhatsApp alerts** — *later*: needs the client's own WhatsApp Business (Meta) setup.

## What the client provides
- Access to their domain's DNS (one record, we guide them).
- Their own accounts and API keys for the apps their flows use (Gmail, Shopify, CRM, AI providers…).
  **The client owns every credential**; they are stored encrypted on the client's server.
- A contact person and the chat/email where alerts should go.

## Not included (say it up front)
- Outages or changes of third-party apps (Shopify, Google, OpenAI…). We tell you fast and fix your side.
- Flows the client builds themselves — supported at the hourly rate.
- Features that are paid in Activepieces and not part of the free (Community) edition: several team members
  with roles, single sign-on, audit logs, custom branding of the builder, Git sync, several projects.
  One admin login per client.
- Legal responsibility for what the client's flows do with personal data (the client is the controller; we
  process on their instructions — EU: data-processing agreement in `eu/`).

## Leaving is easy (no lock-in)
- The software is open source (MIT). On request we hand over: all flows (exported), a full database backup,
  the settings file with the encryption key, and a short guide to run it elsewhere.
- After the contract ends we keep the client's data for **30 days** (in case they change their mind), then
  delete the server and its backups.

## Privacy in one paragraph (for the page and proposals)
Your automations run on a server that is yours alone, in the region you choose (EU or US). Your data stays on that
server, and the passwords of your connected apps are stored encrypted. Every night the server makes a
backup, encrypts it and copies it to private storage in the same region; only we hold the key that unlocks
it. We look at your data only when you ask us to fix something. Alerts contain
the flow name and a short error message, never your customers' full details. EU clients get a
data-processing agreement and a list of the services we use (`eu/`).

## Sales guard-rails (for the owner)
- Never promise 100 % uptime or "no data loss"; promise what is measured: checks every minute, alerts within
  5 minutes, nightly backups, monthly restore tests.
- Don't sell features marked *coming* as ready; offer them as "included when available".
- Price is for reliability and someone who fixes things, not for "cheaper software".
