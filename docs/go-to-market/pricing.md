# Pricing sheet (draft for owner sign-off)

Numbers come from `pricing-calculator.csv` (open it in Google Sheets: *File → Import → Upload*, or in Excel)
with the starting assumptions below, rounded to "nice" prices. Change an input there and the calculated rows
follow. Facts behind the costs: `research.md` (checked 21 Oct 2026). Prices exclude VAT.

## Price list

| | Europe (EUR) | US & rest of world (USD) |
|---|---|---|
| **Setup** (one-time): own server, HTTPS, backups, monitoring, alerts, up to 3 flows, handover call | **€690** | **$749** |
| **Care** (monthly): hosting + backups + restore tests + monitoring + 1 h fixes/changes | **€159 / month** | **$179 / month** |
| **Care Plus** (monthly): everything in Care + 3 h fixes/changes + monthly updates + 1 small flow | **€319 / month** | **$349 / month** |
| Extra hour (15-minute steps) | €55 | $60 |
| Extra flow — small (trigger + up to ~5 steps) | €120 | $140 |
| Extra flow — medium (branches/loops, up to ~15 steps) | €290 | $330 |
| Migration of one Zap/Make scenario (rebuild + side-by-side test) | €90 | $100 |

Minimum term: 3 months, then monthly. Yearly prepay: 2 months free (10 × monthly).
First pilot client (in exchange for a testimonial and a case study): 50 % off setup.

## Where the money goes (per client per month, from the calculator)
| | Care EU | Care US | Care Plus EU | Care Plus US |
|---|---|---|---|---|
| Server | €20 | $24 | €20 | $24 |
| Buffer (backup storage, price rises) | €5 | $6 | €5 | $6 |
| Share of the monitoring server | €4 | $5 | €4 | $5 |
| Your time: 30 min watching + included hours | €82.50 | $90 | €192.50 | $210 |
| **Cost** | **€111.50** | **$125** | **€221.50** | **$245** |
| Calculated price at 30 % margin | €159.29 | $178.57 | €316.43 | $350 |
| **List price** | **€159** | **$179** | **€319** | **$349** |
| Your profit on top of your paid hours | ≈ €48 | ≈ $54 | ≈ €97 | ≈ $104 |

Setup: 11 hours × rate + 15 % buffer = €696 / $759 → list **€690 / $749**.

Starting assumptions (all editable in the CSV): your rate €55 / $60 per hour (below the 2026 market middle
of roughly $40–$235; raise it after the first three clients), EU server Hetzner CPX22 €19.99, US server
DigitalOcean $24, monitoring server shared by about 5 clients, 30 % margin.

## How it compares (what the client sees)
| Option | Monthly cost | Who fixes it when it breaks? |
|---|---|---|
| Zapier Team | from $69 (yearly) / ≈ $103.50 (monthly) for 2,000 tasks, more at higher task tiers | the client |
| Make Teams | ≈ $29–$34 for 10,000 credits, more with volume | the client |
| Activepieces Cloud Plus / Team | $20 / $200 | the client |
| Freelancer on call | $40–$235 per hour, usually no monitoring or backups | whoever is free |
| **YourBrand Care** | **€159 / $179**, no per-task fees | **we do, with alerts within 5 minutes** |

Talking point: *"You are not paying for software — the software is free and open source. You are paying for
a private server, nightly tested backups, alerts within minutes and a person who fixes things."* Clients
with heavy Zapier usage (many tasks) usually save money; clients with light usage buy peace of mind.

## Rules of thumb for the owner
- Quote EU clients in EUR on an EU server; quote everyone else in USD.
- Re-check server prices (`research.md`) before each proposal; Hetzner changed prices twice in 2026.
- Never discount Care below cost (server + buffer + 30 min watching + included hours).
- If a client's flows need more power (many runs, big files), the next server size costs more — quote it.
- VAT and invoicing rules depend on where your business is registered: ask your accountant.
