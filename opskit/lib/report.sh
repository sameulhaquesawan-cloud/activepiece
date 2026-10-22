#!/usr/bin/env bash
# Care report data (task 7.7): everything for one client and calendar month (client time zone) as one JSON
# object. Totals only: no error texts, no run data, no ids. Needs registry.sh, host.sh, clientdata.sh,
# monitor_sync.sh (monitor_uptime), worklog.sh, business.sh.

# report_window <YYYY-MM> <time zone>: "<from epoch> <to epoch>" of that local month
report_window() {
  printf '%s %s' "$(date -u -d "TZ=\"$2\" $1-01 00:00" +%s)" \
    "$(date -u -d "TZ=\"$2\" $(date -d "$1-01 +1 month" +%Y-%m-%d) 00:00" +%s)"
}

# report_backups <id> <YYYY-MM> <tz> <from> <to>: nights of the month with a complete backup (host history)
report_backups() {
  local id="$1" month="$2" tz="$3" from="$4" to="$5" host history now last_day
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  history="$(host_run "$host" cat "$(host_root "$host")/backups/${id}/history.jsonl" 2>/dev/null || true)"
  now="$(date +%s)"
  last_day=$(( now < to ? now : to ))
  jq -sc --arg tz "$tz" --argjson from "$from" --argjson to "$to" --argjson last "$last_day" --arg month "$month" '
    def local_day: (fromdate | strflocaltime("%Y-%m-%d"));
    [.[] | select((.at | fromdate) >= $from and (.at | fromdate) < $to)] as $runs
    | [range($from + 43200; $last; 86400) | strflocaltime("%Y-%m-%d") | select(startswith($month))] as $days
    | ([$runs[] | select(.result == "complete") | .at | local_day] | unique) as $good
    | {
        history: ($runs | length > 0),
        nights: ($days | length),
        complete: ([$days[] | select(. as $d | $good | index($d))] | length),
        missing: [$days[] | select(. as $d | $good | index($d) | not)],
        failed_runs: ([$runs[] | select(.result == "failed")] | length),
        last_complete: ([.[] | select(.result == "complete" and (.at | fromdate) < $to) | .at] | max)
      }' <<< "$history" 2>/dev/null \
    | TZ="$tz" jq -c . || printf '{"history":false,"nights":0,"complete":0,"missing":[],"failed_runs":0,"last_complete":null}'
}

# report_history_events <id> <from> <to>: upgrade events of the month from client.yaml history
report_history_events() {
  yq -o=json '.history // []' "$(client_file "$1")" \
    | jq -c --argjson from "$2" --argjson to "$3" '[.[] | select((.event == "upgraded" or .event == "upgrade_failed" or .event == "rolled_back")
        and ((.at | fromdate) >= $from) and ((.at | fromdate) < $to)) | {at, event, tag}]'
}

# report_collect <id> <YYYY-MM>: the month's report data
report_collect() {
  local id="$1" month="$2" cfile host tz window from to runs uptime backups restore events logged hours
  [[ "$month" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || { log_fail "month must be YYYY-MM: ${month}"; return 1; }
  cfile="$(client_file "$id")"
  host="$(yaml_get "$cfile" .host.name)"
  tz="$(yaml_get "$cfile" .timezone UTC)"
  window="$(report_window "$month" "$tz")"
  from="${window% *}"
  to="${window#* }"
  runs="$(clientdata_month_runs "$host" "$id" "$month" "$tz")" || { log_fail "could not read ${id}'s runs"; return 1; }
  uptime="$(monitor_uptime "$id" "$from" "$to")" || uptime='{"measured":false,"reason":"Uptime Kuma did not answer"}'
  backups="$(TZ="$tz" report_backups "$id" "$month" "$tz" "$from" "$to")"
  restore="null"
  if [ -f "$(client_dir "$id")/restore-tests.jsonl" ]; then
    restore="$(jq -sc --argjson to "$to" '[.[] | select((.at | fromdate) < $to)] | last // null' "$(client_dir "$id")/restore-tests.jsonl")"
  fi
  events="$(report_history_events "$id" "$from" "$to")"
  logged="$(worklog_incidents_month "$id" "$month" "$tz")"
  hours="$(worklog_hours_month "$id" "$month")"
  jq -n \
    --arg month "$month" --arg tz "$tz" \
    --arg label "$(date -d "${month}-01" '+%B %Y')" \
    --arg generated "$(TZ="$tz" date +%Y-%m-%d)" \
    --argjson client "$(yq -o=json '{"name": .name, "domain": .domain, "included_hours": (.support.included_hours // 1)}' "$cfile")" \
    --argjson business "$(jq -n --arg name "$(business_get business_name)" --arg email "$(business_get support_email)" \
        --arg signature "$(business_get signature)" '{name: $name, email: $email, signature: $signature}')" \
    --argjson runs "$runs" --argjson uptime "$uptime" --argjson backups "$backups" --argjson restore "$restore" \
    --argjson events "$events" --argjson logged "$logged" --argjson hours "$hours" '
    {
      month: $month, label: $label, timezone: $tz, generated: $generated, client: $client, business: $business,
      runs: {
        flows: [$runs[] | {name, total, succeeded, failed, other}],
        total: ([$runs[].total] | add // 0), succeeded: ([$runs[].succeeded] | add // 0),
        failed: ([$runs[].failed] | add // 0), other: ([$runs[].other] | add // 0)
      },
      uptime: $uptime,
      backups: $backups,
      restore_test: (if $restore == null then null else {at: $restore.at, result: $restore.result} end),
      upgrades: $events,
      incidents: (
        [($uptime.down_periods // [])[] | {at: .start, what: "Your system did not answer for \(.minutes) minute(s)", source: "uptime"}]
        + [$backups.missing[] | {at: (. + "T12:00:00Z"), what: "No complete backup on the night of \(.)", source: "backup"}]
        + [$events[] | select(.event == "rolled_back") | {at, what: "An upgrade was rolled back to \(.tag) automatically", source: "upgrade"}]
        + [$logged[] | {at, what, source}]
        | sort_by(.at)
      ),
      hours: {used: $hours.total, included: $client.included_hours, entries: [$hours.entries[] | {date, hours, note}]}
    }'
}
