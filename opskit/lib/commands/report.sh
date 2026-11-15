#!/usr/bin/env bash
# summary: monthly care report for a client (runs, availability, backups, updates, incidents, hours); --send emails it

for lib in validate schema registry ssh host stack deploy verify render secrets monitor monitor_sync business clientdata flows worklog report report_send; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

report_usage() {
  cat <<'USAGE'
Usage: opskit report <client id> [--month YYYY-MM] [--send [--resend]]
       opskit report --all [--month YYYY-MM] [--send [--resend]]

Writes opskit/clients/<id>/reports/<month>.html (email/printable), .txt and .json for one calendar month in
the client's time zone (default: last month): runs per flow with failures, availability and interruptions
(Uptime Kuma), nightly backups and the last restore test, version updates, incidents (automatic + opskit
incident), support hours used vs included (opskit hours). Totals only: no error texts or data from runs.
Reads the client's database with the read-only role; changes nothing on the client.
--send    emails it to client.yaml report.recipients, copy to you, through your SMTP account in
          opskit/owner/alerts.conf (SMTP_URL, SMTP_FROM, SMTP_USER, SMTP_PASSWORD, OWNER_EMAIL). A month is
          sent once; --resend sends it again.
--all     every deployed client (for the 1st of the month; one failure does not stop the others).
USAGE
}

cmd_main() {
  local id="" month="" send="false" resend="false" all="false"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) report_usage; return 0 ;;
      --month) month="${2:-}"; shift 2 || { report_usage >&2; return 1; } ;;
      --send) send="true"; shift ;;
      --resend) resend="true"; shift ;;
      --all) all="true"; shift ;;
      -*) report_usage >&2; return 1 ;;
      *) if [ -z "$id" ]; then id="$1"; else report_usage >&2; return 1; fi; shift ;;
    esac
  done
  if { [ "$all" = "true" ] && [ -n "$id" ]; } || { [ "$all" = "false" ] && [ -z "$id" ]; } || { [ "$resend" = "true" ] && [ "$send" = "false" ]; }; then
    report_usage >&2
    return 1
  fi
  if [ -n "$month" ] && ! [[ "$month" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    die "month must be YYYY-MM"
  fi
  business_check || return 1
  if [ "$all" = "true" ]; then
    report_all "$month" "$send" "$resend"
    return
  fi
  require_client "$id" || return 1
  [ -n "$month" ] || month="$(report_last_month "$(yaml_get "$(client_file "$id")" .timezone UTC)")"
  if [ "$send" = "true" ] && [ "$resend" != "true" ] && report_sent_before "$id" "$month"; then
    report_send "$id" "$month"
    return
  fi
  report_build "$id" "$month" || return 1
  [ "$send" != "true" ] || report_send "$id" "$month" "$resend"
}
