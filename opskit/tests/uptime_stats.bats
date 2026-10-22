#!/usr/bin/env bats

load helpers/common

stats() {
  jq -c -f "${OPSKIT_ROOT}/templates/monitor/uptime-stats.jq" <<< "$1"
}

@test "all up is 100, no beats is not measured (null), never rounded up to 100" {
  [ "$(stats '[["2026-10-01 00:00:00",1],["2026-10-01 00:01:00",1]]' | jq -c '{uptime, down_periods}')" = '{"uptime":100,"down_periods":[]}' ]
  [ "$(stats '[]' | jq -c .uptime)" = "null" ]
  local beats
  beats="$(jq -nc '[range(0; 9999) | ["2026-10-01 00:00:00", 1]] + [["2026-10-01 01:00:00", 0]]')"
  [ "$(stats "$beats" | jq -c .uptime)" = "99.99" ]
}

@test "pending counts as up, maintenance is not counted, down periods end at the next good beat" {
  run stats '[["2026-10-01 00:00:00.5",2],["2026-10-01 00:01:00",0],["2026-10-01 00:02:00",0],["2026-10-01 00:03:30",1],["2026-10-01 00:04:00",3],["2026-10-01 00:05:00",3]]'
  [ "$(jq -c '{up, down, uptime}' <<< "$output")" = '{"up":2,"down":2,"uptime":50}' ]
  [ "$(jq -c '.down_periods' <<< "$output")" = '[{"start":"2026-10-01T00:01:00Z","end":"2026-10-01T00:03:30Z","minutes":3}]' ]
}

@test "a down period still open at the end of the window ends at its last down beat" {
  run stats '[["2026-10-31 22:58:00",1],["2026-10-31 22:59:00",0]]'
  [ "$(jq -c '.down_periods' <<< "$output")" = '[{"start":"2026-10-31T22:59:00Z","end":"2026-10-31T22:59:00Z","minutes":1}]' ]
}

@test "without a monitoring host uptime is 'not measured', never 100" {
  load helpers/registry
  make_registry
  for lib in log validate schema registry render secrets stack ssh host deploy monitor monitor_sync; do source "${OPSKIT_ROOT}/lib/${lib}.sh"; done
  run monitor_uptime acme 1790000000 1790086400
  rm -rf "$REG"
  [ "$status" -eq 0 ]
  [ "$output" = '{"measured":false,"reason":"no Uptime Kuma host"}' ]
}
