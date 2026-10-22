#!/usr/bin/env bash
# summary: monthly care report for a client (runs, availability, backups, updates, incidents, hours)

for lib in validate schema registry ssh host stack deploy verify render secrets monitor monitor_sync business clientdata flows worklog report; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

report_usage() {
  cat <<'USAGE'
Usage: opskit report <client id> [--month YYYY-MM]

Writes opskit/clients/<id>/reports/<month>.html (email/printable), .txt and .json for one calendar month in
the client's time zone (default: last month): runs per flow with failures, availability and interruptions
(Uptime Kuma), nightly backups and the last restore test, version updates, incidents (automatic + opskit
incident), support hours used vs included (opskit hours). Totals only: no error texts or data from runs.
Reads the client's database with the read-only role; changes nothing.
USAGE
}

cmd_main() {
  local id="" month=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) report_usage; return 0 ;;
      --month) month="${2:-}"; shift 2 || { report_usage >&2; return 1; } ;;
      -*) report_usage >&2; return 1 ;;
      *) if [ -z "$id" ]; then id="$1"; else report_usage >&2; return 1; fi; shift ;;
    esac
  done
  [ -n "$id" ] || { report_usage >&2; return 1; }
  require_client "$id" || return 1
  [ -n "$month" ] || month="$(report_last_month "$(yaml_get "$(client_file "$id")" .timezone UTC)")"
  business_check || return 1
  report_build "$id" "$month"
}
