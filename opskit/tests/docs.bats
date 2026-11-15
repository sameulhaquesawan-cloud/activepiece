#!/usr/bin/env bats

load helpers/common
load helpers/registry

FLOWS='[
 {"name":"Lead capture","trigger_piece":"@activepieces/piece-webhook","trigger":"catch_webhook","pieces":["@activepieces/piece-gmail","@activepieces/piece-google-sheets","@activepieces/piece-webhook"],"last_run":"2026-10-21T08:00:00+00:00"},
 {"name":"AI email sorter","trigger_piece":"@activepieces/piece-gmail","trigger":"gmail_new_email_received","pieces":["@activepieces/piece-gmail","@opskit/piece-openai-compatible","@activepieces/piece-slack"],"last_run":null}
]'

setup() {
  make_registry
  new_demo_client acme acme.example.com
  yq -i '.name = "Acme Dental" | .backup.remote = "offsite:acme" | .alerts.channels = ["email", "telegram"]' "${REG}/clients/acme/client.yaml"
  yq -i '.location = "Germany (Falkenstein)" | .provider = "Hetzner"' "${REG}/hosts/local-practice.yaml"
  mkdir -p "${REG}/owner"
  printf 'business_name: Bright Ops\nsupport_email: help@brightops.example\nsupport_hours: Mon–Fri 9–17 CET\nsignature: Thanks — Bright Ops\n' > "${REG}/owner/business.yaml"
  printf '{"at":"2026-10-02T03:00:00Z","backup":"x","result":"pass","seconds":40}\n' > "${REG}/clients/acme/restore-tests.jsonl"
  for lib in log validate schema registry ssh host stack deploy verify business clientdata flows docs; do source "${OPSKIT_ROOT}/lib/${lib}.sh"; done
  clientdata_active_flows() { printf '%s' "$FLOWS"; }
  PACK="${REG}/clients/acme/docs/handover.html"
}

teardown() {
  rm -rf "$REG"
}

@test "every active flow is listed with what it does, its accounts and how to pause it" {
  run docs_build acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] handover pack for acme"*"(2 active flow(s))"* ]]
  local html
  html="$(cat "$PACK")"
  [[ "$html" == *"<h3>Lead capture</h3>"* ]]
  [[ "$html" == *"<h3>AI email sorter</h3>"* ]]
  [ "$(grep -c 'To pause it:</strong> open <strong>Automations</strong>' "$PACK")" = "2" ]
  [[ "$html" == *"find “Lead capture” and click its switch so the tooltip says “Flow is off”"* ]]
  [[ "$html" == *"Website form → lead saved to Google Sheets"* ]]
  [[ "$html" == *"when data is sent to its web address"* ]]
  [[ "$html" == *"when something new happens in Gmail"* ]]
  [[ "$html" == *"Uses your accounts:</strong> Gmail, Google Sheets</li>"* ]]
  [[ "$html" == *"AI provider (OpenAI-compatible), Gmail, Slack"* ]]
  [[ "$html" == *"Last ran:</strong> 2026-10-21"* ]]
}

@test "the pack has the privacy note, the Zapier checklist, support, backups and the owner's details" {
  docs_build acme >/dev/null
  local html
  html="$(cat "$PACK")"
  [[ "$html" == *"<h2>6. Data and privacy</h2>"* ]]
  [[ "$html" == *"<h2>7. Moving from Zapier or Make</h2>"* ]]
  [[ "$html" == *"located in Germany (Falkenstein) (provider: Hetzner)"* ]]
  [[ "$html" == *"every night at 02:30 (server time), encrypted, kept 14 days on your server and 30 days in a second location"* ]]
  [[ "$html" == *"Last test: 2026-10-02, passed"* ]]
  [[ "$html" == *"within 12 hours"* ]]
  [[ "$html" == *"1 hour(s) of fixes"* ]]
  [[ "$html" == *"help@brightops.example"* ]]
  [[ "$html" == *"prepared by Bright Ops"* ]]
  [[ "$html" == *"(email, telegram)"* ]]
  [[ "$html" == *"https://acme.example.com"* ]]
  [[ "$html" != *"Activepieces logo"* ]]
}

@test "the owner's notes describe flows and accounts; unknown accounts ask who owns them" {
  printf 'notes_for: acme\nflows:\n  AI email sorter: Sorts the info@ inbox into labels.\naccounts:\n  Gmail: Anna; company password manager\n' > "${REG}/clients/acme/notes.yaml"
  docs_build acme >/dev/null
  local html
  html="$(cat "$PACK")"
  [[ "$html" == *"What it does:</strong> Sorts the info@ inbox into labels."* ]]
  [[ "$html" == *"<td>Gmail</td><td>Anna; company password manager</td>"* ]]
  [[ "$html" == *"<td>Slack</td><td>Not recorded yet — please tell us who owns it.</td>"* ]]
  [[ "$html" != *"<td>Webhook</td>"* ]]
}

@test "names are escaped, and a pack with something secret-looking is refused" {
  FLOWS='[{"name":"<script>x</script>","trigger_piece":"@activepieces/piece-schedule","trigger":"every_day","pieces":[],"last_run":null}]'
  docs_build acme >/dev/null
  [[ "$(cat "$PACK")" == *"&lt;script&gt;x&lt;/script&gt;"* ]]
  [[ "$(cat "$PACK")" == *"on a fixed schedule"* ]]
  rm -f "$PACK"
  printf 'notes_for: acme\nwelcome: our key is sk-%s\n' "$(printf 'a%.0s' {1..20})" > "${REG}/clients/acme/notes.yaml"
  run docs_build acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"handover pack: secret-like"* ]]
  [ ! -e "$PACK" ]
}

@test "no switched-on flow still gives a pack; an unreadable database stops it" {
  FLOWS='[]'
  run docs_build acme
  [ "$status" -eq 0 ]
  [[ "$(cat "$PACK")" == *"No flow is switched on at the moment."* ]]
  clientdata_active_flows() { return 1; }
  run docs_build acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not read acme's flows"* ]]
}

@test "opskit docs: usage, unknown client, invalid notes" {
  run "$OPSKIT" docs
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: opskit docs"* ]]
  run "$OPSKIT" docs nobody
  [ "$status" -eq 1 ]
  printf 'notes_for: acme\npassword: x\n' > "${REG}/clients/acme/notes.yaml"
  run "$OPSKIT" docs acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"notes.yaml of acme is invalid"* ]]
}
