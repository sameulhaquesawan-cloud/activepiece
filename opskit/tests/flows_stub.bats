#!/usr/bin/env bats

load helpers/common

setup() {
  for lib in log registry flows flows_import e2e_flows; do
    # shellcheck source=/dev/null
    source "${OPSKIT_ROOT}/lib/${lib}.sh"
  done
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK"
}

# filled <template>: the template filled like the selftest does (test.set, else examples)
filled() {
  local dir="${OPSKIT_ROOT}/flows/$1" sets=() pairs=() i
  mapfile -t sets < <(e2e_flow_sets "${dir}/template.yaml")
  for ((i = 1; i < ${#sets[@]}; i += 2)); do pairs+=("${sets[$i]}"); done
  flows_fill "$dir" "$(flows_values "$dir" "${pairs[@]}")" > "${WORK}/$1.json"
}

stubbed() {
  filled "$1"
  e2e_flow_stubbed "${OPSKIT_ROOT}/flows/$1" "${WORK}/$1.json" "$2" 0.1.42 > "${WORK}/request.json"
}

steps() {
  jq -c '[.request.trigger | .. | objects | select(has("type") and has("name") and has("settings")) | [.name, .type]]' "${WORK}/request.json"
}

@test "test values: test.set wins, then examples for placeholders without default" {
  run e2e_flow_sets "${OPSKIT_ROOT}/flows/review-request/template.yaml"
  [[ "$output" == *"WAIT_AMOUNT=1"* ]]
  [[ "$output" == *"WAIT_UNIT=minutes"* ]]
  [[ "$output" == *"REVIEW_URL=https://example.com/review"* ]]
  [[ "$output" != *"SUBJECT="* ]]
}

@test "lead capture: Sheets and Gmail steps become code steps returning their input" {
  stubbed lead-capture 0
  [ "$(jq -r .type "${WORK}/request.json")" = "IMPORT_FLOW" ]
  [ "$(jq -r .request.displayName "${WORK}/request.json")" = "Lead capture (opskit stub test)" ]
  [ "$(steps)" = '[["trigger","PIECE_TRIGGER"],["step_1","CODE"],["step_2","CODE"],["step_3","CODE"],["step_4","CODE"]]' ]
  [ "$(jq -r '.request.trigger.settings.pieceName' "${WORK}/request.json")" = "@activepieces/piece-webhook" ]
  [ "$(jq -r '.request.trigger.nextAction.nextAction.settings.sourceCode.code' "${WORK}/request.json")" = "export const code = async (inputs) => inputs;" ]
  [ "$(jq -r '.request.trigger.nextAction.nextAction.nextAction.settings.input.receiver[0]' "${WORK}/request.json")" = "owner@example.com" ]
  ! grep -q 'OPSKIT:' "${WORK}/request.json"
}

@test "invoice reminder: the schedule becomes a webhook, trigger refs follow, the sheet read returns the stub rows" {
  stubbed invoice-reminder 1
  [ "$(jq -r '.request.trigger | [.settings.pieceName, .settings.triggerName] | join(" ")' "${WORK}/request.json")" = "@activepieces/piece-webhook catch_webhook" ]
  [ "$(jq -r '.request.trigger.nextAction.type' "${WORK}/request.json")" = "CODE" ]
  [[ "$(jq -r '.request.trigger.nextAction.settings.sourceCode.code' "${WORK}/request.json")" == *'"typo-at-example.com"'* ]]
  [ "$(jq -r '[.. | objects | select(.name? == "step_3")][0].type' "${WORK}/request.json")" = "LOOP_ON_ITEMS" ]
  [ "$(jq -r '[.. | objects | select(.name? == "step_5")][0].settings.input.row_id' "${WORK}/request.json")" = "{{step_3['output']['item']['row']}}" ]
}

@test "invoice reminder: a stubbed step's code runs and returns the stub" {
  stubbed invoice-reminder 0
  jq -r '.request.trigger.nextAction.settings.sourceCode.code' "${WORK}/request.json" > "${WORK}/stub.mjs"
  printf '\nconsole.log(JSON.stringify(await code({})));\n' >> "${WORK}/stub.mjs"
  run node "${WORK}/stub.mjs"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[].values.Invoice]' <<< "$output")" = '["INV-1001","INV-1002","INV-1003","INV-1004"]' ]
}

@test "review request: only SMTP is stubbed; store and delay run for real with typed test values" {
  stubbed review-request 0
  [ "$(jq -r '[.. | objects | select(.name? == "step_7")][0].type' "${WORK}/request.json")" = "CODE" ]
  [ "$(jq -r '[.. | objects | select(.name? == "step_2")][0].settings.pieceName' "${WORK}/request.json")" = "@activepieces/piece-store" ]
  [ "$(jq -c '[.. | objects | select(.name? == "step_6")][0].settings.input' "${WORK}/request.json")" = '{"delayFor":1,"unit":"minutes"}' ]
  [ "$(jq -c '[.. | objects | select(.name? == "step_4")][0].children[1]' "${WORK}/request.json")" = "null" ]
}

@test "trigger references are rewritten only when the trigger is replaced" {
  printf '%s' '{"name":"t","flows":[{"displayName":"x","schemaVersion":"27","trigger":{"name":"trigger","type":"PIECE_TRIGGER","lastUpdatedDate":"d","settings":{"pieceName":"@activepieces/piece-gmail"},"nextAction":{"name":"step_1","type":"CODE","lastUpdatedDate":"d","settings":{"input":{"s":"{{trigger['"'"'output'"'"']['"'"'subject'"'"']}}"}}}}}]}' > "${WORK}/g.json"
  jq --argjson pieces '["@activepieces/piece-gmail"]' --argjson stubs '{}' --arg webhookVersion 0.1.42 -f "$E2E_STUB_JQ" "${WORK}/g.json" > "${WORK}/out.json"
  [ "$(jq -r '.trigger.nextAction.settings.input.s' "${WORK}/out.json")" = "{{trigger['output']['body']['subject']}}" ]
  stubbed lead-capture 0
  [ "$(jq -r '.request.trigger.nextAction.settings.input.body' "${WORK}/request.json")" = "{{trigger['output']['body']}}" ]
}

@test "ai email sorter: Gmail trigger becomes a webhook carrying the trigger output; AI, labels and Slack are stubbed" {
  stubbed ai-email-sorter 0
  [ "$(jq -r '.request.trigger.settings.pieceName' "${WORK}/request.json")" = "@activepieces/piece-webhook" ]
  [ "$(jq -r '.request.trigger.nextAction.settings.input.messageId' "${WORK}/request.json")" = "{{trigger['output']['body']['message']['messageId']}}" ]
  [ "$(jq -r '.request.trigger.nextAction.settings.input.maxChars' "${WORK}/request.json")" = "4000" ]
  [[ "$(jq -r '[.. | objects | select(.name? == "step_2")][0].settings.sourceCode.code' "${WORK}/request.json")" == *'\"category\": \"urgent\"'* ]]
  [ "$(steps | jq -c '[.[] | select(.[1] == "PIECE")]')" = "[]" ]
}
