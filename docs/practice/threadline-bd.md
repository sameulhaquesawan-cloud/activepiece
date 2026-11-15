---
status: accepted
---
# Practice client #0 — Threadline BD (men's and women's clothing)

Staging (`staging-activepiece.autonyxai.shop`, client id `autonyx-staging`) plays this client. Fake data only;
every email/message goes to the owner's own test inboxes and Telegram. The 10 flows double as the menu for real
clothing/online-shop proposals (Bangladesh and international).

Client brief (discovery answers, decisions for staging): `threadline-brief.md`.

## The business
Dhaka clothing brand: men's panjabi, shirts, t-shirts; women's kurti, three-piece, salwar sets; sizes S–XXL.
~40 orders/day: 60 % from the Facebook page inbox (staff type them in), 40 % from the website (Shopify dev store,
free via Shopify Partners — *verify* connection on the day). ~85 % cash on delivery; Pathao (Dhaka) and Steadfast
(outside Dhaka); some customers pay advance by bKash. Owner "Nadia" + 2 staff, all on Telegram.

## Pain points (research, 15 Nov 2026 — mostly vendor sources, treat numbers as directional)
- Orders scattered across inbox, website and a sheet; staff retype each order into courier panels.
- Fake/unsure COD orders and returns: vendors quote 20–30 % return-to-origin on COD; Pathao charges sellers a return fee.
- Clothing-specific: wrong size is the most common reason for exchanges; stock is per size/colour, so one size sells out
  while others sit; customers ask "when is XL back?".
- bKash advance payments checked by hand; fake payment screenshots are a known scam.
- "Where is my order?" questions; reviews never asked for; abandoned carts on the website (top-ranked first automation in Shopify guides).

## The 10 flows
| # | Flow | Pain | Trigger → steps | Pieces |
|---|---|---|---|---|
| 1 | Order intake + risk flag | scattered orders, repeat returners | website new order (Shopify) **or** staff "inbox order" form → Orders table → phone in Returns list? flag → Telegram to team | shopify, forms, tables, telegram-bot |
| 2 | COD confirmation | fake orders, returns | new COD order → confirm/cancel link to the customer → confirmed = ready to ship; no answer in 6 h → staff call list | approval, smtp (SMS/WhatsApp in real life), delay, tables |
| 3 | Courier booking + tracking message | retyping, "where is my order?" | confirmed order → Dhaka? Pathao : Steadfast → create parcel → tracking id saved → customer gets the tracking link | http (mock courier on staging), tables, smtp |
| 4 | Delivery and return updates | returns noticed late, stock not put back | courier status → update order; returned → alert, add phone to Returns, put sizes back in stock | webhook/schedule, http, tables, telegram-bot |
| 5 | Size exchange / return request | wrong size | customer form (order no, reason, wanted size) → is that size in stock? → staff approve in Telegram → customer told next steps | forms, tables, approval, smtp |
| 6 | Low stock + back-in-stock | size sold out, lost sales | daily: any size/colour below threshold → Telegram; restocked → email everyone on that item's waitlist | schedule, tables, smtp, telegram-bot |
| 7 | bKash advance check | fake screenshots | customer submits TrxID by form → staff check the statement, approve in Telegram → order marked paid | forms, approval, tables |
| 8 | Abandoned checkout | lost website sales | Shopify abandoned checkout → wait 1 h → reminder email with the cart | shopify, delay, smtp |
| 9 | Review request | no reviews | order delivered → wait 3 days → review link, asks for a photo of the outfit (template `review-request`) | webhook, delay, smtp |
| 10 | Daily summary + weekly cash check | no overview, COD cash not matching | 22:00 orders, revenue, COD pending, returns, low sizes → Telegram; Mondays: courier payout vs delivered orders | schedule, tables, telegram-bot |

Not possible as-is: reading Facebook page messages (the 0.92.3 Facebook Pages piece only posts), WhatsApp/SMS without
the client's own Meta or SMS-gateway account, real courier APIs without a merchant account (staging uses email,
Telegram and a mock courier instead).

## Build order on staging
- Launch week — Wed: 1 (order intake) and 9 (review request, from the template). Thu: 2 (COD confirmation) and the incident drill on it.
- Week 2 practice hour: 3, 4, 5, 6, 10. Then 7, 8 (8 needs the Shopify dev store connected).

## Sources
- COD/returns/courier pain: egrow.com/en/blog/bangladesh-cod-whatsapp-2026 · youthfireit.com/academy/courier-automation-pathao-steadfast-redx-bangladesh · easysellapp.com/blogs/wiki/cod-ecommerce-pakistan-bangladesh-cash-collection-delivery-2026 · pathao.com/?p=7787 · steadfast.com.bd/terms-and-condition
- bKash checks and fake screenshots: youthfireit.com/academy/automate-bkash-payment-confirmation-bangladesh · lock.pub/en/blog/facebook-marketplace-bangladesh-safety
- Shopify small-store automations: pixc.com/blog/ecommerce-automation-solo-merchants · getmesa.com/blog/shopify-flow-best-automation-ideas-for-2026 · community.shopify.com/t/what-automations-do-you-use/600593
- Admin hours: retailminded.com/merchants-are-spending-332-hours-each-year-on-overwhelming-admin (Brightpearl by Sage, ~6.4 h/week)
- Pieces checked in the pinned 0.92.3 source (`packages/pieces/core`, `packages/pieces/community`).
