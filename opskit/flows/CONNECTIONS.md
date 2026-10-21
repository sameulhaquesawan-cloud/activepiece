# Connecting the client's accounts

In the builder: a step → **Connection** → new connection. Activepieces 0.92.3 (self-hosted) shows a
**Connect** button (Activepieces' own sign-in service, `secrets.activepieces.com`, which then holds the
sign-in tokens) and **Try another method** (the client's own credentials, no third party). EU clients:
use "Try another method" (`docs/go-to-market/eu/subprocessors.md`). The client types every password,
key and token themselves; they never go into chat, email or files.

## Google Sheets — service account (our default)
Seen in the Phase 5 test: **Connect** saved a connection, but every Sheets call failed with
`403 PERMISSION_DENIED … insufficient authentication scopes` (even after signing in again). Until that
is understood, use a service account (also no third party):
1. console.cloud.google.com with the client's Google account → create a project (e.g. "Automations").
2. APIs & Services → Library → enable **Google Sheets API** and **Google Drive API**.
3. IAM & Admin → Service Accounts → Create service account (name "activepieces", no roles needed) →
   open it → Keys → Add key → Create new key → JSON. A `.json` file downloads.
4. Copy the service account's email (`…@….iam.gserviceaccount.com`). In Google Sheets, **Share** each
   sheet the flows use with that email as **Editor**.
5. Builder → Google Sheets connection → Try another method → **Service Account (Advanced)** → the client
   opens the JSON file in a text editor and pastes the whole content into "Service Account JSON Key";
   leave "User Email" empty → Save. Then delete the downloaded file (it is a key).
6. The spreadsheet dropdown lists only sheets shared with the service account.

If you try **Connect** anyway: on Google's consent screen tick **every** box ("See, edit, create and
delete all your Google Sheets spreadsheets", Drive). A connection saved with a box unticked looks fine
but fails with "insufficient authentication scopes"; delete it and connect again.

## Gmail
- **Connect** worked in the Phase 5 test (sending). Tick every box on Google's consent screen.
- No third party: Try another method → **Custom OAuth2 App (Advanced)**: a Google Cloud OAuth client of
  the client's own (type Web application, redirect URI `https://<domain>/redirect`, Gmail API enabled);
  paste its client ID and secret. Google limits unverified apps (100 users, consent screen warning);
  fine for one business. Workspace accounts can also use a service account with domain-wide delegation.

## Slack
**Connect**, or Try another method → **Bot Token**: api.slack.com/apps → Create app → OAuth &
Permissions → bot scopes `chat:write`, `channels:read` (plus `groups:read` for private channels) →
Install to workspace → copy the `xoxb-…` token into "Bot Token" (leave "User Token" empty); invite the
bot to the channel. Check the scopes once against the error message if posting fails (CHECKLIST).

## HubSpot
**Connect**, or Try another method → **Private App Access Token**: HubSpot → Development → Legacy apps
(private apps) → create → scopes `crm.objects.contacts.read`, `crm.objects.contacts.write` → copy the
token into the connection.

## SMTP (any mail provider)
Host, port, user, password of the client's mail provider. Gmail: `smtp.gmail.com`, port 465, TLS on,
password = a Google **app password** (Google Account → Security → 2-Step Verification → App passwords).

## AI (OpenAI Compatible, our piece)
Base URL of the provider (e.g. `https://api.openai.com/v1`, `https://openrouter.ai/api/v1`, a local
`http://…/v1`) and the client's API key.

## Facebook Lead Ads
Only Try another method → **Custom OAuth2 App** with the client's Meta app: see
`lead-ad-alert/README.md`.
