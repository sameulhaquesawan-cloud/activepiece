#!/usr/bin/env bats

load helpers/common

FIXTURE="${BATS_TEST_DIRNAME}/fixtures/report"

setup() {
  for lib in log report; do source "${OPSKIT_ROOT}/lib/${lib}.sh"; done
  DATA="$(cat "${FIXTURE}/2026-09.json")"
}

@test "the text version of the fixture month matches the golden file" {
  run report_render "$DATA" text
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$output") "${FIXTURE}/2026-09.txt"
}

@test "the HTML version shows the same numbers, local dates, and escapes names" {
  run report_render "$DATA" html
  [ "$status" -eq 0 ]
  [[ "$output" == "<!DOCTYPE html>"* ]]
  [[ "$output" == *">99.976 %</div><div style=\"color:#59636e;font-size:13px\">Availability<"* ]]
  [[ "$output" == *">28 of 30</div>"* ]]
  [[ "$output" == *"<td style=\"padding:6px;border:1px solid #d0d7de\">Lead capture</td><td style=\"padding:6px;border:1px solid #d0d7de\">40</td>"* ]]
  [[ "$output" == *"12 Sep: 10 minutes"* ]]
  run report_render "$(jq '.runs.flows[0].name = "<b>x</b>" | .timezone = "America/New_York"' <<< "$DATA")" html
  [[ "$output" == *"&lt;b&gt;x&lt;/b&gt;"* ]]
  [[ "$output" == *"11 Sep: 10 minutes"* ]]
}

@test "not measured, no backup record, nothing to report read as such" {
  run report_render "$(jq '.uptime = {measured: false} | .backups = {history: false, nights: 0, complete: 0, missing: [], failed_runs: 0, last_complete: null}
    | .restore_test = null | .upgrades = [] | .incidents = [] | .runs = {flows: [], total: 0, succeeded: 0, failed: 0, other: 0}
    | .hours = {used: 0, included: 1, entries: []}' <<< "$DATA")" text
  [[ "$output" == *"Availability: not measured"* ]]
  [[ "$output" == *"Nightly backups: no record"* ]]
  [[ "$output" == *"No flow ran this month."* ]]
  [[ "$output" == *"No backup record exists for this month yet"* ]]
  [[ "$output" == *"No restore test yet."* ]]
  [[ "$output" == *"No version update this month."* ]]
  [[ "$output" == *$'Incidents\nNone.'* ]]
}

@test "last month is computed in the client's time zone" {
  run report_last_month UTC
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}$ ]]
  [ "$output" = "$(date -u -d "$(date -u +%Y-%m-01) -1 month" +%Y-%m)" ]
}
