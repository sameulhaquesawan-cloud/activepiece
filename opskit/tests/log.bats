#!/usr/bin/env bats

load helpers/common

setup() {
  source "${OPSKIT_ROOT}/lib/log.sh"
}

@test "log_ok and log_warn print tagged lines on stdout" {
  run log_ok "all good"
  [ "$output" = "[ok] all good" ]
  run log_warn "careful"
  [ "$output" = "[warn] careful" ]
}

@test "log_fail writes to stderr" {
  run bash -c "source '${OPSKIT_ROOT}/lib/log.sh'; log_fail broken 2>/dev/null"
  [ -z "$output" ]
  run bash -c "source '${OPSKIT_ROOT}/lib/log.sh'; log_fail broken 2>&1"
  [ "$output" = "[fail] broken" ]
}

@test "die exits non-zero with a fail line" {
  run bash -c "source '${OPSKIT_ROOT}/lib/log.sh'; die stop here; echo unreachable"
  [ "$status" -eq 1 ]
  [ "$output" = "[fail] stop here" ]
}
