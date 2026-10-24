#!/usr/bin/env bats

load helpers/common

FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

setup() {
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK"
}

broken_client() {
  yq "$1" "${FIXTURES}/clients/valid.yaml" > "${WORK}/client.yaml"
}

expect_client_error() {
  broken_client "$1"
  run "$OPSKIT" validate "${WORK}/client.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] $2"* ]]
  [[ "$output" == *"[fail] client.yaml: invalid"* ]]
}

@test "valid client and host fixtures pass" {
  run "$OPSKIT" validate "${FIXTURES}/clients/valid.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] valid.yaml: valid"* ]]
  run "$OPSKIT" validate "${FIXTURES}/hosts/valid.yaml"
  [ "$status" -eq 0 ]
}

@test "upgrade history events are valid; an unknown event is not" {
  broken_client '.history += [{"at": "2026-10-22T10:00:00Z", "event": "upgraded", "tag": "0.92.3", "note": "from 0.92.2 in 65 s; app down 15 s"},
    {"at": "2026-10-22T11:00:00Z", "event": "upgrade_failed", "tag": "0.93.0", "note": "verify failed"},
    {"at": "2026-10-22T11:01:00Z", "event": "rolled_back", "tag": "0.92.3", "note": "path restore"}]'
  run "$OPSKIT" validate "${WORK}/client.yaml"
  [ "$status" -eq 0 ]
  expect_client_error '.history += [{"at": "2026-10-22T10:00:00Z", "event": "downgraded"}]' "history.0.event: must be one of"
}

@test "missing required field" {
  expect_client_error 'del(.domain)' "domain: is required"
}

@test "bad client id slug" {
  expect_client_error '.client_id = "Acme Dental"' "client_id: has an invalid format"
}

@test "bad domain" {
  expect_client_error '.domain = "https://acme.com"' "domain: has an invalid format"
}

@test "unknown alert channel (WhatsApp is a later add-on)" {
  expect_client_error '.alerts.channels = ["whatsapp"]' "alerts.channels.0: must be one of: telegram, email, slack"
}

@test "worker replicas below 1" {
  expect_client_error '.workers.replicas = 0' "workers.replicas: must be >= 1"
}

@test "bad host mode" {
  expect_client_error '.host.mode = "cloud"' "host.mode: must be one of: dedicated, shared"
}

@test "root ssh user is rejected" {
  expect_client_error '.host.ssh_user = "root"' "host.ssh_user: this value is not allowed"
}

@test "unknown top-level field" {
  expect_client_error '.colour = "red"' "colour: unknown field"
}

@test "image must be an official Activepieces repo" {
  expect_client_error '.image.repo = "evil/activepieces"' "image.repo: must be one of"
}

@test "slack takes a secret name, never the webhook URL" {
  expect_client_error '.alerts.slack.webhook_secret = "https://hooks.slack.com/services/x"' "alerts.slack.webhook_secret: has an invalid format"
}

@test "host file errors are reported too" {
  yq '.ram_gb = 1 | del(.cpus)' "${FIXTURES}/hosts/valid.yaml" > "${WORK}/host.yaml"
  run "$OPSKIT" validate "${WORK}/host.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] cpus: is required"* ]]
  [[ "$output" == *"[fail] ram_gb: must be >= 2"* ]]
}

@test "file that is not a mapping is rejected" {
  printf -- '- just\n- a list\n' > "${WORK}/list.yaml"
  run "$OPSKIT" validate "${WORK}/list.yaml" --type client
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a valid YAML/JSON mapping"* ]]
}

@test "type cannot be detected without client_id, host_id or template_id" {
  printf 'name: x\n' > "${WORK}/x.yaml"
  run "$OPSKIT" validate "${WORK}/x.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot tell the file type"* ]]
}

TEMPLATE="${BATS_TEST_DIRNAME}/../flows/example/template.yaml"

expect_template_error() {
  yq "$1" "$TEMPLATE" > "${WORK}/template.yaml"
  run "$OPSKIT" validate "${WORK}/template.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] $2"* ]]
  [[ "$output" == *"[fail] template.yaml: invalid"* ]]
}

@test "the example template manifest is valid and detected as a template" {
  run "$OPSKIT" validate "$TEMPLATE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] template.yaml: valid"* ]]
}

@test "every template manifest in the library is valid" {
  local manifest
  for manifest in "${BATS_TEST_DIRNAME}"/../flows/*/template.yaml; do
    run "$OPSKIT" validate "$manifest" --type template
    [ "$status" -eq 0 ] || { echo "$manifest: $output"; return 1; }
  done
}

@test "template: missing pieces list" {
  expect_template_error 'del(.pieces)' "pieces: is required"
}

@test "template: piece version must be exact" {
  expect_template_error '.pieces[0].version = "^0.1.42"' "pieces.0.version: has an invalid format"
}

@test "template: only official or opskit pieces" {
  expect_template_error '.pieces[0].name = "evil-piece"' "pieces.0.name: has an invalid format"
}

@test "template: placeholder keys are capitals" {
  expect_template_error '.placeholders[0].key = "greeting"' "placeholders.0.key: has an invalid format"
}

@test "template: placeholder needs an example" {
  expect_template_error 'del(.placeholders[0].example)' "placeholders.0.example: is required"
}

@test "template: unknown failure mode" {
  expect_template_error '.failure = "ignore"' "failure: must be one of: fail-run, notify-and-fail"
}

@test "template: connection needs ways to connect" {
  expect_template_error '.connections = [{"piece": "@activepieces/piece-gmail", "purpose": "read mail", "options": []}]' "connections.0.options: must NOT have fewer than 1 items"
}

@test "template: sample runs expect SUCCEEDED or FAILED with a test/ payload" {
  expect_template_error '.test.runs[0].expect = "OK"' "test.runs.0.expect: must be one of: SUCCEEDED, FAILED"
  expect_template_error '.test.runs[0].payload = "../secret.json"' "test.runs.0.payload: has an invalid format"
}

@test "template: unknown field" {
  expect_template_error '.api_key = "x"' "api_key: unknown field"
}

@test "a wrong yq flavor gives a clear fix-it message" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/usr/bin/env bash\necho "yq 3.4.3"\n' > "${stub}/yq"
  chmod +x "${stub}/yq"
  PATH="${stub}:${PATH}" run "$OPSKIT" validate "${FIXTURES}/hosts/valid.yaml" --type host
  rm -rf "$stub"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mikefarah yq v4 is required"*"opskit/bin/dev-env"* ]]
}

@test "owner business profile: the example is valid; missing email, bad website and unknown fields fail" {
  run "$OPSKIT" validate "${OPSKIT_ROOT}/templates/business.example.yaml"
  [ "$status" -eq 0 ]
  yq 'del(.support_email) | .website = "http://plain.example" | .logo = "x"' "${OPSKIT_ROOT}/templates/business.example.yaml" > "${WORK}/business.yaml"
  run "$OPSKIT" validate "${WORK}/business.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] support_email: is required"* ]]
  [[ "$output" == *"[fail] website: has an invalid format"* ]]
  [[ "$output" == *"[fail] logo: unknown field"* ]]
}

@test "client notes: flows and accounts take one short sentence each" {
  printf 'notes_for: acme\nflows:\n  Lead capture: Website form leads go to the sales sheet.\naccounts:\n  Gmail: Anna owns it; login in the company password manager.\n' > "${WORK}/notes.yaml"
  run "$OPSKIT" validate "${WORK}/notes.yaml"
  [ "$status" -eq 0 ]
  yq -i '.flows["Lead capture"] = "" | .password = "x"' "${WORK}/notes.yaml"
  run "$OPSKIT" validate "${WORK}/notes.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] password: unknown field"* ]]
  [[ "$output" == *"flows.Lead capture"* ]]
}

@test "included support hours are 0 to 40 per month" {
  broken_client '.support.included_hours = 3'
  run "$OPSKIT" validate "${WORK}/client.yaml"
  [ "$status" -eq 0 ]
  expect_client_error '.support.included_hours = 41' "support.included_hours"
}

@test "app memory below 896m is refused with the reason; 896m, 1g and 1536m pass" {
  expect_client_error '.app.memory_limit = "640m"' "app.memory_limit: must be at least 896m (less runs the app out of JavaScript heap)"
  local value
  for value in 896m 1g 1536m; do
    broken_client ".app.memory_limit = \"${value}\""
    run "$OPSKIT" validate "${WORK}/client.yaml"
    [ "$status" -eq 0 ]
  done
}
