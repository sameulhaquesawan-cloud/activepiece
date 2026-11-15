#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client acme acme.example.com
  HOSTROOT="$(mktemp -d)"
  yq -i ".opskit_root = \"${HOSTROOT}\"" "${REG}/hosts/local-practice.yaml"
  yq -i '.name = "Acme Dental" | .timezone = "Europe/Berlin" | .support.included_hours = 3
    | .history += [{"at": "2026-09-05T01:00:00Z", "event": "upgraded", "tag": "0.92.3"},
                   {"at": "2026-09-20T01:00:00Z", "event": "upgrade_failed", "tag": "0.93.0"},
                   {"at": "2026-09-20T01:05:00Z", "event": "rolled_back", "tag": "0.92.3"},
                   {"at": "2026-10-02T01:00:00Z", "event": "upgraded", "tag": "0.93.1"}]' "${REG}/clients/acme/client.yaml"
  mkdir -p "${HOSTROOT}/backups/acme"
  local day
  {
    printf '{"at":"2026-08-31T23:30:00Z","backup":"a","result":"complete"}\n'
    for day in $(seq -w 2 30); do
      case "$day" in
        10) printf '{"at":"2026-09-10T00:30:00Z","backup":"","result":"failed","reason":"dump or encryption step failed"}\n' ;;
        11) ;;
        *) printf '{"at":"2026-09-%sT00:30:00Z","backup":"b","result":"complete"}\n' "$day" ;;
      esac
    done
    printf '{"at":"2026-09-30T22:30:00Z","backup":"c","result":"complete"}\n'
  } > "${HOSTROOT}/backups/acme/history.jsonl"
  printf '{"at":"2026-09-02T03:00:00Z","backup":"x","result":"pass","seconds":40}\n{"at":"2026-10-02T03:00:00Z","backup":"y","result":"fail","seconds":40}\n' \
    > "${REG}/clients/acme/restore-tests.jsonl"
  printf '{"at":"2026-09-15T08:00:00Z","what":"Gmail outage, flows retried","source":"owner"}\n' > "${REG}/clients/acme/incidents.jsonl"
  printf '{"date":"2026-09-03","hours":1.5,"note":"changed reminder text"}\n{"date":"2026-10-01","hours":0.5,"note":"later"}\n' \
    > "${REG}/clients/acme/hours.jsonl"
  for lib in log validate schema registry ssh host stack deploy verify render secrets monitor monitor_sync business clientdata flows worklog report; do
    source "${OPSKIT_ROOT}/lib/${lib}.sh"
  done
  clientdata_month_runs() {
    printf '[{"flow_id":"f1","name":"Lead capture","total":40,"succeeded":38,"failed":2,"other":0},{"flow_id":"f2","name":"Invoice reminder","total":30,"succeeded":30,"failed":0,"other":0}]'
  }
  monitor_uptime() {
    printf '{"measured":true,"up":43190,"down":10,"uptime":99.976,"down_periods":[{"start":"2026-09-12T03:00:00Z","end":"2026-09-12T03:10:00Z","minutes":10}]}'
  }
}

teardown() {
  rm -rf "$REG" "$HOSTROOT"
}

@test "a past month gives exactly the expected report data" {
  run report_collect acme 2026-09
  [ "$status" -eq 0 ]
  [ "$(jq -c 'del(.generated)' <<< "$output")" = "$(jq -c . <<'JSON'
{"month":"2026-09","label":"September 2026","timezone":"Europe/Berlin",
 "client":{"name":"Acme Dental","domain":"acme.example.com","included_hours":3},
 "business":{"name":"YourBrand","email":"support@yourbrand.example","signature":"Thanks for working with us. — YourBrand"},
 "runs":{"flows":[{"name":"Lead capture","total":40,"succeeded":38,"failed":2,"other":0},{"name":"Invoice reminder","total":30,"succeeded":30,"failed":0,"other":0}],
   "total":70,"succeeded":68,"failed":2,"other":0},
 "uptime":{"measured":true,"up":43190,"down":10,"uptime":99.976,"down_periods":[{"start":"2026-09-12T03:00:00Z","end":"2026-09-12T03:10:00Z","minutes":10}]},
 "backups":{"history":true,"nights":30,"complete":28,"missing":["2026-09-10","2026-09-11"],"failed_runs":1,"last_complete":"2026-09-30T00:30:00Z"},
 "restore_test":{"at":"2026-09-02T03:00:00Z","result":"pass"},
 "upgrades":[{"at":"2026-09-05T01:00:00Z","event":"upgraded","tag":"0.92.3"},{"at":"2026-09-20T01:00:00Z","event":"upgrade_failed","tag":"0.93.0"},{"at":"2026-09-20T01:05:00Z","event":"rolled_back","tag":"0.92.3"}],
 "incidents":[
   {"at":"2026-09-10T12:00:00Z","what":"No complete backup that night","source":"backup"},
   {"at":"2026-09-11T12:00:00Z","what":"No complete backup that night","source":"backup"},
   {"at":"2026-09-12T03:00:00Z","what":"Your system did not answer for 10 minute(s)","source":"uptime"},
   {"at":"2026-09-15T08:00:00Z","what":"Gmail outage, flows retried","source":"owner"},
   {"at":"2026-09-20T01:05:00Z","what":"An upgrade was rolled back to 0.92.3 automatically","source":"upgrade"}],
 "hours":{"used":1.5,"included":3,"entries":[{"date":"2026-09-03","hours":1.5,"note":"changed reminder text"}]}}
JSON
)" ]
}

@test "no backup history, no Kuma and no restore test are reported as such, not as zeros that look fine" {
  rm -f "${HOSTROOT}/backups/acme/history.jsonl" "${REG}/clients/acme/restore-tests.jsonl"
  monitor_uptime() { printf '{"measured":false,"reason":"no Uptime Kuma host"}'; }
  run report_collect acme 2026-09
  [ "$status" -eq 0 ]
  [ "$(jq -c '.backups | {history, complete}' <<< "$output")" = '{"history":false,"complete":0}' ]
  [ "$(jq -c '.uptime.measured, .restore_test' <<< "$output" | paste -sd' ')" = "false null" ]
}

@test "nights before the client's first deploy are not counted as missing backups" {
  yq -i '.history = [{"at": "2026-09-08T10:00:00Z", "event": "deployed", "tag": "0.92.3"}] + .history' "${REG}/clients/acme/client.yaml"
  run report_collect acme 2026-09
  [ "$status" -eq 0 ]
  [ "$(jq -c '.backups | {nights, complete, missing}' <<< "$output")" = '{"nights":22,"complete":20,"missing":["2026-09-10","2026-09-11"]}' ]
  yq -i '.history[0].at = "2026-09-12T10:00:00Z"' "${REG}/clients/acme/client.yaml"
  run report_collect acme 2026-09
  [ "$(jq -c '(.backups | {nights, complete, missing}), [.incidents[] | select(.source == "backup")]' <<< "$output" | paste -sd' ')" = '{"nights":18,"complete":18,"missing":[]} []' ]
}

@test "a bad month or an unreadable database stops the report" {
  run report_collect acme 2026-9
  [ "$status" -eq 1 ]
  clientdata_month_runs() { return 1; }
  run report_collect acme 2026-09
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not read acme's runs"* ]]
}

@test "report_build writes the month's html, text and data, numbers taken from the data" {
  run report_build acme 2026-09
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] care report acme 2026-09: 70 runs (2 failed), availability 99.976 %, backups 28/30, 5 incident(s), 1.5/3 h"* ]]
  [ -s "${REG}/clients/acme/reports/2026-09.html" ]
  [ "$(jq -r '.runs.total' "${REG}/clients/acme/reports/2026-09.json")" = "70" ]
  grep -q "^Flow runs: 70$" "${REG}/clients/acme/reports/2026-09.txt"
  grep -q "Acme Dental" "${REG}/clients/acme/reports/2026-09.html"
}

@test "opskit report: usage and unknown client" {
  run "$OPSKIT" report
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: opskit report"* ]]
  run "$OPSKIT" report nobody --month 2026-09
  [ "$status" -eq 1 ]
  run "$OPSKIT" report acme --month 2026-09 extra
  [ "$status" -eq 1 ]
}
