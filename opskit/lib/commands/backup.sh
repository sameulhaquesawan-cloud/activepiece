#!/usr/bin/env bash
# summary: run a client's backup now on its host (same agent as the nightly cron)

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
      printf 'Usage: opskit backup <client id>\n\nRuns <root>/agent/backup.sh on the client'"'"'s host and reports the result:\n0 complete (local + off-server + heartbeat), 2 local only, 1 failed (an alert was sent).\n'
      [ -n "${1:-}" ] && return 0
      return 1
      ;;
  esac
  local id="$1" host root rc=0
  require_client "$id" || return 1
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  root="$(host_root "$host")"
  host_run "$host" test -x "${root}/agent/backup.sh" \
    || die "backup agent not installed on ${host}: run opskit deploy ${id} (needs opskit/keys/owner.age.pub)"
  host_run "$host" "${root}/agent/backup.sh" "$id" --root "$root" || rc=$?
  case "$rc" in
    0) log_ok "backup of ${id} complete" ;;
    2) log_warn "backup of ${id} is local only (set backup.remote in client.yaml, then opskit deploy ${id})" ;;
    *) log_fail "backup of ${id} failed (exit ${rc})" ;;
  esac
  return "$rc"
}
