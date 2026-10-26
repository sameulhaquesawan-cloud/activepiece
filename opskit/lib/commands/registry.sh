#!/usr/bin/env bash
# summary: back up / restore your own registry (clients, hosts, owner settings) encrypted to your age key

for lib in validate schema registry confirm render secrets stack ssh host deploy restore registry_backup; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

registry_usage() {
  cat <<'USAGE'
Usage: opskit registry backup [--to <remote:path>]
       opskit registry restore <latest|archive file|remote:path/archive> [--overwrite --yes]

Your clients/, hosts/ and owner/ folders are git-ignored (they hold secrets) and live only on this
machine. backup packs them into one archive encrypted to your owner age public key, keeps the last 10
in ~/opskit-registry-backups (OPSKIT_REGISTRY_BACKUPS), and with --to also copies it to an rclone
remote from opskit/owner/rclone.conf (e.g. b2:your-bucket/registry; the last 30 are kept there).
restore needs your owner private key. It never overwrites: with folders already present it stops,
unless --overwrite --yes (type "registry" to confirm), and then moves the current ones aside to
.registry-before-<time>/ instead of deleting them.
USAGE
}

cmd_main() {
  local sub="${1:-}" to="" source="" overwrite="false" yes="false"
  shift || true
  case "$sub" in
    backup)
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --to) [ -n "${2:-}" ] || { registry_usage >&2; return 1; }; to="$2"; shift 2 ;;
          *) registry_usage >&2; return 1 ;;
        esac
      done
      registry_backup "$to"
      ;;
    restore)
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --overwrite) overwrite="true"; shift ;;
          --yes) yes="true"; shift ;;
          -*) registry_usage >&2; return 1 ;;
          *) [ -z "$source" ] || { registry_usage >&2; return 1; }; source="$1"; shift ;;
        esac
      done
      [ -n "$source" ] || { registry_usage >&2; return 1; }
      registry_restore "$source" "$overwrite" "$yes"
      ;;
    -h|--help|"") registry_usage ;;
    *) registry_usage >&2; return 1 ;;
  esac
}
