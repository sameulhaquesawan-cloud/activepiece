#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client acme acme.example.com
  yq -i '.timezone = "Europe/Berlin" | .support.included_hours = 3' "${REG}/clients/acme/client.yaml"
}

teardown() {
  rm -rf "$REG"
}

@test "hours: entries add up per month and are shown against the included hours" {
  run "$OPSKIT" hours acme add 1.5 "changed the invoice reminder text" --date 2026-10-03
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] 1.5 h logged for acme on 2026-10-03"* ]]
  "$OPSKIT" hours acme add 0.25 "checked a failed run" --date 2026-10-31 >/dev/null
  "$OPSKIT" hours acme add 2 "new flow" --date 2026-11-01 >/dev/null
  run "$OPSKIT" hours acme list --month 2026-10
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-10-03  1.5 h  changed the invoice reminder text"* ]]
  [[ "$output" != *"new flow"* ]]
  [[ "$output" == *"2026-10: 1.75 h used of 3 h included"* ]]
}

@test "hours: bad numbers, dates, long or secret-looking notes are refused" {
  run "$OPSKIT" hours acme add 0 "x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"hours must be a number above 0"* ]]
  run "$OPSKIT" hours acme add 25 "x"
  [ "$status" -eq 1 ]
  run "$OPSKIT" hours acme add 1,5 "x"
  [ "$status" -eq 1 ]
  run "$OPSKIT" hours acme add 1 "x" --date 2026-02-30
  [ "$status" -eq 1 ]
  [[ "$output" == *"date must be YYYY-MM-DD"* ]]
  run "$OPSKIT" hours acme add 1 "$(printf 'y%.0s' {1..301})"
  [ "$status" -eq 1 ]
  run "$OPSKIT" hours acme add 1 "pasted sk-$(printf 'a%.0s' {1..24}) by mistake"
  [ "$status" -eq 1 ]
  [[ "$output" == *"looks like it contains a key"* ]]
  [ ! -f "${REG}/clients/acme/hours.jsonl" ]
}

@test "incidents: logged in the client's time zone, listed by the client's month" {
  run "$OPSKIT" incident acme add "Gmail was down for 2 hours; flows retried later" --at 2026-11-01T00:30
  [ "$status" -eq 0 ]
  [[ "$output" == *"incident logged for acme at 2026-10-31T23:30:00Z"* ]]
  "$OPSKIT" incident acme add "wrong reply text sent twice; fixed" --at 2026-10-15T10:00 >/dev/null
  run "$OPSKIT" incident acme list --month 2026-10
  [[ "$output" == *"2026-10-15T08:00:00Z  wrong reply text sent twice; fixed"* ]]
  [[ "$output" != *"Gmail was down"* ]]
  run "$OPSKIT" incident acme list --month 2026-11
  [[ "$output" == *"Gmail was down"* ]]
  run "$OPSKIT" incident acme add "x" --at 2026-10-15
  [ "$status" -eq 1 ]
  [[ "$output" == *"--at must be YYYY-MM-DDTHH:MM (client time zone Europe/Berlin)"* ]]
}

@test "usage errors and unknown clients" {
  run "$OPSKIT" hours
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: opskit hours"* ]]
  run "$OPSKIT" hours acme add 1
  [ "$status" -eq 1 ]
  run "$OPSKIT" incident nobody list
  [ "$status" -eq 1 ]
  run "$OPSKIT" hours acme list --month 2026-13
  [ "$status" -eq 1 ]
}
