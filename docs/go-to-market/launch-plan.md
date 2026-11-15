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

## Week 1 detail
**Role-play client #0:** staging plays *GreenCart BD*, a fictional small online shop in Dhaka (website form,
B2B invoices, order-paid webhook). Every client document is filled for it as if real: brief from the discovery
questions, proposal, `client.yaml`, handover. Templates on staging: `lead-capture-tables`,
`invoice-reminder-tables`, `review-request` (all SMTP, no Google) + one flow the owner builds (webhook → Telegram).
Skipped: `lead-ad-alert` (needs a Meta app), Google Sheets variants, `ai-email-sorter` (optional Sat, needs an AI key).
SMTP account for tests: Gmail app password (needs 2-step verification) or a free SMTP relay — decided on Wed.

| Day | Role-play step | Teach topics |
|---|---|---|
| Sun | client brief for GreenCart (discovery answers) | flow, trigger, step, piece, connection, run; what a VPS, DNS record, firewall are |
| Mon | proposal for GreenCart; server preparation (`host bootstrap`) | SSH keys, Docker containers, why each client gets its own stack |
| Tue | onboarding: DNS, `client new`, `deploy` | HTTPS/Caddy, `.env` and the encryption key, Uptime Kuma |
| Wed | delivery: import + test the 3 templates with test data | data selector, publish, run log, connections |
| Thu | incident drill: break a flow → alert → fix; backup + restore test | failed runs, alerts, why tested backups sell |
| Fri | handover call role-play; promote to prod | demo script, handover, Care plan |
| Sat | mock discovery call (agent plays a hard prospect); first outreach | objections, pricing talk, proposal |

**Build this week (no new features):** fixes the first real deploy needs (likely: sharing 80/443 with AnythingLLM,
Oracle's default iptables rules), the AutonyxAI site (brand, pilot prices, contact form → prod webhook), the
Telegram alert bot, our own prod lead flow. Each fix gets a test, per the repo rules.

**Branches:** every cloud session works on its own `claude/...` branch (named in PROGRESS). At the end of each
working day the owner merges it into `main` by PR, so a new session or account always starts from an
up-to-date `main`. Staging is deployed and tested first; prod only gets what passed on staging.

## Week 2–3 (22 Nov – 5 Dec) — to the first dollar
| Week | Daily (3 h) | Target by end of week |
|---|---|---|
| 2 | 1 h outreach (10 Upwork proposals, 10 LinkedIn/email, 5 local BD contacts), 1 h follow-ups + calls, 1 h practice/fixes on staging | 150 contacts total, 10 replies, 3–5 discovery calls, 1–2 proposals sent |
| 3 | same; plus deliver whatever was won | first payment (one-off build or pilot setup 50 % upfront) |

Fastest first dollar, in order of likelihood: (1) warm/local contact, one-off build (e.g. Facebook lead → sheet/table →
Telegram), paid by bKash/bank; (2) small fixed-price Upwork/Fiverr job ($50–300); (3) international pilot
(setup + Care). Funnel rule of thumb for a new seller: ~100–150 contacts → ~10 replies → 3–5 calls → 1 yes.
If week 2 gets < 3 replies: change the message (sharper outcome, one niche), not the product.

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
