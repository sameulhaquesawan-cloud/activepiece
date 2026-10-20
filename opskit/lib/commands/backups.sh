#!/usr/bin/env bash
# summary: list a client's backups on the host and off-server

# shellcheck source=../validate.sh
source "${OPSKIT_ROOT}/lib/validate.sh"
# shellcheck source=../schema.sh
source "${OPSKIT_ROOT}/lib/schema.sh"
# shellcheck source=../registry.sh
source "${OPSKIT_ROOT}/lib/registry.sh"
# shellcheck source=../ssh.sh
source "${OPSKIT_ROOT}/lib/ssh.sh"
# shellcheck source=../host.sh
source "${OPSKIT_ROOT}/lib/host.sh"

cmd_main() {
  case "${1:-}" in
    -h|--help|"")
      printf 'Usage: opskit backups <client id>\n\nLists backups (newest last): name, database size, off-server status.\n'
      [ -n "${1:-}" ] && return 0
      return 1
      ;;
  esac
  local id="$1" host root remote
  require_client "$id" || return 1
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  root="$(host_root "$host")"
  log_info "On host ${host} (${root}/backups/${id}):"
  # shellcheck disable=SC2016
  host_run "$host" sh -c 'for d in "$1"/*/; do [ -f "${d}status.json" ] && cat "${d}status.json" && echo; done; true' _ "${root}/backups/${id}" \
    | jq -r 'select(.backup) | "  \(.backup)  db \(.db_bytes) bytes  off-server: \(.remote // "?")"'
  remote="$(yaml_get "$(client_file "$id")" .backup.remote)"
  if [ -n "$remote" ]; then
    log_info "Off-server (${remote}/${id}):"
    # shellcheck disable=SC2016
    host_run "$host" sh -c 'if [ -f "$1" ]; then rclone --config "$1" lsf --dirs-only "$2"; else rclone lsf --dirs-only "$2"; fi' _ \
      "${root}/agent/rclone.conf" "${remote%/}/${id}/" | sed 's#/$##; s#^#  #'
  else
    log_warn "no off-server remote configured (client.yaml backup.remote)"
  fi
}
