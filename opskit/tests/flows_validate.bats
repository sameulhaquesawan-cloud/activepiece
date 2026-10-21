#!/usr/bin/env bats

load helpers/common

setup() {
  WORK="$(mktemp -d)"
  export OPSKIT_FLOWS_DIR="${WORK}/flows"
  mkdir -p "$OPSKIT_FLOWS_DIR"
  cp -r "${OPSKIT_ROOT}/flows/example" "${OPSKIT_FLOWS_DIR}/demo"
  T="${OPSKIT_FLOWS_DIR}/demo"
  yq -i '.template_id = "demo"' "${T}/template.yaml"
}

teardown() {
  rm -rf "$WORK"
}

edit_flow() {
  jq "$1" "${T}/flow.json" > "${WORK}/flow.json" && mv "${WORK}/flow.json" "${T}/flow.json"
}

expect_problem() {
  run "$OPSKIT" flows validate demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] demo: $1"* ]]
  [[ "$output" == *"[fail] demo: invalid"* ]]
}

CODE_INPUT='.flows[0].trigger.nextAction.settings.input'

@test "every template in the library validates" {
  unset OPSKIT_FLOWS_DIR
  run "$OPSKIT" flows validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] example: valid"* ]]
  [[ "$output" != *"[fail]"* ]]
}

@test "list shows each template with its connections" {
  run "$OPSKIT" flows list
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo"*"Example — webhook greeting"*"none"* ]]
  [[ "$output" == *"missing name fails the run"* ]]
}

@test "malformed JSON" {
  printf '{"name": "x", "flows": [' > "${T}/flow.json"
  expect_problem "flow.json: not valid JSON"
}

@test "JSON that is not the Activepieces export format" {
  printf '{"displayName": "x"}\n' > "${T}/flow.json"
  expect_problem "flow.json: needs a name"
  [[ "$output" == *"needs a non-empty flows list"* ]]
}

@test "steps without lastUpdatedDate are rejected (the import would fail)" {
  edit_flow 'del(.flows[0].trigger.nextAction.lastUpdatedDate)'
  expect_problem "flow.json: steps without lastUpdatedDate: step_1"
}

@test "placeholder used but not declared" {
  edit_flow "${CODE_INPUT}.extra = \"{{OPSKIT:OWNER_EMAIL}}\""
  expect_problem "placeholder OWNER_EMAIL is used in flow.json but not declared in template.yaml"
}

@test "placeholder declared but not used" {
  yq -i '.placeholders += [{"key": "SHEET_NAME", "description": "Name of the sheet", "example": "Leads"}]' "${T}/template.yaml"
  expect_problem "placeholder SHEET_NAME is declared in template.yaml but not used in flow.json"
}

@test "malformed placeholder" {
  edit_flow "${CODE_INPUT}.extra = \"{{OPSKIT:owner}}\""
  expect_problem "flow.json: malformed placeholder"
}

@test "step references must use the output form of flow schema 27" {
  edit_flow "${CODE_INPUT}.name = \"{{trigger['body']['name']}}\" | ${CODE_INPUT}.extra = \"{{step_1.greeting}}\""
  expect_problem "flow.json: write step references as {{step_1['output']…}} (flow schema 27): {{step_1.greeting}} {{trigger['body']['name']}}"
}

@test "piece version in flow.json differs from the manifest" {
  edit_flow '.flows[0].trigger.settings.pieceVersion = "0.1.41"'
  expect_problem "piece @activepieces/piece-webhook@0.1.41 is in flow.json but not in template.yaml pieces"
  [[ "$output" == *"piece @activepieces/piece-webhook@0.1.42 is in template.yaml pieces but not used in flow.json"* ]]
}

@test "real email address" {
  edit_flow "${CODE_INPUT}.to = \"jane.doe@acme-dental.com\""
  expect_problem "real-looking email address (use example.com): jane.doe@acme-dental.com"
}

@test "example.com addresses are fine" {
  edit_flow "${CODE_INPUT}.to = \"owner@mail.example.com\""
  run "$OPSKIT" flows validate demo
  [ "$status" -eq 0 ]
}

@test "real email in a test payload" {
  printf '{"name": "Jane", "email": "jane@gmail.com"}\n' > "${T}/test/good.json"
  expect_problem "real-looking email address (use example.com): jane@gmail.com"
}

@test "real URL in flow data" {
  edit_flow "${CODE_INPUT}.url = \"https://hooks.acme.io/abc\""
  expect_problem "real-looking URL in flow/test data"
}

@test "API keys and private links are caught" {
  local key
  local fake="abcdefghijklmnopqrstuvwxyz123456"
  for key in "sk-proj-${fake}" "xox""b-123456789012-${fake:0:10}" \
    "https://docs.google.com/spreadsheets/d/1AbCdEf/edit" "pat-""na1-${fake:0:8}-${fake:8:4}-${fake:12:4}-${fake:16:12}"; do
    cp "${OPSKIT_ROOT}/flows/example/flow.json" "${T}/flow.json"
    edit_flow "${CODE_INPUT}.key = \"${key}\""
    expect_problem "looks like a real key, token or private link"
  done
}

@test "a key in the README is caught too" {
  printf '\nkey: %s\n' "AKIA""ABCDEFGHIJKLMNOP" >> "${T}/README.md"
  expect_problem "looks like a real key, token or private link"
}

@test "connection references must be left empty" {
  edit_flow "${CODE_INPUT}.auth = \"{{connections['acme-gmail']}}\""
  expect_problem "flow.json: a connection is referenced"
}

@test "real-looking ids in step inputs" {
  edit_flow "${CODE_INPUT}.spreadsheet_id = \"1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms\""
  expect_problem "flow.json: real-looking ids in step inputs"
}

@test "a fail-run template may not continue on failure" {
  edit_flow '.flows[0].trigger.nextAction.settings.errorHandlingOptions.continueOnFailure.value = true'
  expect_problem "failure is fail-run but these steps continue on failure: step_1"
}

@test "number and choice placeholders need valid examples and defaults" {
  yq -i '.placeholders[0].type = "number"' "${T}/template.yaml"
  expect_problem "placeholder GREETING: Hello is not a valid number"
  yq -i '.placeholders[0].type = "string" | .placeholders[0].choices = ["Hi", "Hey"]' "${T}/template.yaml"
  expect_problem "placeholder GREETING: Hello is not a valid string (one of: Hi, Hey)"
}

@test "test.set must name declared placeholders with valid values" {
  yq -i '.test.set = {"NOPE": "x"}' "${T}/template.yaml"
  expect_problem "test.set: NOPE is not a declared placeholder"
  yq -i '.test.set = {"GREETING": "Yo"} | .placeholders[0].choices = ["Hello", "Hi"]' "${T}/template.yaml"
  expect_problem "test.set: GREETING=Yo is not valid for that placeholder"
}

@test "sample runs: stub files must exist and named steps must be in the flow" {
  yq -i '.test.runs[0].stubs = {"step_1": "test/nope.json"} | .test.runs[1].not_ran = ["step_9"]' "${T}/template.yaml"
  expect_problem "test payload missing: test/nope.json"
  [[ "$output" == *"test step step_9 does not exist in flow.json"* ]]
}

@test "our custom piece archive must be committed and match its checksum" {
  unset OPSKIT_FLOWS_DIR
  run "$OPSKIT" flows validate ai-email-sorter
  [ "$status" -eq 0 ]
  export OPSKIT_REPO_ROOT="${WORK}/repo"
  local release="${OPSKIT_REPO_ROOT}/packages/pieces/custom/openai-compatible/release"
  run "$OPSKIT" flows validate ai-email-sorter
  [ "$status" -eq 1 ]
  [[ "$output" == *"custom piece archive missing"* ]]
  mkdir -p "$release"
  cp "${OPSKIT_ROOT}/../packages/pieces/custom/openai-compatible/release/"* "$release/"
  printf 'x' >> "${release}/opskit-piece-openai-compatible-0.1.0.tgz"
  run "$OPSKIT" flows validate ai-email-sorter
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match packages/pieces/custom/openai-compatible/release/SHA256SUMS"* ]]
}

@test "missing README, CHECKLIST and test payload" {
  rm "${T}/README.md" "${T}/CHECKLIST.md" "${T}/test/good.json"
  expect_problem "missing file: README.md"
  [[ "$output" == *"missing file: CHECKLIST.md"* ]]
  [[ "$output" == *"test payload missing: test/good.json"* ]]
}

@test "template_id must match the folder" {
  yq -i '.template_id = "other"' "${T}/template.yaml"
  expect_problem "template.yaml: template_id must be the folder name (demo)"
}

@test "schema errors in template.yaml are reported per template" {
  yq -i '.pieces[0].version = "latest"' "${T}/template.yaml"
  expect_problem "template.yaml pieces.0.version: has an invalid format"
}

@test "unknown template" {
  run "$OPSKIT" flows validate nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown template: nope"* ]]
}

@test "one bad template fails the whole run but the others are still checked" {
  cp -r "${OPSKIT_ROOT}/flows/example" "${OPSKIT_FLOWS_DIR}/example"
  printf 'not json' > "${T}/flow.json"
  run "$OPSKIT" flows validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] demo: invalid"* ]]
  [[ "$output" == *"[ok] example: valid"* ]]
}

@test "usage" {
  run "$OPSKIT" flows
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: opskit flows list"* ]]
}

@test "steps of pieces that need the client's account must start incomplete" {
  yq -i '.connections = [{"piece": "@activepieces/piece-webhook", "purpose": "pretend it needs an account", "options": ["Connect"]}]' "${T}/template.yaml"
  expect_problem "steps that need the client's connection must be \"valid\": false: trigger"
}
