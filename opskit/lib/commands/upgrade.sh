#!/usr/bin/env bash
# summary: upgrade a client to a newer Activepieces release (plan; staging, switch and rollback follow)

for lib in validate schema registry ssh host upgrade; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

upgrade_usage() {
  cat <<'USAGE'
Usage: opskit upgrade <client id> --to <x.y.z> --plan

--plan   read-only: checks the target release exists and is newer, lists the breaking changes
         Activepieces documents between the two versions, counts database changes (when both
         images are on this machine) and checks the gates: a backup younger than 26 h with its
         off-server copy, a passed restore test from the last 35 days, free disk on the host and
         here. Exit 1 when a gate fails. Nothing is changed.
Without --plan the upgrade itself runs (staging copy → switch → automatic rollback); being built
in Phase 6, tasks 6.3–6.7. Checklist: docs/runbooks/upgrade-checklist.md
USAGE
}

cmd_main() {
  local id="" to="" plan=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) upgrade_usage; return 0 ;;
      --to) to="${2:-}"; shift 2 || { upgrade_usage >&2; return 1; } ;;
      --plan) plan=1; shift ;;
      -*) upgrade_usage >&2; return 1 ;;
      *) if [ -z "$id" ]; then id="$1"; else upgrade_usage >&2; return 1; fi; shift ;;
    esac
  done
  if [ -z "$id" ] || [ -z "$to" ]; then
    upgrade_usage >&2
    return 1
  fi
  require_client "$id" || return 1
  if [ "$plan" != "1" ]; then
    die "the upgrade itself is not available yet (Phase 6, tasks 6.3–6.7); use --plan"
  fi
  upgrade_plan "$id" "$to"
}
