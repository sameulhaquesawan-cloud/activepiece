#!/usr/bin/env bash
# summary: log support hours for a client (shown as used vs included in the care report)

for lib in validate schema registry flows worklog; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

hours_usage() {
  cat <<'USAGE'
Usage: opskit hours <client id> add <hours> "<what you did>" [--date YYYY-MM-DD]
       opskit hours <client id> list [--month YYYY-MM]

add   logs work for the client (e.g. 1.5 "changed the invoice reminder text"); date defaults to today in
      the client's time zone. Notes: one line, no passwords, keys or customer data.
list  the entries of a month (default: this month) with the total and the hours included per month
      (client.yaml support.included_hours).
USAGE
}

cmd_main() {
  local id="${1:-}" action="${2:-}" month="" day=""
  case "$id" in -h|--help) hours_usage; return 0 ;; ""|-*) hours_usage >&2; return 1 ;; esac
  require_client "$id" || return 1
  case "$action" in
    add)
      [ "$#" -ge 4 ] || { hours_usage >&2; return 1; }
      if [ "$#" -eq 6 ] && [ "$5" = "--date" ]; then day="$6"; elif [ "$#" -ne 4 ]; then hours_usage >&2; return 1; fi
      worklog_hours_add "$id" "$3" "$4" "$day"
      ;;
    list)
      if [ "$#" -eq 4 ] && [ "$3" = "--month" ]; then month="$4"; elif [ "$#" -ne 2 ]; then hours_usage >&2; return 1; fi
      [ -n "$month" ] || month="$(TZ="$(yaml_get "$(client_file "$id")" .timezone UTC)" date +%Y-%m)"
      [[ "$month" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || die "month must be YYYY-MM"
      local data
      data="$(worklog_hours_month "$id" "$month")"
      jq -r '.entries[] | "\(.date)  \(.hours) h  \(.note)"' <<< "$data"
      log_info "${month}: $(jq -r '.total' <<< "$data") h used of $(yaml_get "$(client_file "$id")" .support.included_hours 1) h included"
      ;;
    *) hours_usage >&2; return 1 ;;
  esac
}
