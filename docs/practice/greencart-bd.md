---
status: proposed
---
# Practice client #0 — GreenCart BD (online shop)

Staging (`staging-activepiece.autonyxai.shop`, client id `autonyx-staging`) plays this client. Fake data only;
every email/message goes to the owner's own test inboxes and Telegram. The flow catalog below doubles as the
menu for real online-shop proposals (Bangladesh and international).

## The business
Dhaka shop selling groceries and household goods. ~40 orders/day: 60 % from the Facebook page inbox (staff
type them in), 40 % from the website (Shopify dev store, free via Shopify Partners — *verify* connection on the day).
~85 % cash on delivery; couriers Pathao (Dhaka) and Steadfast (outside Dhaka); some customers pay advance by bKash.
Also supplies 5 cafés on invoice (15-day terms). Owner "Nadia" + 2 staff, all on Telegram.

## Pain points (research, 15 Nov 2026 — mostly vendor sources, treat numbers as directional)
- Orders scattered across inbox, website and a sheet; staff retype each order into courier panels (Pathao for Dhaka, Steadfast elsewhere).
- Fake/unsure COD orders and returns: vendors quote 20–30 % return-to-origin on COD; Pathao charges sellers a return fee, so a fake order costs both delivery legs.
- bKash advance payments checked by hand against the statement; fake payment screenshots are a known scam.
- "Where is my order?" questions eat support time; stock runs out unnoticed; reviews are never asked for; B2B invoices paid late.
- Internationally the same list minus COD, plus abandoned carts (the top-ranked first automation in Shopify guides) and low-stock alerts.

## Flow catalog (17) — ★ = built on staging in launch week
| # | Flow | Pain | Trigger → steps | Pieces |
|---|---|---|---|---|
| 1 ★ | Order intake | orders scattered | website new order (Shopify) **or** staff "inbox order" form → Orders table → Telegram to team | shopify, forms, tables, telegram-bot |
| 2 ★ | COD confirmation | fake orders, returns | new COD order → customer gets a confirm/cancel link → confirmed = ready to ship; no answer in 6 h → staff call list | approval, smtp (SMS/WhatsApp in real life), delay, tables |
| 3 | Risky-order check | repeat returners | new order → phone in Returns table? → flag + Telegram | tables, telegram-bot |
| 4 ★ | Courier booking | retyping into courier panels | confirmed order → Dhaka? Pathao : Steadfast → create parcel → tracking id saved → customer told | http (mock courier on staging; real merchant APIs need a merchant account) |
| 5 | Delivery updates | returns noticed late | courier status (webhook/poll) → update order; returned → alert + add phone to Returns | webhook/schedule, http, tables |
| 6 | COD reconciliation | cash not matching | weekly courier payout vs delivered orders → mismatch report | schedule, http, tables, smtp |
| 7 | bKash advance check | fake screenshots | customer submits TrxID by form → staff approves in Telegram after checking the statement → order paid | forms, approval, telegram-bot |
| 8 ★ | Low-stock alert | stock-outs | daily → stock below threshold → Telegram | schedule, tables or shopify |
| 9 | Abandoned checkout | lost website sales | Shopify abandoned checkout → wait 1 h → reminder email | shopify, delay, smtp |
| 10 ★ | Review request | no reviews | order delivered/paid → wait → review link (template `review-request`) | webhook, smtp |
| 11 ★ | Café invoice reminders | late B2B payment | weekdays 08:00 → overdue invoices → reminder (template `invoice-reminder-tables`) | schedule, tables, smtp |
| 12 ★ | Wholesale enquiry | missed leads | site form → Leads table → owner + auto-reply (template `lead-capture-tables`) | webhook, tables, smtp |
| 13 ★ | Daily summary | owner has no overview | 22:00 → orders, revenue, COD pending, returns → Telegram | schedule, tables, telegram-bot |
| 14 | Order status reply | "where is my order?" | form/chat with phone → Orders lookup → status reply | forms, tables |
| 15 | Win-back | one-time buyers | 30 days no order → offer email | schedule, tables, smtp |
| 16 | Accountant export | monthly bookkeeping | 1st of month → orders CSV → email | schedule, tables, smtp |
| 17 | AI message drafting | slow replies | pasted customer message → AI draft in Bangla/English → staff reviews | openai-compatible (owner's GLM, practice data only) |

Not possible as-is: reading Facebook page messages (the 0.92.3 Facebook Pages piece only posts), WhatsApp/SMS without
the client's own Meta or SMS-gateway account (staging uses email + Telegram in their place).

## Launch-week build (9 ★ flows)
- Wed: import 10, 11, 12; build 1 (order intake) with a test form and the Shopify dev store.
- Thu: 2 (COD confirmation) and the incident drill on it; backup + restore test.
- Week 2 practice hour: 4 (mock courier), 8, 13. The rest stay in the catalog for proposals.

## Sources
- COD/returns/courier pain: egrow.com/en/blog/bangladesh-cod-whatsapp-2026 · youthfireit.com/academy/courier-automation-pathao-steadfast-redx-bangladesh · easysellapp.com/blogs/wiki/cod-ecommerce-pakistan-bangladesh-cash-collection-delivery-2026 · pathao.com/?p=7787 · steadfast.com.bd/terms-and-condition
- bKash checks and fake screenshots: youthfireit.com/academy/automate-bkash-payment-confirmation-bangladesh · lock.pub/en/blog/facebook-marketplace-bangladesh-safety
- Shopify small-store automations: pixc.com/blog/ecommerce-automation-solo-merchants · getmesa.com/blog/shopify-flow-best-automation-ideas-for-2026 · community.shopify.com/t/what-automations-do-you-use/600593
- Admin hours: retailminded.com/merchants-are-spending-332-hours-each-year-on-overwhelming-admin (Brightpearl by Sage, ~6.4 h/week)
- Pieces checked in the pinned 0.92.3 source (`packages/pieces/core`, `packages/pieces/community`).
