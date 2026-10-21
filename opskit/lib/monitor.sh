#!/usr/bin/env bash
# Uptime Kuma (the owner's monitoring) on a host: render, run behind the host's Caddy edge, admin
# account. Talks to Uptime Kuma only through its own socket API from inside its container
# (ASSUMPTIONS #11), so no extra tool is needed anywhere.

MONITOR_PROJECT="opskit-monitor"

# local folder in the registry (git-ignored): rendered files + admin.env (600)
monitor_dir() {
  printf '%s/hosts/%s.monitor' "$(registry_root)" "$1"
}

monitor_remote_dir() {
  printf '%s/monitor' "$(host_root "$1")"
}

monitor_require() {
  local host="$1"
  require_host "$host" || return 1
  [ -n "$(yaml_get "$(host_file "$host")" .monitor.domain)" ] \
    || { log_fail "host ${host} has no monitor section (add monitor: {domain: status.example.com} to its yaml)"; return 1; }
}

monitor_admin_secrets() {
  local file
  file="$(monitor_dir "$1")/admin.env"
  if [ ! -s "$file" ]; then
    local password
    password="Uk-$(openssl rand -hex 16 2>/dev/null || true)"
    [ "${#password}" -eq 35 ] || { log_fail "could not generate the Uptime Kuma admin password"; return 1; }
    (umask 077 && printf 'UK_ADMIN_USER=opskit\nUK_ADMIN_PASSWORD=%s\n' "$password" > "$file")
  fi
  chmod 600 "$file"
}

monitor_admin_json() {
  local file
  file="$(monitor_dir "$1")/admin.env"
  jq -nc --arg u "$(sed -n 's/^UK_ADMIN_USER=//p' "$file")" --arg p "$(sed -n 's/^UK_ADMIN_PASSWORD=//p' "$file")" \
    '{username: $u, password: $p}'
}

monitor_render() {
  local host="$1" hfile dir
  monitor_require "$host" || return 1
  hfile="$(host_file "$host")"
  dir="$(monitor_dir "$host")"
  (umask 077 && mkdir -p "$dir")
  (
    set -e
    export MONITOR_IMAGE MONITOR_TAG MONITOR_MEMORY MONITOR_DOMAIN CADDY_TLS
    MONITOR_IMAGE="$(yaml_get "$hfile" .monitor.image louislam/uptime-kuma)"
    MONITOR_TAG="$(yaml_get "$hfile" .monitor.tag 2.5.5)"
    MONITOR_MEMORY="$(yaml_get "$hfile" .monitor.memory 512m)"
    MONITOR_DOMAIN="$(yaml_get "$hfile" .monitor.domain)"
    CADDY_TLS="# tls: automatic HTTPS (ACME)"
    [ "$(yaml_get "$hfile" .edge.tls acme)" != "internal" ] || CADDY_TLS="tls internal"
    render_template "${OPSKIT_ROOT}/templates/monitor/compose.yml.tmpl" "${dir}/compose.yml"
    render_template "${OPSKIT_ROOT}/templates/monitor/site.caddy.tmpl" "${dir}/${MONITOR_PROJECT}.caddy"
  ) || return 1
  monitor_admin_secrets "$host" || return 1
  log_ok "rendered monitor for ${host}: compose.yml, ${MONITOR_PROJECT}.caddy → ${dir}"
}

monitor_compose() {
  local host="$1" dir
  shift
  dir="$(monitor_remote_dir "$host")"
  host_run "$host" docker compose -p "$MONITOR_PROJECT" --project-directory "$dir" -f "${dir}/compose.yml" "$@"
}

monitor_container() {
  monitor_compose "$1" ps -q uptime-kuma | head -n 1
}

monitor_wait_healthy() {
  local host="$1" container state="" waited=0
  container="$(monitor_container "$host")"
  [ -n "$container" ] || { log_fail "Uptime Kuma container not found on ${host}"; return 1; }
  while [ "$waited" -lt 240 ]; do
    state="$(host_run "$host" docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || true)"
    [ "$state" = "healthy" ] && { log_ok "Uptime Kuma healthy (${waited}s)"; return 0; }
    sleep 3
    waited=$((waited + 3))
  done
  log_fail "Uptime Kuma not healthy after ${waited}s (${state:-unknown}): docker logs ${container}"
  return 1
}

# monitor_node <host> <script file> <json input>: run a socket-API script inside the container
monitor_node() {
  local host="$1" script="$2" input="$3" container
  container="$(monitor_container "$host")"
  [ -n "$container" ] || { log_fail "Uptime Kuma is not running on ${host}"; return 1; }
  # shellcheck disable=SC2016
  printf '%s' "$input" | host_run "$host" docker exec -i -w /app "$container" node -e "$(cat "$script")"
}

# monitor_node_retry: Uptime Kuma accepts socket calls ~15 s after it reports healthy; scripts exit 2 then
monitor_node_retry() {
  local host="$1" script="$2" input="$3" result rc attempt
  for attempt in $(seq 1 20); do
    rc=0
    result="$(monitor_node "$host" "$script" "$input" 2>&1)" || rc=$?
    [ "$rc" -eq 2 ] || [[ "$result" == *'"connect: '* ]] || break
    [ "$attempt" -lt 20 ] && sleep 3
  done
  printf '%s' "$result"
  return "$rc"
}

monitor_check_https() {
  local host="$1" hfile domain port code waited=0
  hfile="$(host_file "$host")"
  domain="$(yaml_get "$hfile" .monitor.domain)"
  port="$(yaml_get "$hfile" .edge.https_port 443)"
  while [ "$waited" -lt 60 ]; do
    code="$(curl -sk -o /dev/null -w '%{http_code}' -m 10 --resolve "${domain}:${port}:$(yaml_get "$hfile" .ip)" "https://${domain}:${port}/" || true)"
    case "$code" in
      200|302) log_ok "Uptime Kuma answers on https://${domain}$([ "$port" = 443 ] || printf ':%s' "$port")"; return 0 ;;
    esac
    sleep 3
    waited=$((waited + 3))
  done
  log_fail "https://${domain} does not answer (HTTP ${code:-none}); check DNS and the edge"
  return 1
}

monitor_deploy() {
  local host="$1" dir remote edge result
  monitor_render "$host" || return 1
  dir="$(monitor_dir "$host")"
  remote="$(monitor_remote_dir "$host")"
  edge="$(yaml_get "$(host_file "$host")" .edge.container opskit-caddy)"
  host_run "$host" docker inspect "$edge" >/dev/null 2>&1 \
    || { log_fail "edge ${edge} not running on ${host}: run opskit host bootstrap ${host}"; return 1; }
  host_put "$host" "${dir}/compose.yml" "${remote}/compose.yml" 600 || return 1
  monitor_compose "$host" up -d --remove-orphans >/dev/null 2>&1 || { log_fail "docker compose up failed for Uptime Kuma on ${host}"; return 1; }
  log_ok "Uptime Kuma up on ${host}"
  monitor_wait_healthy "$host" || return 1
  result="$(monitor_node_retry "$host" "${OPSKIT_ROOT}/templates/monitor/admin.js" "$(monitor_admin_json "$host")")" \
    || { log_fail "Uptime Kuma admin setup failed: ${result:0:200}"; return 1; }
  log_ok "Uptime Kuma admin account ready (login: ${dir}/admin.env)"
  host_put "$host" "${dir}/${MONITOR_PROJECT}.caddy" "$(host_root "$host")/caddy/etc/sites/${MONITOR_PROJECT}.caddy" 644 || return 1
  host_run "$host" docker exec "$edge" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 \
    || { log_fail "caddy reload failed on ${host}"; return 1; }
  deploy_export_local_ca "$host"
  monitor_check_https "$host"
}
