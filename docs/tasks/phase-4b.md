# Phase 4b — Go to market (owner-led, agent assists)

SPEC: Section 17 Phase 4b, Section 1 (buyers, positioning), Section 2 (scope, V2 list), Section 18 (pricing check, paid-only features), Appendix B #1, #2, #4, Appendix C A4/A5.
**Accept (SPEC 17):** owner signs off offer, pricing sheet, page draft and demo script in `docs/go-to-market/`.
Phases 1–4 are the minimum sellable service. The agent drafts; the owner decides and signs off. Phases 5–7 continue after this phase while the owner looks for clients.

## Open questions for the owner (recommended defaults in brackets — "ok" accepts them)
- **Q1 — Business name and domain** (App. B #1). [Drafts use the placeholder "YourBrand" / `yourbrand.com`; replace any time.]
- **Q2 — Who and where:** country and currency for prices, page language, and the first niche to target. [USD, English, first niche = small agencies and e-commerce stores that already pay for Zapier/Make; others later.]
- **Q3 — Response-time promise** for care clients (App. B #4). [12 hours on business days for normal issues, 4 hours for "everything is down"; best effort at weekends.]
- **Q4 — Server provider for clients** (App. B #2). [Hetzner Cloud (cheapest reliable 2 vCPU / 4 GB, EU + US locations); DigitalOcean as the alternative when a client needs a specific region.]
- **Q5 — Your time per client per month** included in care. [1 hour in the basic plan, 3 hours in the higher plan; extra work billed hourly.]

## Tasks

### [ ] 4b.1 — Fresh market and cost facts
- **Goal:** re-check and date every number the offer depends on: Zapier, Make and Activepieces Cloud prices, n8n licence position, typical freelancer rates, VPS prices for 2 vCPU / 4 GB (Hetzner, DigitalOcean, Vultr), backup storage (Backblaze B2), Telegram/SMTP costs. Sources and dates for each.
- **Spec refs:** 1 (positioning), 18 (pricing check); RESEARCH says "re-check before quoting".
- **Files likely touched:** `docs/go-to-market/research.md`, `docs/RESEARCH.md` (pointer)
- **Acceptance checks:** every price has a source link and a check date; anything unverifiable is marked "not verified".
- **Tests required:** `opskit/bin/check` stays green (docs only).
- **Manual verification:** owner skims the table.

### [ ] 4b.2 — The offer
- **Goal:** what is sold, in plain words: one-time setup (server, HTTPS, backups, monitoring, first flows or Zapier migration), monthly "hosting + care" plans, add-ons (extra flows, migration from Zapier/Make, WhatsApp alerts later), what is included and excluded, response times (Q3), what the client must provide (accounts, API keys they own), how they can leave (handover, data export), privacy note summary (A4). Only features that exist in Phases 1–4 are promised; Phases 5–7 are listed as "coming".
- **Spec refs:** 1, 2, 18, App. C A4/A5
- **Files likely touched:** `docs/go-to-market/offer.md`
- **Acceptance checks:** no promise depends on a CE paid-only feature (SPEC 18 list) or a V2 item; every included item maps to an opskit command or runbook.
- **Manual verification:** owner reads it as if they were a client.

### [ ] 4b.3 — Pricing sheet + cost calculator
- **Goal:** cost per client (server, backup storage, monitoring share, your hours) → setup price and monthly plans with a visible margin; comparison against what the client pays Zapier/Make today; a small calculator the owner can edit (CSV that opens in Google Sheets/Excel) and a printable one-page pricing table.
- **Spec refs:** 18 (≥ 2 vCPU / 4 GB per client, dedicated hosts until the first paying client)
- **Files likely touched:** `docs/go-to-market/pricing.md`, `docs/go-to-market/pricing-calculator.csv`
- **Acceptance checks:** every plan covers server cost + included hours at your target hourly rate; numbers recompute from the CSV inputs.
- **Manual verification:** owner changes one input in a spreadsheet and the totals follow.

### [ ] 4b.4 — One-page site draft
- **Goal:** a single static page (plain HTML + CSS, no build step, works offline, mobile-friendly): problem, what you do, how it works (setup → hosting → care), plans and prices, trust points (backups tested monthly, alerts, you own your data, open source), FAQ, contact (email link; no form backend yet). Brand placeholders from Q1; no client names or fake testimonials.
- **Spec refs:** 1, 4b
- **Files likely touched:** `docs/go-to-market/site/index.html`
- **Acceptance checks:** opens from the file system; passes an HTML validator; readable at phone width; no external scripts or trackers.
- **Manual verification:** owner opens it in a browser (and on the phone).

### [ ] 4b.5 — 3-minute demo script + demo setup
- **Goal:** a timed script (what to say, what to click) showing: a working flow, a deliberate failure arriving on Telegram with the run link, the daily summary, a backup and a restore check, and the care report "coming soon"; plus a checklist to prepare the demo on a Codespace or practice stack (`opskit selftest --keep`, the e2e failing flow, a real Telegram bot).
- **Spec refs:** 4b, 9, 10
- **Files likely touched:** `docs/go-to-market/demo-script.md`
- **Acceptance checks:** every step uses something that exists today; each step has a fallback if the network is slow.
- **Manual verification:** owner rehearses once with a timer.

### [ ] 4b.6 — Outreach kit
- **Goal:** ideal-client profile per niche, where to find the first 20 prospects, three short message templates (cold email, LinkedIn/DM, referral ask), discovery-call questions, a one-page proposal template, and the Zapier/Make → Activepieces migration checklist (A5) used in sales calls.
- **Spec refs:** 1 (buyers), App. C A5
- **Files likely touched:** `docs/go-to-market/outreach.md`, `docs/go-to-market/proposal-template.md`, `docs/go-to-market/zapier-migration-checklist.md`
- **Acceptance checks:** templates contain no claims beyond the offer; the migration checklist flags what CE cannot do (paid-only features).
- **Manual verification:** owner adapts one template and sends it to a friendly contact.

### [ ] 4b.7 — Owner sign-off and phase close
- **Goal:** owner reviews 4b.2–4b.6, requests changes, signs off; record the sign-off and final numbers in PROGRESS; next phase (5) starts.
- **Files likely touched:** `docs/PROGRESS.md`, `docs/go-to-market/README.md` (index + status of each document)
- **Acceptance checks:** SPEC 4b accept: offer, pricing sheet, page draft, demo script signed off by the owner.
