#!/usr/bin/env bash
# summary: our own copies of the pieces (integrations) stacks use: list, add, check, install into a stack

for lib in validate schema registry stack host flows flows_import pieces; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

pieces_usage() {
  cat <<'USAGE'
Usage: opskit pieces list
       opskit pieces add <@scope/piece-name> <x.y.z>
       opskit pieces check
       opskit pieces install <client id> [--email <admin email>] [--url <https://…>]
       opskit pieces install --url <builder address> [--email <admin email>]

Client stacks run with a frozen piece catalog (AP_PIECES_SYNC_MODE=NONE): they only have the pieces
we install from opskit/pieces, so nothing Activepieces publishes, removes or switches off changes them.

list      the pieces in the pack (opskit/pieces/pack.yaml) with their versions.
add       download one exact version from npm once (sha512 checked against npm, refused if it
          has npm dependencies), store it in opskit/pieces/files and record its sha256. Commit both.
check     every file is present and unchanged, and every template pin is in the pack.
install   sign in as the platform admin (password asked, never stored) and install every pack piece
          the stack does not have yet. `opskit flows import` also installs what a template needs.
USAGE
}

pieces_list() {
  local name version count=0
  while IFS=$'\t' read -r name version _; do
    [ -n "$name" ] || continue
    printf '%-45s %s\n' "$name" "$version"
    count=$((count + 1))
  done < <(pieces_entries)
  log_info "${count} pieces in $(pieces_pack_file)"
}

pieces_install() {
  local id="" email="" url="" name version installed=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --email) email="${2:-}"; shift 2 ;;
      --url) url="${2:-}"; shift 2 ;;
      -*) pieces_usage >&2; return 1 ;;
      *) [ -z "$id" ] || { pieces_usage >&2; return 1; }; id="$1"; shift ;;
    esac
  done
  [ -n "$id" ] || [ -n "$url" ] || { pieces_usage >&2; return 1; }
  pieces_check || return 1
  [ -z "$id" ] || require_client "$id" || return 1
  flows_target "$id" "$url" || return 1
  FLOWS_TMP="$(mktemp -d)"
  chmod 700 "$FLOWS_TMP"
  trap 'rm -rf "${FLOWS_TMP:-}"' EXIT
  if [ -z "$email" ]; then
    IFS= read -r -p "Admin email for ${FLOWS_BASE_URL}: " email || true
  fi
  [ -n "$email" ] || { log_fail "no admin email given (--email)"; return 1; }
  flows_sign_in "$email" || return 1
  while IFS=$'\t' read -r name version _; do
    [ -n "$name" ] || continue
    if flows_piece_known "$name" "$version"; then
      continue
    fi
    flows_install_archive "$name" "$version" "$(pieces_file "$name" "$version")" || return 1
    installed=$((installed + 1))
  done < <(pieces_entries)
  log_ok "pieces on ${FLOWS_BASE_URL}: ${installed} installed, the rest were already there"
}

cmd_main() {
  case "${1:-}" in
    -h|--help) pieces_usage; return 0 ;;
    list) pieces_list ;;
    add) [ "$#" -eq 3 ] || { pieces_usage >&2; return 1; }; pieces_add "$2" "$3" ;;
    check) pieces_check ;;
    install) shift; pieces_install "$@" ;;
    *) pieces_usage >&2; return 1 ;;
  esac
}
