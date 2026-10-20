#!/usr/bin/env bash
# Destructive-action guard: requires --yes AND the client id typed on stdin.

# confirm_destructive <client_id> <yes_flag:true|false> <action description>
confirm_destructive() {
  local client_id="$1" yes_flag="$2" action="$3" typed=""
  if [ "$yes_flag" != "true" ]; then
    log_fail "${action} is destructive: re-run with --yes"
    return 1
  fi
  printf 'Type the client id (%s) to confirm: %s\n> ' "$client_id" "$action" >&2
  if ! IFS= read -r typed; then
    log_fail "no confirmation received; nothing was changed"
    return 1
  fi
  if [ "$typed" != "$client_id" ]; then
    log_fail "typed id does not match ${client_id}; nothing was changed"
    return 1
  fi
  log_ok "confirmed: ${action}"
}
