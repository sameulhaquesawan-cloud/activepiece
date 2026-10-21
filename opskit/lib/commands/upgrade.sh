#!/usr/bin/env bash
# summary: upgrade a client to a newer Activepieces release (plan, pre-pull, lock; staging, switch and rollback follow)

for lib in validate schema registry ssh host stack deploy verify restore roundtrip e2e practice smoke smoke_flows upgrade upgrade_run upgrade_stage; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

upgrade_usage() {
  cat <<'USAGE'
Usage: opskit upgrade <client id> --to <x.y.z> [--plan]
       opskit upgrade <client id> --resume | --rollback | --unlock

--plan      read-only: checks the target release exists and is newer, lists the breaking changes
            Activepieces documents between the two versions, the database changes (when both
            images are on this machine) and the gates: a backup younger than 26 h with its
            off-server copy, a passed restore test from the last 35 days, free disk and memory on
            the host, free disk here, no other upgrade running. Exit 1 when a gate fails.
(no option) runs the upgrade: gates, lock, waits for a running backup, pulls the image here and on
            the host (same digest), stages it (fresh backup restored into a temporary stack on
            this machine on the new version, checks incl. a webhook and a schedule flow; needs the
            owner key and internet for pieces), then switch → checks (automatic rollback).
            Switch and rollback are being built (Phase 6, tasks 6.6–6.7).
--resume    continues an interrupted upgrade that had not reached the switch
--rollback  puts an interrupted upgrade back on the previous version (task 6.7)
--unlock    gives up an interrupted upgrade that had not reached the switch (releases its lock)
State of every run: opskit/clients/<id>/upgrades/<time>/state.json. Checklist:
docs/runbooks/upgrade-checklist.md
USAGE
}

cmd_main() {
  local id="" to="" mode=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) upgrade_usage; return 0 ;;
      --to) to="${2:-}"; shift 2 || { upgrade_usage >&2; return 1; } ;;
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
    rollback) die "rollback is not available yet (Phase 6, task 6.7)" ;;
    *) upgrade_start "$id" "$to" ;;
  esac
}
