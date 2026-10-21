# Review request

**For:** online shops (Shopify, WooCommerce, Stripe Checkout or anything that can send an "order paid"
webhook).
**What it does:** the shop calls the webhook when an order is paid → the order is read → if this order
was not handled before, it is remembered and the flow waits `WAIT_AMOUNT` `WAIT_UNIT` (default 7 days)
→ the customer gets a short email with the review link.
**Ignored on purpose (run succeeds, nothing sent):** the same order arriving again (shops retry
webhooks), and orders whose status is not paid (`pending`, `failed`, …).
**If something is wrong:** a webhook without an order id, or a paid order without a customer email,
fails the run at "Read order" and the failed-run alert reaches you. An SMTP error fails the run at
"Send review request"; sending is never retried automatically. The wait survives restarts and
upgrades (it is stored in the database).

## Placeholders (`--set KEY=value`)
| Key | Meaning | Default |
|---|---|---|
| `BUSINESS_NAME` | sender name and signature | — |
| `FROM_EMAIL` | sender address (the SMTP account must be allowed to use it) | — |
| `REPLY_TO` | where replies go | — |
| `REVIEW_URL` | review page (Google review link, Trustpilot, shop page) | — |
| `SUBJECT` | subject | `How did we do?` |
| `WAIT_AMOUNT` | number | `7` |
| `WAIT_UNIT` | `minutes`, `hours` or `days` | `days` |

## Import
```bash
opskit flows import review-request <client> --set BUSINESS_NAME="…" --set FROM_EMAIL=… \
  --set REPLY_TO=… --set REVIEW_URL=https://…
```

## Connection (the client's own account)
- **SMTP** — host, port, user, password of the shop's mail provider (or an app password). No third
  party. In the flow: "Send review request" → pick it.

## Hooking up the shop
Publish the flow, copy the **production** webhook URL from the trigger, then:
- **Shopify:** Settings → Notifications → Webhooks → event "Order payment", format JSON.
- **WooCommerce:** Settings → Advanced → Webhooks → topic "Order updated" (status is checked, only
  paid/processing/completed orders are asked).
- **Stripe:** Developers → Webhooks → event `checkout.session.completed`.
Field names read: order id (`id`, `order_id` or Stripe `data.object.id`), email (`email`,
`customer.email`, `billing.email` or Stripe `customer_details.email`), first name, status.
Check the menu names in the shop once; they change between versions.

## Sample run
1. Set `WAIT_AMOUNT=1` and `WAIT_UNIT=minutes` for the test (or edit the wait step), use your own
   address in `test/shopify-paid.json`.
2. Send it to the production URL → the run pauses at "Wait before asking", one minute later the email
   arrives and the run SUCCEEDED.
3. Send the same file again → run SUCCEEDED, no email (already asked).
4. `test/woo-pending.json` → SUCCEEDED, no email. `test/stripe-no-email.json` → FAILED at "Read order",
   alert received.
5. Put the wait back to 7 days.
