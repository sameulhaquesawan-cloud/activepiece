#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client demo
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/validate.sh"
  source "${OPSKIT_ROOT}/lib/registry.sh"
  source "${OPSKIT_ROOT}/lib/stack.sh"
  source "${OPSKIT_ROOT}/lib/upgrade_stage.sh"
  TEMP_ID=demo
  TEMP_PORT=18443
  CALLS="$(mktemp)"
  sleep() { :; }
}

teardown() {
  rm -f "$CALLS"
  rm -rf "$REG"
}

smoke_after() {
  eval "smoke_piece_version() { printf x >> '${CALLS}'; [ \"\$(wc -c < '${CALLS}')\" -ge $1 ] && printf '0.1.0'; return 0; }"
}

@test "a copy on Activepieces' catalog is polled until the webhook piece appears" {
  yq -i '.pieces.catalog = "official"' "${REG}/clients/demo/client.yaml"
  smoke_after 3
  run upgrade_stage_wait_webhook demo.localhost tok proj
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$CALLS")" -eq 3 ]
  [[ "$output" == *"waiting for the copy to load Activepieces' piece catalog"* ]]
}

@test "a copy on Activepieces' catalog gives up after UPGRADE_STAGE_PIECE_WAIT_S" {
  yq -i '.pieces.catalog = "official"' "${REG}/clients/demo/client.yaml"
  smoke_after 1000
  UPGRADE_STAGE_PIECE_WAIT_S=30 run upgrade_stage_wait_webhook demo.localhost tok proj
  [ "$status" -eq 1 ]
  [ "$(wc -c < "$CALLS")" -eq 4 ]
}

@test "a frozen copy is asked once, without waiting" {
  smoke_after 1000
  run upgrade_stage_wait_webhook demo.localhost tok proj
  [ "$status" -eq 1 ]
  [ "$(wc -c < "$CALLS")" -eq 1 ]
  [[ "$output" != *"waiting"* ]]
}
