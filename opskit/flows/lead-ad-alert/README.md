# Lead-ad alert

**For:** businesses running Facebook or Instagram lead ads (instant forms) who lose leads because
nobody looks at Meta's lead centre.
**What it does:** a new lead → read the answers → the contact is created or updated in HubSpot (by
email, lifecycle stage "lead") → the sales person gets an email with name, email, phone, the other
answers, ad and campaign, usually within a minute.
**If something is wrong:** a lead without an email (a phone-only form) fails the run at "Read lead"
naming the lead id, so you see it and can handle it by hand; HubSpot or Gmail errors fail at their
step. The failed-run alert reaches you within 5 minutes. The HubSpot update is retried automatically
(it is an upsert, safe to repeat); the email is not.

## Placeholders (`--set KEY=value`)
| Key | Meaning |
|---|---|
| `SALES_EMAIL` | who gets each lead |
| `BUSINESS_NAME` | sender name |

## One-time Meta setup per client (this is the part that takes time)
Facebook Lead Ads has no ready-made sign-in on self-hosted Activepieces: each client stack needs its
own Meta app, because Meta sends all leads of an app to one webhook address. Do it with the client
(their Meta business account owns the app). Menu names change often — check them once and note them
in the CHECKLIST.
1. developers.facebook.com → My Apps → Create app (type Business), owned by the client's business
   portfolio.
2. Add **Facebook Login for Business** (or Facebook Login): valid OAuth redirect URI
   `https://<domain>/redirect`.
3. Add **Webhooks**: object **Page**, callback URL `https://<domain>/api/v1/app-events/facebook-leads`,
   verify token `activepieces`, subscribe to the field `leadgen`.
4. Settings → Basic: copy the **App ID** and **App secret**.
5. Put the app secret into the client's git-ignored `opskit/clients/<id>/channels.env` with your own
   editor (never in chat): `META_APP_SECRET=<app secret>`; in `client.yaml`:
   ```yaml
   app_webhooks:
     facebook_leads: { secret: META_APP_SECRET }
   ```
   then `opskit deploy <id>` (renders `AP_APP_WEBHOOK_SECRETS`, restarts the app).
6. Permissions `leads_retrieval`, `pages_manage_metadata`, `pages_show_list`, `pages_manage_ads`,
   `business_management`: while the app is in development mode they work for people with a role on
   the app *(verify)*; for anything else Meta's app review / business verification is needed.

## Import
```bash
opskit flows import lead-ad-alert <client> --set SALES_EMAIL=… --set BUSINESS_NAME="…"
```

## Connections (the client's own accounts)
- **Facebook Lead Ads** — "Custom OAuth2 App (Advanced)" with the App ID / App secret from step 4.
How-to: `../CONNECTIONS.md`.
- **HubSpot** — **Connect**, or Try another method → Private App Access Token (a private app with
  `crm.objects.contacts.read` and `.write` scopes; no third party).
- **Gmail** — **Connect** (tick every box) or Try another method → the client's own Google Cloud app.

In the flow: trigger → Facebook connection, page and (optionally) form; HubSpot and Gmail steps →
their connections.

## Sample run
1. Publish the flow (the trigger subscribes the page to the app).
2. Meta's **Lead Ads Testing Tool** (developers.facebook.com/tools/lead-ads-testing) → page and form →
   create a test lead with your own email.
3. Within a minute: contact in HubSpot (first name, last name, phone, lifecycle "lead") and the email
   to `SALES_EMAIL`. A run appears in the builder.
4. Without Meta: CI replays `test/lead.json` and `test/lead-no-email.json` on a stub copy.
