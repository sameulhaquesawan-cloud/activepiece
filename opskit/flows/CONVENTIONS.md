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
- `type: number` for numeric inputs (wait times, counts): written as the whole value
  (`"delayFor": "{{OPSKIT:WAIT_AMOUNT}}"`) it is filled as a JSON number. `choices: [...]` limits the
  allowed values (e.g. a dropdown's units).
- No real ids, emails, URLs, sheet links or keys in a template. Examples use `example.com`.

## Step references
- Templates are written in flow schema 27 (`"schemaVersion": "27"`, Activepieces 0.92.3). Since schema
  22 every reference goes through the step's output: `{{trigger['output']['body']['email']}}`,
  `{{step_1['output']['email']}}`, in a loop `{{step_3['output']['item']}}`. The old form
  (`{{step_1['email']}}`) is only rewritten for imports that declare an older schema; in ours it
  silently resolves to nothing. `flows validate` rejects it.

## Step inputs
- Every list input of a piece step must be present, `[]` when unused (`cc`, `bcc`, `attachments`, …):
  0.92.3 treats a missing optional list as invalid and the builder shows the step "Incomplete".
  Required inputs are filled; dropdowns that depend on the client's account (spreadsheet, label,
  channel, page) stay empty for the client to pick. `flows check-pieces` checks this against the
  catalog.
- Steps of pieces listed in `connections` are `"valid": false` (they cannot run before the client picks
  a connection; Activepieces' own exports do the same); the import lists them by name.

## Pieces
- Every piece step pins the exact version the template was tested with, listed in `template.yaml`
  `pieces` (the import fails if the client's stack does not know that version). Re-pin and re-test
  after an Activepieces upgrade.
- Our own pieces carry `custom: packages/pieces/custom/<name>`; `flows import` installs them first.

## Connections — always the client's own
- Piece steps that need an account leave the connection empty; the client creates it in their builder
  and picks it in the step. We never put a client's credentials in a template, a file or chat.
- `template.yaml` `connections` lists, per piece, what it is for and the ways to connect. Name both:
  "Connect" (quick; for Gmail, Sheets, Slack and HubSpot it signs in through Activepieces'
  `secrets.activepieces.com`, which then sees the tokens; the builder calls the others "Try another
  method") and an own-credential option with no third
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

## Tests
- Code steps are tested offline with node (`opskit/tests/flows_code.bats`): good input, each failure,
  edge cases.
- `test.runs` in `template.yaml`: payloads replayed by `opskit selftest` (CI) on a stub copy of the
  flow: steps of pieces listed in `connections` become code steps that return their input, or the
  run's `stubs` file (e.g. the rows a Sheets read would return); a non-webhook trigger becomes a
  webhook whose body is the payload. Each run must end with `expect` and may list steps that must have
  run (`ran`) or not (`not_ran`). `test.set` gives placeholder values for the test (e.g. a 1-minute
  wait). Real accounts are covered by `CHECKLIST.md`.

## Switched off until tested
- Imported flows are drafts (not published) = off. Order for the client: connect accounts → test with
  `test/` payloads or a real event → publish (switch on) → watch the first real run.
