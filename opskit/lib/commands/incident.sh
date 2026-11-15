#!/usr/bin/env bash
# summary: log an incident for a client (care report; downtime, missed backups and rollbacks are counted automatically)

for lib in validate schema registry flows worklog; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

incident_usage() {
  cat <<'USAGE'
Usage: opskit incident <client id> add "<what happened and what was done>" [--at YYYY-MM-DDTHH:MM]
       opskit incident <client id> list [--month YYYY-MM]

Logs something the client should see in the care report that opskit does not count by itself (a third-
party outage, a wrong email sent by a flow, …). Site downtime, nights without a complete backup and
upgrade rollbacks are counted automatically. --at is in the client's time zone (default: now).
Notes: one line, no passwords, keys or customer data.
USAGE
}

cmd_main() {
  local id="${1:-}" action="${2:-}" month="" when="" tz
  case "$id" in -h|--help) incident_usage; return 0 ;; ""|-*) incident_usage >&2; return 1 ;; esac
  require_client "$id" || return 1
  tz="$(yaml_get "$(client_file "$id")" .timezone UTC)"
  case "$action" in
    add)
      [ "$#" -ge 3 ] || { incident_usage >&2; return 1; }
      if [ "$#" -eq 5 ] && [ "$4" = "--at" ]; then when="$5"; elif [ "$#" -ne 3 ]; then incident_usage >&2; return 1; fi
      worklog_incident_add "$id" "$3" "$when"
      ;;
    list)
      if [ "$#" -eq 4 ] && [ "$3" = "--month" ]; then month="$4"; elif [ "$#" -ne 2 ]; then incident_usage >&2; return 1; fi
      [ -n "$month" ] || month="$(TZ="$tz" date +%Y-%m)"
      [[ "$month" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || die "month must be YYYY-MM"
      worklog_incidents_month "$id" "$month" "$tz" | jq -r '.[] | "\(.at)  \(.what)"'
      ;;
    *) incident_usage >&2; return 1 ;;
  esac
}
