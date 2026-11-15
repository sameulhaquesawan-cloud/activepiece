#!/usr/bin/env bash
# Owner-kept logs per client for the care report: hours worked (clients/<id>/hours.jsonl, one line per entry,
# local date) and incidents (clients/<id>/incidents.jsonl, UTC time). Notes are short, never secrets or
# customer data. Needs registry.sh and flows.sh (FLOWS_SECRET_PATTERNS).

worklog_file() {
  printf '%s/%s.jsonl' "$(client_dir "$1")" "$2"
}

# worklog_text_ok <text>: 1–300 characters, one line, nothing that looks like a key
worklog_text_ok() {
  local text="$1" pattern
  if [ -z "$text" ] || [ "${#text}" -gt 300 ] || [[ "$text" == *$'\n'* ]]; then
    log_fail "the note must be one line of 1–300 characters"
    return 1
  fi
  for pattern in "${FLOWS_SECRET_PATTERNS[@]}"; do
    if grep -qE -- "$pattern" <<< "$text"; then
      log_fail "the note looks like it contains a key or token; leave secrets out of notes"
      return 1
    fi
  done
}

# worklog_hours_add <id> <hours> <note> [YYYY-MM-DD]: date defaults to today in the client's time zone
worklog_hours_add() {
  local id="$1" hours="$2" note="$3" day="${4:-}"
  if ! [[ "$hours" =~ ^([0-9]{1,2})(\.[0-9]{1,2})?$ ]] || ! awk -v h="$hours" 'BEGIN { exit !(h > 0 && h <= 24) }'; then
    log_fail "hours must be a number above 0 and at most 24 (e.g. 0.5, 1.25)"
    return 1
  fi
  [ -n "$day" ] || day="$(TZ="$(yaml_get "$(client_file "$id")" .timezone UTC)" date +%Y-%m-%d)"
  if ! [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! date -d "$day" +%F >/dev/null 2>&1; then
    log_fail "date must be YYYY-MM-DD"
    return 1
  fi
  worklog_text_ok "$note" || return 1
  jq -nc --arg date "$day" --argjson hours "$hours" --arg note "$note" '{date: $date, hours: $hours, note: $note}' \
    >> "$(worklog_file "$id" hours)"
  log_ok "${hours} h logged for ${id} on ${day}"
}

# worklog_hours_month <id> <YYYY-MM>: JSON {total, entries: [...]}
worklog_hours_month() {
  local file
  file="$(worklog_file "$1" hours)"
  [ -f "$file" ] || { printf '{"total":0,"entries":[]}'; return 0; }
  jq -sc --arg m "$2" '[.[] | select(.date | startswith($m + "-"))] | {total: (map(.hours) | add // 0 | . * 100 | round / 100), entries: .}' "$file"
}

# worklog_incident_add <id> <what> [YYYY-MM-DDTHH:MM in the client's time zone]
worklog_incident_add() {
  local id="$1" what="$2" when="${3:-}" tz at
  tz="$(yaml_get "$(client_file "$id")" .timezone UTC)"
  worklog_text_ok "$what" || return 1
  if [ -n "$when" ]; then
    if ! [[ "$when" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$ ]] \
      || ! at="$(date -u -d "TZ=\"${tz}\" ${when/T/ }" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
      log_fail "--at must be YYYY-MM-DDTHH:MM (client time zone ${tz})"
      return 1
    fi
  else
    at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi
  jq -nc --arg at "$at" --arg what "$what" '{at: $at, what: $what, source: "owner"}' >> "$(worklog_file "$id" incidents)"
  log_ok "incident logged for ${id} at ${at}"
}

# worklog_incidents_month <id> <YYYY-MM> <time zone>: JSON array of owner-logged incidents in that local month
worklog_incidents_month() {
  local file from to
  file="$(worklog_file "$1" incidents)"
  [ -f "$file" ] || { printf '[]'; return 0; }
  from="$(date -u -d "TZ=\"$3\" $2-01 00:00" +%s)"
  to="$(date -u -d "TZ=\"$3\" $(date -d "$2-01 +1 month" +%Y-%m-%d) 00:00" +%s)"
  jq -sc --argjson from "$from" --argjson to "$to" '[.[] | select((.at | fromdate) >= $from and (.at | fromdate) < $to)]' "$file"
}
