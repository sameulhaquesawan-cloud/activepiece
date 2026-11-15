# Launch plan — AutonyxAI, first income

Owner decisions (15 Nov 2026): brand **AutonyxAI**, domain `autonyxai.shop` (Spaceship). Markets: **international
(Upwork, Fiverr, LinkedIn) + Bangladesh local**. Owner already has a payment method. No job restrictions. Time: 3 h/day Sun–Thu,
6–8 h Fri + Sat (Bangladesh weekend). Owner has never used Activepieces → every step is also a lesson.

## Goal
First paid client, then the first monthly Care payment. Week 1 = our own staging stack treated as a real
client, demo assets, payment rail, profiles and first outreach. Realistic: first payment in weeks 1–3, first
monthly client in 1–2 months. Pricing and offer: `pricing.md`, `offer.md`; pilot price for the first 2
clients ≈ $299 setup + $79–99/month in exchange for a testimonial.

## Our environments (all on the Oracle host `oracle-mumbai`, `ubuntu@129.154.225.22`)
| Name | URL | Client id | State |
|---|---|---|---|
| Production / demo | `activepiece.autonyxai.shop` | `autonyx-practice` | live since 24 Oct 2026 (Phase 9 S5), Activepieces 0.92.2 |
| Staging | `staging-activepiece.autonyxai.shop` | `autonyx-staging` | to create this week (DNS record not yet made); client #0 = Threadline BD |
| Status | `status.autonyxai.shop` | — | Uptime Kuma, live since 24 Oct 2026 (S6) |

The host is shared with AnythingLLM, Dograh, crw (ADR-020, ASSUMPTIONS #32); one `opskit-caddy` edge holds 80/443.
T1 (15 Nov): 2 OCPU / 12 GB, 7.6 GiB free, **18 GB disk free** — one more stack fits, disk is the limit.
Staging is our own (no client data), so a second stack on this shared host is fine (ASSUMPTIONS #35).
Rule: every change (new Activepieces version, opskit change, flow) goes to staging first; prod is upgraded with
`opskit upgrade` (Phase 6) only after staging passed. First use: prod 0.92.2 → pinned 0.92.3.

Who runs what:
- **Cloud session** — code, tests, docs. Cannot SSH out (verified 15 Nov).
- **Codespace Claude** — the operator: holds the registry (`opskit/clients/`, `opskit/hosts/`, `opskit/owner/`)
  and the SSH key (secret `ORACLE_SSH_KEY_PRIVATE`). `docs/OPERATOR_GUIDE.md`, `docs/testing/TESTING_GUIDE.md`.
- **Local session** (owner's laptop) — Claude in Chrome. Protocol: `docs/CHROME_LOG.md`.

## Week 1 (15–21 Nov 2026)
| Day | Tech track | Business track | Owner learns |
|---|---|---|---|
| Sun 15 ✓ | T1 inventory, T3 Telegram bot | T2 payouts (owner already has a payment method) | basic words (`docs/ACTIVEPIECES_GUIDE.md`) |
| Mon 16 | T4: Codespace still there? registry backup; TESTING_GUIDE Part 0 (alerts.conf with Telegram, SMTP, Backblaze) | client brief for Threadline | tour of the live builder on prod |
| Tue 17 | staging: DNS record (approval) → `client new autonyx-staging` → `deploy` → `monitor sync` | proposal for Threadline; email on the domain | HTTPS, the encryption key, Kuma |
| Wed 18 | Threadline flows 1 + 9 on staging | Upwork + Fiverr profile drafts | build a flow yourself on staging |
| Thu 19 | flow 2 + incident drill; backup + `restore-test` on staging | website with the real brand | failed runs, alerts, restores |
| Fri 20 (long) | `opskit upgrade autonyx-practice` 0.92.2 → 0.92.3 after staging passed; Scenario B flows 1–2 on prod; demo video | profiles live; prospect list (40) | the staging → prod routine; demo out loud |
| Sat 21 (long) | Scenario B flow 3 (research helper) | first 50 messages | mock discovery call |

## Week 1 detail
**Role-play client #0: Threadline BD** (men's and women's clothing; COD, couriers, bKash, size exchanges). Scenario,
pain-point research, the 10 flows and their build order: `docs/practice/threadline-bd.md` (owner approved 15 Nov 2026).

| Day | Role-play step | Teach topics |
|---|---|---|
| Mon | client brief for Threadline (discovery answers) | flow, trigger, step, piece, connection, run; what a VPS, DNS record, firewall are |
| Tue | proposal for Threadline; onboarding: DNS, `client new`, `deploy` | SSH keys, Docker containers, HTTPS, `.env` and the encryption key |
| Wed | delivery: flows 1 (order intake) + 9 (review request) with test data | data selector, publish, run log, connections |
| Thu | flow 2 (COD confirmation); incident drill on it → alert → fix; backup + restore test | failed runs, alerts, why tested backups sell |
| Fri | handover call role-play; promote to prod | demo script, handover, Care plan |
| Sat | mock discovery call (agent plays a hard prospect); first outreach | objections, pricing talk, proposal |

**Practice niche (owner, 15 Nov 2026): online clothing shop** — Threadline BD on staging. International outreach still
targets small agencies too.

**Scenario B — AutonyxAI's own sales system on prod** (owner approved, 15 Nov 2026):
1. Site enquiry → table → Telegram alert.
2. Prospect pipeline table (status, next follow-up) → daily Telegram "follow up today" list (day 4 / day 10 rule
   from `outreach.md`). The owner builds this one as practice.
3. Prospect research helper: owner pastes a company URL or Upwork job text → page fetched → AI summary + likely
   automation needs + draft first message → table. Owner reviews and sends by hand. AI = owner's GLM key via the
   `openai-compatible` piece (ADR-013), stored only as an Activepieces connection on prod; public business data only.
No automated lead scraping (LinkedIn/Maps): ban risk, paid data, separate product idea.
Schedule: Fri = B1 + B2 on prod; Sat = B3, then used on the first 10 real prospects.

**Build this week (no new features):** fixes the staging deploy and the prod upgrade surface, the AutonyxAI site
(brand, pilot prices, contact form → prod webhook), our own prod flows. Each fix gets a test, per the repo rules.

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
1. Discovery call (questions in `outreach.md`) → proposal (`proposal-template.md`) → 50 % upfront (Payoneer/bank invoice or platform escrow).
2. Client opens their own server account (Hetzner/DigitalOcean) and adds us; adds one DNS record; connects their own apps.
3. `host bootstrap` → `client new` → `deploy` → backups and alerts on → `flows import` / build → test with their data.
4. Handover call (45 min) → invoice the rest → first Care month → testimonial + case study on the site.

## Prerequisites checklist
- [x] Payment method (owner has one; T2: Payoneer, Upwork, Fiverr work from BD; PayPal and Stripe do not)
- [ ] Email on the domain, Upwork + Fiverr + LinkedIn profiles
- [ ] Staging live, prod on 0.92.3, Threadline flows 1, 2, 9 tested; Telegram bot made (T3), wired into alerts.conf
- [ ] 3-minute demo video, site live with AutonyxAI branding and pilot prices
- [ ] Prospect sheet (columns in `outreach.md`)

## Risks
- The registry lives only in the Codespace: a deleted Codespace loses client settings and keys → T4 + registry backup first.
- Disk: 18 GB free on the shared host; watch it when staging is added.
- `.shop` reads less trustworthy to B2B buyers; a `.com` later is cheap.
- Bangladesh local clients cannot carry a dedicated €20 server; local = one-off builds or shared hosts (V2).
- Capacity: 3–5 simple clients max alongside the job; 12 h response.
- Outreach is always sent by the owner; no automated mass messaging (LinkedIn/Upwork bans).
