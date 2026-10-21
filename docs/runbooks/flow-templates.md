# Runbook — flow templates for a client

Commands run on your machine (Codespace, WSL, cloud AI session) from the repo folder. What each template
does and needs: `opskit/flows/<template>/README.md`. Design: ADR-017 in `docs/DECISIONS.md`.

## The library
```bash
opskit/bin/opskit flows list
```
| Template | Good for | Client needs |
|---|---|---|
| `lead-capture` | website contact/quote form | Google account (Sheets + Gmail) |
| `invoice-reminder` | chasing overdue invoices | invoices in a Google Sheet, Gmail |
| `review-request` | shops asking for reviews | shop webhook, any mail account (SMTP) |
| `ai-email-sorter` | busy shared inbox | Gmail, an AI key (or local model), Slack |
| `lead-ad-alert` | Facebook/Instagram lead ads | Meta app (one-time setup), HubSpot, Gmail |

## Import for a client (5 minutes per template)
1. Read the template's README with the client: placeholders, what they must prepare (sheet headers,
   Gmail labels, Meta app …), how they will connect each account. EU clients: use the
   "no third party" connection options.
2. Import (it starts switched off):
   ```bash
   opskit/bin/opskit flows import lead-capture acme --set OWNER_EMAIL=owner@acme.com --set BUSINESS_NAME="Acme Dental"
   ```
   It asks for the client's builder **admin email and password**: type them yourself; they are used
   once and never stored. It prints the flow link, the steps still waiting for a connection and the next
   steps. Running it again changes nothing (`--again` imports a second copy).
3. No terminal access to the client's builder? `--print-steps` writes the filled file to
   `opskit/clients/<id>/flows/<template>.json` (git-ignored, contains client settings) and prints how to
   import it by clicking (Create New → Import Flow).

## Connect, test, switch on (with the client, on a call)
1. **Connections:** in the builder, the client creates each connection themselves (they type their own
   passwords and keys — never send them to you). Then open the flow and pick the connection in every
   step the import listed.
2. **Test:** follow "Sample run" in the README (test buttons in the builder, or the `test/` payloads with
   `curl`). Use your own email address as the test recipient.
3. **Switch on:** Publish. Watch the first real run on the Runs page.
4. Note in your client notes which templates are live and how each account is connected.

## When a template run fails
The failed-run alert (Telegram etc.) names the flow, the step and links to the run. Templates fail on
purpose when data is bad (e.g. "Invalid email in field "email""), so nothing is lost silently. Fix the
cause (often an expired connection: reconnect it), then **Retry** the failed run in the builder.

## Pause or remove
- Pause: open the flow → switch off (the run history stays).
- Remove: delete the flow in the builder. Ask the client whether to delete the connections too.

## For you (maintenance)
- `opskit/bin/opskit flows validate` must pass before any template change is committed (it runs in
  `opskit/bin/check` and CI).
- After an Activepieces upgrade: re-pin the piece versions in `flow.json` + `template.yaml`, run CI
  (it imports every template and replays its samples), redo the CHECKLIST of templates whose pieces
  changed.
- Each template's `CHECKLIST.md` is the real-account test; do it once per template version (Codespace,
  your own free test accounts) and note the result in `docs/PROGRESS.md`.
