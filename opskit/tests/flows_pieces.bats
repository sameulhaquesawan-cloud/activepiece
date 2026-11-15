#!/usr/bin/env bats

load helpers/common

setup() {
  WORK="$(mktemp -d)"
  export OPSKIT_FLOWS_DIR="${WORK}/flows"
  export OPSKIT_PIECES_METADATA_DIR="${WORK}/meta"
  mkdir -p "$OPSKIT_FLOWS_DIR" "$OPSKIT_PIECES_METADATA_DIR"
  cp -r "${OPSKIT_ROOT}/flows/example" "${OPSKIT_FLOWS_DIR}/example"
  T="${OPSKIT_FLOWS_DIR}/example"
  jq -n '{name: "@activepieces/piece-webhook", version: "0.1.42", actions: {}, triggers: {catch_webhook: {props: {
      authType: {type: "STATIC_DROPDOWN", required: true},
      authFields: {type: "DYNAMIC", required: true},
      tags: {type: "ARRAY", required: false},
      strict: {type: "CHECKBOX", required: true},
      note: {type: "MARKDOWN", required: false}}}}}' > "${OPSKIT_PIECES_METADATA_DIR}/activepieces_piece-webhook@0.1.42.json"
}

teardown() {
  rm -rf "$WORK"
}

edit_trigger_input() {
  jq ".flows[0].trigger.settings.input |= ($1)" "${T}/flow.json" > "${WORK}/f.json" && mv "${WORK}/f.json" "${T}/flow.json"
}

@test "inputs that match the piece definition pass; false is a value, dynamic fields may wait for the client" {
  edit_trigger_input '{authType: "none", tags: [], strict: false}'
  run "$OPSKIT" flows check-pieces example
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] example: piece inputs match the catalog"* ]]
}

@test "a missing optional list, an empty required input and an unknown input are reported" {
  edit_trigger_input '{authType: "", strict: true, typo: 1}'
  run "$OPSKIT" flows check-pieces example
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] example: trigger: list input tags must be present (use []) or the builder marks the step Incomplete"* ]]
  [[ "$output" == *"[fail] example: trigger: required input authType is empty"* ]]
  [[ "$output" == *"[fail] example: trigger: unknown input typo"* ]]
}

@test "a trigger the piece version does not have is reported" {
  jq '.flows[0].trigger.settings.triggerName = "nope"' "${T}/flow.json" > "${WORK}/f.json" && mv "${WORK}/f.json" "${T}/flow.json"
  run "$OPSKIT" flows check-pieces example
  [ "$status" -eq 1 ]
  [[ "$output" == *"trigger: nope does not exist in @activepieces/piece-webhook 0.1.42"* ]]
}

@test "missing metadata is a failure, not a pass" {
  rm "${OPSKIT_PIECES_METADATA_DIR}"/*
  run "$OPSKIT" flows check-pieces example
  [ "$status" -eq 1 ]
  [[ "$output" == *"no metadata for @activepieces/piece-webhook 0.1.42"* ]]
}

@test "every template matches the live Activepieces catalog" {
  unset OPSKIT_FLOWS_DIR OPSKIT_PIECES_METADATA_DIR
  if ! curl -s -m 10 -o /dev/null "https://cloud.activepieces.com/api/v1/pieces?limit=1"; then
    [ "${OPSKIT_REQUIRE_PIECES:-0}" != "1" ] || { echo "catalog unreachable"; return 1; }
    skip "Activepieces catalog not reachable"
  fi
  run "$OPSKIT" flows check-pieces
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "check-pins: a pin still offered to new stacks passes; custom pieces are skipped" {
  export OPSKIT_FLOWS_DIR="${OPSKIT_ROOT}/flows"
  jq -n '[{name: "@activepieces/piece-openai", version: "0.1.0"}]' > "${WORK}/registry.json"
  yq -o=json '[.pieces[] | select(.custom == null) | {"name": .name, "version": .version}]' "${OPSKIT_ROOT}/flows/ai-email-sorter/template.yaml" \
    | jq --slurpfile extra "${WORK}/registry.json" '. + $extra[0]' > "${WORK}/registry-all.json"
  OPSKIT_PIECES_REGISTRY_FILE="${WORK}/registry-all.json" run "$OPSKIT" flows check-pins ai-email-sorter
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] ai-email-sorter: pinned pieces are offered to new 0.92.3 stacks"* ]]
}

@test "check-pins: a pin dropped from the catalog fails and names the offered version" {
  jq -n '[{name: "@activepieces/piece-webhook", version: "0.1.43"}]' > "${WORK}/registry.json"
  OPSKIT_PIECES_REGISTRY_FILE="${WORK}/registry.json" run "$OPSKIT" flows check-pins example
  [ "$status" -eq 1 ]
  [[ "$output" == *"@activepieces/piece-webhook 0.1.42 is no longer offered to new"*"(offered: 0.1.43)"* ]]
}

@test "check-pins: no catalog answer is a failure, not a pass" {
  printf '' > "${WORK}/registry.json"
  OPSKIT_PIECES_REGISTRY_FILE="${WORK}/registry.json" run "$OPSKIT" flows check-pins example
  [ "$status" -eq 1 ]
  [[ "$output" == *"no piece list for Activepieces"* ]]
}
