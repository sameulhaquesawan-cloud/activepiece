#!/usr/bin/env bash
# Throwaway practice hosts on this machine (local transport, Caddy internal TLS on free ports),
# used by selftest and restore-test. Only ever removes what it created.

port_free() {
  ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

free_port_pair() {
  local http
  for http in $(seq 18080 10 18980); do
    if port_free "$http" && port_free "$((http + 363))"; then
      printf '%s %s' "$http" "$((http + 363))"
      return 0
    fi
  done
  return 1
}

# practice_host_write <registry> <host id> <opskit root> <edge container>: prints the https port
practice_host_write() {
  local registry="$1" host="$2" root="$3" edge="$4" shim="false" ports http_port https_port
  [ -e /proc/net/if_inet6 ] || shim="true"
  ports="$(free_port_pair)" || { log_fail "no free port pair in 18080-18980"; return 1; }
  http_port="${OPSKIT_PRACTICE_HTTP_PORT:-${ports% *}}"
  https_port="${OPSKIT_PRACTICE_HTTPS_PORT:-${ports#* }}"
  mkdir -p "${registry}/hosts"
  cat > "${registry}/hosts/${host}.yaml" <<YAML
host_id: ${host}
ip: 127.0.0.1
ssh_user: ops
mode: dedicated
cpus: 2
ram_gb: 4
transport: local
opskit_root: ${root}
edge:
  http_port: ${http_port}
  https_port: ${https_port}
  tls: internal
  container: ${edge}
practice_quirks:
  ipv4_listen_shim: ${shim}
YAML
  printf '%s' "$https_port"
}

# practice_teardown <opskit root> <edge container> <client id>...
practice_teardown() {
  local root="$1" edge="$2" id
  shift 2
  for id in "$@"; do
    [ -f "${root}/clients/${id}/compose.yml" ] || continue
    docker compose -p "$id" --project-directory "${root}/clients/${id}" \
      -f "${root}/clients/${id}/compose.yml" down -v --remove-orphans >/dev/null 2>&1 || true
  done
  [ -z "$edge" ] || docker rm -f "$edge" >/dev/null 2>&1 || true
}

practice_remove_tree() {
  local dir="$1" caddy
  for caddy in "${dir}"/*/caddy "${dir}/caddy"; do
    [ -d "$caddy" ] || continue
    docker run --rm -v "${caddy}:/caddy" --entrypoint sh caddy:2.10.0 \
      -c 'rm -rf /caddy/data /caddy/config' >/dev/null 2>&1 || true
  done
  rm -rf "$dir" 2>/dev/null || log_warn "could not fully remove ${dir}"
}
