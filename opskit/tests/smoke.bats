#!/usr/bin/env bats

load helpers/common

setup() {
  # shellcheck source=/dev/null
  for lib in log deploy verify smoke; do source "${OPSKIT_ROOT}/lib/${lib}.sh"; done
  BASE='{"flows":3,"connections":1,"runs":5,"enabled":2}'
  FAKE_STATES=$'app running\nworker running\npostgres running\nredis running'
  FAKE_COUNTS="$BASE"
  FAKE_DECRYPT="1 0"
  FAKE_MANIFEST='[null,"A1","B2",null,"C3"]'
  FAKE_MIGRATIONS=$'old1\nA1\nB2\nold2\nC3'
  FAKE_RO="0"
  unset OPSKIT_SMOKE_FAIL
  stub_stack
}

stub_stack() {
  stack_compose() { printf '%s\n' "$FAKE_STATES"; }
  stack_service_container() { echo "cid-$3"; }
  stack_connections_decrypt() { echo "$FAKE_DECRYPT"; [[ "$FAKE_DECRYPT" =~ \ 0$ ]]; }
  stack_psql() {
    case "$3" in
      *json_build_object*) echo "$FAKE_COUNTS" ;;
      *migrations*) printf '%s\n' "$FAKE_MIGRATIONS" ;;
    esac
  }
  host_run() {
    case "$*" in
      *migration-manifest.json*) echo "$FAKE_MANIFEST" ;;
      *opskit_ro*) echo "$FAKE_RO" ;;
    esac
  }
  deploy_wait_healthy() { log_ok "app healthy (0s)"; }
  deploy_wait_worker() { log_ok "worker registered (polling the app)"; }
  deploy_check_https() { log_ok "HTTPS health OK"; }
}

@test "every check passes on a healthy stack that matches its baseline" {
  run smoke_production h acme "$BASE" 2026-10-22T10:00:00Z
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] containers of acme: app worker postgres redis running"* ]]
  [[ "$output" == *"[ok] schema of acme: matches the image (5 migrations)"* ]]
  [[ "$output" == *"[ok] counts of acme: 3 flows, 1 connections, 5 runs (none lower than before)"* ]]
  [[ "$output" == *"[ok] enabled flows of acme: 2 (unchanged)"* ]]
  [[ "$output" == *"[ok] connections of acme: all 1 decrypt with the stack's key"* ]]
  [[ "$output" == *"[ok] failed runs of acme: no engine errors since 2026-10-22T10:00:00Z"* ]]
  [[ "$output" != *"[fail]"* ]]
}

@test "a stopped or missing container fails with its name" {
  FAKE_STATES=$'app running\nworker exited\npostgres running'
  run smoke_containers h acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] containers of acme: worker exited, redis missing"* ]]
}

@test "fewer flows, connections or runs than the baseline fail; more is fine" {
  FAKE_COUNTS='{"flows":3,"connections":0,"runs":4,"enabled":2}'
  run smoke_counts h acme "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] counts of acme dropped: connections 0 < 1, runs 4 < 5"* ]]
  FAKE_COUNTS='{"flows":4,"connections":1,"runs":9,"enabled":2}'
  run smoke_counts h acme "$BASE"
  [ "$status" -eq 0 ]
}

@test "a changed number of enabled flows fails" {
  FAKE_COUNTS='{"flows":3,"connections":1,"runs":5,"enabled":1}'
  run smoke_enabled_flows h acme "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] enabled flows of acme: 1 now, 2 before"* ]]
}

@test "connections that do not decrypt point at the encryption key" {
  FAKE_DECRYPT="2 1"
  run smoke_connections_decrypt h acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] connections of acme: 1 of 3 do not decrypt (wrong AP_ENCRYPTION_KEY?)"* ]]
  FAKE_DECRYPT=""
  run smoke_connections_decrypt h acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"decrypt check could not run"* ]]
}

@test "schema: missing migrations and a database newer than the image fail" {
  FAKE_MIGRATIONS=$'old1\nA1\nold2'
  run smoke_schema h acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] schema of acme: 2 migration(s) of the image are not applied"* ]]
  FAKE_MIGRATIONS=$'old1\nA1\nB2\nold2\nC3\nNewer9'
  run smoke_schema h acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"the database has 1 migration(s) this image does not know (database newer than the code)"* ]]
}

@test "engine errors since the switch fail; an unreadable count fails too" {
  FAKE_RO="2"
  run smoke_no_failed_runs h acme 2026-10-22T10:00:00Z
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] failed runs of acme: 2 production run(s) ended in an engine error since 2026-10-22T10:00:00Z"* ]]
  FAKE_RO="permission denied"
  run smoke_no_failed_runs h acme 2026-10-22T10:00:00Z
  [ "$status" -eq 1 ]
  [[ "$output" == *"read-only query did not run"* ]]
}

@test "an injected failure fails only that check, and the set still runs every check" {
  OPSKIT_SMOKE_FAIL=schema run smoke_production h acme "$BASE" 2026-10-22T10:00:00Z
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] smoke schema: injected failure (OPSKIT_SMOKE_FAIL)"* ]]
  [ "$(grep -c '^\[fail\]' <<< "$output")" = "1" ]
  [[ "$output" == *"[ok] failed runs of acme"* ]]
}
