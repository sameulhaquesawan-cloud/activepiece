# Market and cost facts (Phase 4b.1)

Checked **21 Oct 2026**. Prices change often: re-check before quoting a client. "Official" = read from the
vendor's own page that day; "secondary" = third-party article, not verified against the vendor.
Prices exclude VAT unless stated.

## What clients pay today (the tools we replace or sit next to)
| Tool | Plan (entry tier) | Price | Included | Source |
|---|---|---|---|---|
| Zapier | Free | $0 | 100 tasks/month | official, [zapier.com/pricing](https://zapier.com/pricing) |
| Zapier | Professional | from $19.99/month (annual billing); about $29.99 billed monthly | 750 tasks/month, rises with task tier | official (annual "starting from"); monthly figure secondary ([jetadmin](https://www.jetadmin.io/blog/zapier-pricing/), [eesel](https://eesel.ai/blog/zapier-subscription)) |
| Zapier | Team | from $69/month (annual); about $103.50 billed monthly | 2,000 tasks/month, 25 users | official (annual); monthly secondary |
| Make | Core / Pro / Teams | $9 / $16 / $29 per month (annual); about $10.59 / $18.82 / $34.12 monthly | 10,000 credits/month | secondary, sources disagree ([jetadmin](https://www.jetadmin.io/blog/make-pricing/), [automationatlas](https://automationatlas.io/answers/make-pricing-explained-2026/), [coworker](https://coworker.ai/blog/make-com-pricing)); make.com blocked from here — **not verified** |
| Activepieces Cloud | Free / Plus / Team | $0 / $20 / $200 per month | 1,000 (daily reset) / 10,000 / 50,000 credits per month; a run = 1 credit however many steps; extra $0.007/credit | official, [activepieces.com/pricing](https://www.activepieces.com/pricing) |

**Correction:** `docs/RESEARCH.md` and several 2026 articles describe Activepieces Cloud as "$5 per active
flow after 10 free". The official page now shows the credit plans above; the per-flow model is out of date.

What this means for the offer: a client who pays Zapier Team monthly (≈ $104) or Professional at higher
task tiers is the natural buyer; our price must be explained as "hosting + someone who watches and fixes it",
not as "cheaper software".

## Licence position (why Activepieces and not n8n)
- **Activepieces Community Edition: MIT** — we may host and run clients' workflows for a fee (SPEC 1).
- **n8n (Sustainable Use License):** building automations for clients is allowed, but hosting and managing
  several clients' workflows and credentials in an instance you run requires a commercial (Enterprise/Embed)
  agreement; per-client instances owned by the client are a grey area handled case by case.
  Sources: [n8n licence FAQ](https://docs.n8n.io/n8n-community-license/community-license/license-faq), [nordflux guide](https://nordflux.de/en/guides/may-my-agency-host-n8n-for-customers-fair-code-resale-gray-area-customer-access), [n8n community](https://community.n8n.io/t/can-i-use-n8n-cloud-to-manage-workflows-for-multiple-consulting-clients/236130?tl=en).
- Sales line: "Open source (MIT) — no per-task fees, no vendor lock-in; you keep your data and can take the
  whole system with you."

## Server cost per client (SPEC 18: at least 2 vCPU / 4 GB per client stack)
| Provider | Plan | Location | Price / month | Notes | Source |
|---|---|---|---|---|---|
| Hetzner | CX23 (2 vCPU, 4 GB, 40 GB) | DE, FI | €5.99 | **"not available"** on 21 Oct 2026 (whole cost-optimised line) | official, [hetzner.com/cloud/cost-optimized](https://www.hetzner.com/cloud/cost-optimized) |
| Hetzner | CPX22 (2 AMD vCPU, 4 GB, 80 GB) | DE, FI, SG | €19.99 | available; incl. IPv4 in the shown price | official, [hetzner.com/cloud/regular-performance](https://www.hetzner.com/cloud/regular-performance) |
| Hetzner | CPX21 (3 vCPU, 4 GB, 80 GB) | US | €32.49 | US locations cost far more | official, same page |
| DigitalOcean | Basic, 2 vCPU, 4 GiB, 80 GiB | many incl. EU + US | $24.00 | 4,000 GiB transfer | official, [digitalocean.com/pricing/droplets](https://www.digitalocean.com/pricing/droplets) |
| Vultr | — | — | — | vultr.com blocked from here — **not verified** | — |

Hetzner raised prices twice in 2026 and its cheapest line is often sold out
([findstack](https://findstack.com/resources/hetzner-price-increase-2026), [suominen comparison](https://kimmo.suominen.com/stuff/cpc-2026-08.txt)).
**Planning numbers:** EU client ≈ €20/month (Hetzner CPX22), US client ≈ $24/month (DigitalOcean); if Hetzner
CX23 becomes available again, an EU client drops to ≈ €6/month. Budget **€25 / $30 per client per month** for
server + backups + spare. Changes owner decision Q4: Hetzner is the default for EU clients only; US clients go
to DigitalOcean (cheaper than Hetzner US now).

## Running costs that are (almost) free
| Item | Price | Source |
|---|---|---|
| Backblaze B2 backup storage | $6.95 per TB/month, first 10 GB free; egress free up to 3× stored | secondary, consistent across 2026 sources ([egresscost](https://egresscost.com/backblaze-b2), [upstash](https://upstash.com/blog/backblaze-b2-pricing-explained-2026.md)); a client's backups are typically well under 10 GB |
| Telegram bot alerts | free | Telegram Bot API |
| Email alerts (Brevo free) | 300 emails/day free; paid from ≈ $9/month | secondary ([sendlayer](https://sendlayer.com/blog/best-free-smtp-servers/), [dreamlit](https://dreamlit.ai/blog/brevo-review)) |
| Uptime Kuma | free (open source); runs on one small monitoring server for all clients (≈ €6–20/month total) | — |
| UptimeRobot (watches Uptime Kuma) | free plan | — |

## What automation help costs (to set your hourly rate)
- Freelance automation work (Zapier/Make/n8n), 2026: commonly **$40–$100/hour** on Upwork; experienced solo
  operators report **$95–$235/hour**; flat builds $1,800–$4,500; maintenance retainers $1,200–$3,800/month.
  Secondary and US-leaning, sources have an interest in high numbers
  ([ciphernutz](https://ciphernutz.com/blog/hire-n8n-expert-cost-pricing-guide), [betonai rate card](https://betonai.net/ai-automation-rate-card-2026-what-to-charge-for-n8n-make-and-zapier-builds-real-rates-from-54-operators/), [adsnipper](https://adsnipper.com/blog/hire-n8n-developer/)).
- No reliable Europe-specific data found; assume similar in EUR for Western Europe and lower in Southern/Eastern Europe — **not verified**.
- Starting assumption for the pricing sheet: **$60 / €55 per hour** (new provider, below the market middle,
  raise after the first three clients).

## Open items for the owner's accountant (not researched here)
- VAT: selling services to EU businesses (reverse charge vs. registering) depends on where your business is
  registered.
- Invoicing currency and payment provider fees (Stripe, Wise, PayPal).
