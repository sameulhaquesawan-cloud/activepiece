#!/usr/bin/env bash
# summary: upgrade a client to a newer Activepieces release (plan, pre-pull, lock; staging, switch and rollback follow)

for lib in validate schema registry render secrets confirm stack ssh host deploy verify restore roundtrip e2e practice smoke smoke_flows upgrade upgrade_run upgrade_stage upgrade_switch upgrade_rollback; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

upgrade_usage() {
  cat <<'USAGE'
Usage: opskit upgrade <client id> --to <x.y.z> [--plan | --yes [--now]]
       opskit upgrade <client id> --resume --yes [--now] | --rollback --yes | --unlock

--plan      read-only: checks the target release exists and is newer, lists the breaking changes
            Activepieces documents between the two versions, the database changes (when both
            images are on this machine) and the gates: a backup younger than 26 h with its
            off-server copy, a passed restore test from the last 35 days, free disk and memory on
            the host, free disk here, no other upgrade running. Exit 1 when a gate fails.
(no option) runs the upgrade: gates, lock, waits for a running backup, pulls the image here and on
            the host (same digest), stages it (fresh backup restored into a temporary stack on
            this machine on the new version, checks incl. a webhook and a schedule flow; needs the
            owner key and internet for pieces), then the switch: app stopped, encrypted pre-switch
            dump on the host, new version deployed, production checks against the counts taken
            with the app stopped. Needs --yes and the typed client id; only inside the client's
            quiet hours (alerts.quiet_hours, client time zone) unless --now. Any failure after the
            app was stopped rolls back on its own: the pre-switch dump replaces the database, the
            old version is deployed and checked, the owner gets a critical alert.
--resume    continues an interrupted upgrade that had not reached the switch
--rollback  puts the client back on the version before its last upgrade (interrupted, or
            finished less than 7 days ago): data since the switch is lost; needs --yes + typed id
--unlock    gives up an interrupted upgrade that had not reached the switch (releases its lock)
State of every run: opskit/clients/<id>/upgrades/<time>/state.json. Checklist:
docs/runbooks/upgrade-checklist.md
USAGE
}

cmd_main() {
  local id="" to="" mode=""
  # shellcheck disable=SC2034 # UPGRADE_YES / UPGRADE_NOW are read by upgrade_switch.sh
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) upgrade_usage; return 0 ;;
      --to) to="${2:-}"; shift 2 || { upgrade_usage >&2; return 1; } ;;
      --yes) UPGRADE_YES=true; shift ;;
      --now) UPGRADE_NOW=true; shift ;;
      --plan|--resume|--rollback|--unlock)
        [ -z "$mode" ] || { upgrade_usage >&2; return 1; }
        mode="${1#--}"
        shift
        ;;
      -*) upgrade_usage >&2; return 1 ;;
      *) if [ -z "$id" ]; then id="$1"; else upgrade_usage >&2; return 1; fi; shift ;;
    esac
  done
  local needs_to=0
  case "$mode" in ""|plan) needs_to=1 ;; esac
  if [ -z "$id" ] || { [ "$needs_to" = 1 ] && [ -z "$to" ]; } || { [ "$needs_to" = 0 ] && [ -n "$to" ]; }; then
    upgrade_usage >&2
    return 1
  fi
  require_client "$id" || return 1
  case "$mode" in
    plan) upgrade_plan "$id" "$to" ;;
    resume) upgrade_resume "$id" ;;
    unlock) upgrade_unlock "$id" ;;
    rollback) upgrade_rollback_manual "$id" ;;
    *) upgrade_start "$id" "$to" ;;
  esac
}
