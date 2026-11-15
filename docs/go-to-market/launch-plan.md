# Launch plan — AutonyxAI, first income

Owner decisions (15 Nov 2026): brand **AutonyxAI**, domain `autonyxai.shop` (Spaceship). Markets: **international
(Upwork, Fiverr, LinkedIn) + Bangladesh local**. No Payoneer yet. No job restrictions. Time: 3 h/day Sun–Thu,
6–8 h Fri + Sat (Bangladesh weekend). Owner has never used Activepieces → every step is also a lesson.

## Goal
First paid client, then the first monthly Care payment. Week 1 = our own staging stack treated as a real
client, demo assets, payment rail, profiles and first outreach. Realistic: first payment in weeks 1–3, first
monthly client in 1–2 months. Pricing and offer: `pricing.md`, `offer.md`; pilot price for the first 2
clients ≈ $299 setup + $79–99/month in exchange for a testimonial.

## Our environments
| Name | URL | Client id | Purpose |
|---|---|---|---|
| Staging | `staging-activepiece.autonyxai.shop` | `autonyx-staging` | treated as client #0: every change (new pinned version, opskit change, flow template) is tested here first |
| Production / demo | `activepiece.autonyxai.shop` | `autonyx-prod` | our own instance: live demo for prospects, our own business automations (lead alerts, invoice reminders) |
| Status | `status.autonyxai.shop` | — | Uptime Kuma (owner monitoring host) |

Host: the owner's Oracle Cloud server (also runs AnythingLLM). Both stacks on one host is a **shared host**,
which SPEC defers until after the first paying client — allowed here only because both stacks are ours (no client
data); owner approval recorded in `docs/ASSUMPTIONS.md`. Facts still to check (T1): CPU type/RAM, free ports
80/443 (AnythingLLM may hold them), Oracle firewall rules. Activepieces 0.92.3 image ships amd64 + arm64
(verified 15 Nov 2026 with `docker manifest inspect`).

Who runs what: the cloud session writes code/docs and cannot SSH out (port 22 blocked, verified). The **local
session** (owner's Windows laptop) is the operator: Chrome work, and opskit commands inside WSL2 Ubuntu.
Registry with secrets (`opskit/clients/`, `opskit/hosts/`) lives only on the laptop. Protocol: `docs/CHROME_LOG.md`.

## Week 1 (15–21 Nov 2026)
| Day | Tech track (staging = client #0) | Business track | Owner learns |
|---|---|---|---|
| Sun 15 | T1 read-only inventory of server, Oracle firewall, DNS | T2 payout research; start Payoneer signup | what a flow, trigger, step, connection, run are (`docs/learn/activepieces-101.md`) |
| Mon 16 | WSL2 + `opskit/bin/dev-env` on laptop; `host bootstrap` on Oracle (with approval) | Payoneer documents | watch the server setup, read the step summaries |
| Tue 17 | DNS records; `client new autonyx-staging`; `deploy`; Uptime Kuma at `status.` | brand basics: email on the domain, LinkedIn headline | first login, tour of the builder |
| Wed 18 | import 3 templates into staging; run with real Gmail/SMTP; backup + restore-test | Upwork + Fiverr profile drafts | build a 3-step flow yourself in staging |
| Thu 19 | fix what the real deploy broke; record findings | website with real brand on Cloudflare Pages | read run logs, find a failed step, re-run it |
| Fri 20 (long) | `autonyx-prod` deploy; promote templates staging → prod; record 3-min demo video | profiles live; prospect list (40 names) | do the demo out loud twice |
| Sat 21 (long) | our own lead-capture flow live on prod (site form → table → Telegram) | 20 warm messages, 10 Upwork proposals, 20 LinkedIn messages | run a mock discovery call with the agent |

Week 2+: 10 proposals/day on Upwork, follow-ups (day 4, day 10), discovery calls, proposals within 2 days.

## Client path (same steps as staging, for real)
1. Discovery call (questions in `outreach.md`) → proposal (`proposal-template.md`) → 50 % upfront (Payoneer invoice or platform escrow).
2. Client opens their own server account (Hetzner/DigitalOcean) and adds us; adds one DNS record; connects their own apps.
3. `host bootstrap` → `client new` → `deploy` → backups and alerts on → `flows import` / build → test with their data.
4. Handover call (45 min) → invoice the rest → first Care month → testimonial + case study on the site.

## Prerequisites checklist
- [ ] Payoneer verified (BD payouts; Stripe, PayPal and Wise do not serve BD residents — T2 confirms)
- [ ] Email on the domain, Upwork + Fiverr + LinkedIn profiles
- [ ] Staging + prod + status live, 3 templates tested with real accounts, Telegram alert bot
- [ ] 3-minute demo video, site live with AutonyxAI branding and pilot prices
- [ ] Prospect sheet (columns in `outreach.md`)

## Risks
- First real-internet deploy will surface bugs → do it on staging, log them in PROGRESS Known issues.
- `.shop` reads less trustworthy to B2B buyers; a `.com` later is cheap.
- Bangladesh local clients cannot carry a dedicated €20 server; local = one-off builds or shared hosts (V2).
- Capacity: 3–5 simple clients max alongside the job; 12 h response.
- Outreach is always sent by the owner; no automated mass messaging (LinkedIn/Upwork bans).
