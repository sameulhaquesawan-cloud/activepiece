# Template conventions

## Names
- Folder = `template_id` (lowercase, dashes). Flow display name = the template `name`.
- Step display names say what the step does for the client ("Add lead to sheet"), because they appear
  in failed-run alerts.

## Placeholders
- Written `{{OPSKIT:KEY}}`, `KEY` in capitals (`OWNER_EMAIL`, `SHEET_NAME`). Every one used in
  `flow.json` is declared in `template.yaml` with a description and a made-up example; every declared
  one is used.
- `flows import --set KEY=value` fills them; `default` is used when not set; a missing or unknown key
  stops the import. Placeholders hold settings (addresses, names, wording, wait times), never secrets.
- No real ids, emails, URLs, sheet links or keys in a template. Examples use `example.com`.

## Pieces
- Every piece step pins the exact version the template was tested with, listed in `template.yaml`
  `pieces` (the import fails if the client's stack does not know that version). Re-pin and re-test
  after an Activepieces upgrade.
- Our own pieces carry `custom: packages/pieces/custom/<name>`; `flows import` installs them first.

## Connections — always the client's own
- Piece steps that need an account leave the connection empty; the client creates it in their builder
  and picks it in the step. We never put a client's credentials in a template, a file or chat.
- `template.yaml` `connections` lists, per piece, what it is for and the ways to connect. Name both:
  "OAuth2 (Recommended)" (quick; for Gmail, Sheets, Slack and HubSpot it signs in through Activepieces'
  `secrets.activepieces.com`, which then sees the tokens) and an own-credential option with no third
  party (service account, bot token, private-app token, own OAuth app). EU clients: own credentials by
  default (`docs/go-to-market/eu/subprocessors.md`).
- AI steps use the client's own key (`openai-compatible` piece, ADR-013).

## Failures are never hidden
- `failure: fail-run` (default): steps keep "continue on failure" off, so a failing step fails the run
  and the failed-run detector alerts within 5 minutes (SPEC 10.3). Bad input fails on purpose with a
  clear message (a code step that throws "Invalid email: …").
- `failure: notify-and-fail`: only where the client must hear about it themselves (e.g. a lead that
  could not be saved). A branch sends the client's notification and then a code step throws, so the run
  is still FAILED and we are alerted too.
- Retries: "retry on failure" only on steps that are safe to repeat (reading, idempotent updates),
  never on sending an email.
- Error messages must not quote whole records; name the field ("Invalid email in field email") —
  alerts carry up to 300 characters of them.

## Switched off until tested
- Imported flows are drafts (not published) = off. Order for the client: connect accounts → test with
  `test/` payloads or a real event → publish (switch on) → watch the first real run.
