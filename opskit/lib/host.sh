#!/usr/bin/env bash
# Host transport: run commands / copy files on a host, either over SSH (lib/ssh.sh) or locally
# (practice hosts). Callers never branch on the transport themselves.

host_transport() {
  yaml_get "$(host_file "$1")" .transport ssh
}

host_root() {
  yaml_get "$(host_file "$1")" .opskit_root /opt/opskit
}

host_ssh_target() {
  local file
  file="$(host_file "$1")"
  printf '%s\n%s\n%s\n' "$(yaml_get "$file" .ssh_user)" "$(yaml_get "$file" .ip)" "$(yaml_get "$file" .ssh_port 22)"
}

# host_run <host> <command> [args...]
host_run() {
  local host="$1"
  shift
  if [ "$(host_transport "$host")" = "local" ]; then
    "$@"
    return
  fi
  local target
  mapfile -t target < <(host_ssh_target "$host")
  ssh_run "${target[0]}" "${target[1]}" "${target[2]}" "$@"
}

# host_put <host> <local file> <remote path> [mode]
host_put() {
  local host="$1" src="$2" dest="$3" mode="${4:-600}"
  [ -f "$src" ] || { log_fail "host_put: source not found: ${src}"; return 1; }
  if [ "$(host_transport "$host")" = "local" ]; then
    install -D -m "$mode" "$src" "$dest"
    return
  fi
  local target
  mapfile -t target < <(host_ssh_target "$host")
  ssh_run "${target[0]}" "${target[1]}" "${target[2]}" mkdir -p "$(dirname "$dest")" || return 1
  scp_put "${target[0]}" "${target[1]}" "${target[2]}" "$src" "$dest" || return 1
  ssh_run "${target[0]}" "${target[1]}" "${target[2]}" chmod "$mode" "$dest"
}

# host_get <host> <remote file> <local file>
host_get() {
  local host="$1" src="$2" dest="$3"
  if [ "$(host_transport "$host")" = "local" ]; then
    cp "$src" "$dest"
    return
  fi
  local target
  mapfile -t target < <(host_ssh_target "$host")
  scp_get "${target[0]}" "${target[1]}" "${target[2]}" "$src" "$dest"
}
