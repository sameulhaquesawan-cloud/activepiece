#!/usr/bin/env bash
# summary: restore a backup into a fresh stack (or over the client with --overwrite --yes)

for lib in validate schema registry render secrets stack ssh host deploy confirm verify restore; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

restore_usage() {
  cat <<'USAGE'
Usage: opskit restore <client id> [--from <backup name>|latest] [--target <new id>] [--domain <domain>]
                      [--overwrite --yes]

--target <new id>  restore into a NEW client stack on the same host (default: <id>-restore);
                   needs --domain unless the host uses internal TLS (practice: <new id>.localhost)
--target <id>      restore over the client itself: always needs --overwrite --yes
                   plus the client id typed to confirm (all current data is replaced)
Needs the owner's age private key: $OPSKIT_OWNER_AGE_KEY or ~/.config/opskit/owner.key
USAGE
}

cmd_main() {
  local source="${1:-}" from="latest" target="" domain="" overwrite="false" yes="false"
  case "$source" in
    -h|--help) restore_usage; return 0 ;;
    ""|-*) restore_usage >&2; return 1 ;;
  esac
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --from) from="${2:-}"; shift 2 ;;
      --target) target="${2:-}"; shift 2 ;;
      --domain) domain="${2:-}"; shift 2 ;;
      --overwrite) overwrite="true"; shift ;;
      --yes) yes="true"; shift ;;
      *) restore_usage >&2; return 1 ;;
    esac
  done
  restore_client "$source" "$from" "${target:-${source}-restore}" "$domain" "$overwrite" "$yes"
}
