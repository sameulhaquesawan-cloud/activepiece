# Threadline BD — client brief (discovery call, role-play 15 Nov 2026)

Answers to the 10 questions in `docs/go-to-market/outreach.md`. Q1–6 from the owner, Q7–10 drafted for a
realistic Dhaka clothing shop. Scenario: `threadline-bd.md`.

| # | Question | Nadia's answer | What it tells us |
|---|---|---|---|
| 1 | Tools you automate with today? | None. Everything is done by hand. | First automation for her: start small, show quick wins. |
| 2 | What do you pay for them? | Nothing for tools. Two staff spend ~3 h/day copying orders and calling customers. | Sell saved staff time and fewer fake orders, not "cheaper than Zapier". |
| 3 | Which three would hurt most if they stopped? | None yet. Most painful by hand: confirming COD orders, booking couriers, answering "where is my parcel?". | Build order: flows 2 (COD confirm), 3 (courier + tracking), 1 (order intake). |
| 4 | When did one last break? | Nothing automated. Last week 6 fake COD orders went out; ~৳900 lost on return fees. | Put a taka number on the pain in the proposal. |
| 5 | Who builds and fixes them? | Nobody. | She needs the Care plan, not just a setup. |
| 6 | Which apps? | A CRM (HubSpot free) and a Google Sheet for orders. Plus Facebook page, website, Pathao/Steadfast panels, bKash, Gmail. | Connections: HubSpot, Gmail/SMTP, Sheets (needs Google 2-step verification, ASSUMPTIONS #22) or Activepieces Tables instead. |
| 7 | Personal data? Where stored? | Yes: customer names, phones, addresses. No legal rule; wants it private and not shared. | No GDPR paperwork; privacy paragraph from `offer.md`; Mumbai server is fine. |
| 8 | Several people log in? | Nadia edits; the 2 staff only need alerts and approve buttons. | Community Edition's single admin login is enough; staff use Telegram + approval links. |
| 9 | How fast a reply when something breaks? | Same day normally; within 2 hours during Eid and sale campaigns. | Care (12 h) normally; offer Care Plus or an add-on for campaign weeks. |
| 10 | Who decides; what makes it a clear yes? | Nadia alone. Yes if fake COD orders drop and staff save at least 2 h/day. Budget about ৳15,000 setup + ৳3,000/month. | Local price point is far below the international list; one stack per client at ~€20/month does not fit, so a local deal is a one-off build or a shared host (V2). |

## Decisions for staging
- Orders live in an Activepieces table on staging (stands in for her Google Sheet until Google 2-step verification is set up).
- CRM step: HubSpot free account (piece `@activepieces/piece-hubspot` 0.13.1 is in our pack); added after flows 1, 2 and 9 work.
- Alerts and approvals: the owner's Telegram (T3 bot) plays Nadia and her staff.
