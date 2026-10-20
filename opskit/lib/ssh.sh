#!/usr/bin/env bash
# SSH/SCP wrappers: key-only, non-interactive, accept-new host keys, bounded timeouts.
# All remote actions go through these helpers.

ssh_common_opts() {
  local opts=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o PasswordAuthentication=no
    -o KbdInteractiveAuthentication=no
    -o ConnectTimeout="${OPSKIT_SSH_CONNECT_TIMEOUT:-10}"
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=3
  )
  if [ -n "${OPSKIT_KNOWN_HOSTS:-}" ]; then
    opts+=(-o UserKnownHostsFile="${OPSKIT_KNOWN_HOSTS}")
  fi
  printf '%s\n' "${opts[@]}"
}

ssh_target_ok() {
  local user="$1" host="$2" port="$3"
  [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { log_fail "invalid ssh user: ${user}"; return 1; }
  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || { log_fail "invalid ssh host: ${host}"; return 1; }
  is_port "$port" || { log_fail "invalid ssh port: ${port}"; return 1; }
}

# ssh_run <user> <host> <port> <command> [args...]  (args are shell-quoted for the remote side)
ssh_run() {
  local user="$1" host="$2" port="$3"
  shift 3
  ssh_target_ok "$user" "$host" "$port" || return 1
  local opts remote_command
  mapfile -t opts < <(ssh_common_opts)
  remote_command="$(printf '%q ' "$@")"
  ssh "${opts[@]}" -p "$port" "${user}@${host}" -- "${remote_command% }"
}

# scp_get <user> <host> <port> <remote path> <local path>
scp_get() {
  local user="$1" host="$2" port="$3" remote_path="$4" local_path="$5"
  ssh_target_ok "$user" "$host" "$port" || return 1
  local opts
  mapfile -t opts < <(ssh_common_opts)
  scp -q "${opts[@]}" -P "$port" -- "${user}@${host}:${remote_path}" "$local_path"
}

# scp_put <user> <host> <port> <local path> <remote path>
scp_put() {
  local user="$1" host="$2" port="$3" local_path="$4" remote_path="$5"
  ssh_target_ok "$user" "$host" "$port" || return 1
  [ -e "$local_path" ] || { log_fail "scp source not found: ${local_path}"; return 1; }
  local opts
  mapfile -t opts < <(ssh_common_opts)
  scp -q "${opts[@]}" -P "$port" -- "$local_path" "${user}@${host}:${remote_path}"
}
