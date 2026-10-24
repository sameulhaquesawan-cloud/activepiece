#!/usr/bin/env bash
# Deploy a rendered client stack to its host and verify it end to end.

DEPLOY_HEALTH_TIMEOUT="${OPSKIT_HEALTH_TIMEOUT:-420}"
DEPLOY_WORKER_TIMEOUT="${OPSKIT_WORKER_TIMEOUT:-180}"
DEPLOY_HTTPS_TIMEOUT="${OPSKIT_HTTPS_TIMEOUT:-180}"

stack_remote_dir() {
  printf '%s/clients/%s' "$(host_root "$1")" "$2"
}

# stack_compose <host> <id> <compose args...>
stack_compose() {
  local host="$1" id="$2" dir files=()
  shift 2
  dir="$(stack_remote_dir "$host" "$id")"
  files=(-f "${dir}/compose.yml")
  if host_run "$host" test -f "${dir}/compose.practice.yml"; then
    files+=(-f "${dir}/compose.practice.yml")
  fi
  host_run "$host" docker compose -p "$id" --project-directory "$dir" "${files[@]}" "$@"
}

deploy_push_files() {
  local host="$1" id="$2" out dir
  out="$(rendered_dir "$id")"
  dir="$(stack_remote_dir "$host" "$id")"
  host_put "$host" "${out}/compose.yml" "${dir}/compose.yml" 600 || return 1
  host_put "$host" "${out}/.env" "${dir}/.env" 600 || return 1
  if [ -f "${out}/compose.practice.yml" ]; then
    host_put "$host" "${out}/compose.practice.yml" "${dir}/compose.practice.yml" 600 || return 1
    host_put "$host" "${out}/ipv4-shim.js" "${dir}/ipv4-shim.js" 644 || return 1
  else
    host_run "$host" rm -f "${dir}/compose.practice.yml" "${dir}/ipv4-shim.js"
  fi
  log_ok "files copied to ${host}:${dir}"
}

deploy_wait_healthy() {
  local host="$1" id="$2" container state="" waited=0
  container="$(stack_compose "$host" "$id" ps -q app | head -n 1)"
  [ -n "$container" ] || { log_fail "app container not found"; return 1; }
  while [ "$waited" -lt "$DEPLOY_HEALTH_TIMEOUT" ]; do
    state="$(host_run "$host" docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || true)"
    [ "$state" = "healthy" ] && { log_ok "app healthy (${waited}s)"; return 0; }
    sleep 5
    waited=$((waited + 5))
  done
  log_fail "app not healthy after ${DEPLOY_HEALTH_TIMEOUT}s (state: ${state:-unknown}); see: docker compose -p ${id} logs app"
  return 1
}

deploy_wait_worker() {
  local host="$1" id="$2" since="$3" waited=0
  while [ "$waited" -lt "$DEPLOY_WORKER_TIMEOUT" ]; do
    if stack_compose "$host" "$id" logs --no-color --since "$since" app 2>/dev/null | grep -q 'Poll request received'; then
      log_ok "worker registered (polling the app)"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  log_fail "no worker poll seen after ${DEPLOY_WORKER_TIMEOUT}s; see: docker compose -p ${id} logs worker"
  return 1
}

# deploy_export_local_ca <host>: internal-TLS (practice) hosts keep a readable copy of Caddy's public
# local root certificate at <root>/caddy/local-root.crt for heartbeats (the original is root-only)
deploy_export_local_ca() {
  local host="$1" edge
  [ "$(yaml_get "$(host_file "$host")" .edge.tls acme)" = "internal" ] || return 0
  edge="$(yaml_get "$(host_file "$host")" .edge.container opskit-caddy)"
  # shellcheck disable=SC2016
  host_run "$host" sh -c 'docker exec "$1" cat /data/caddy/pki/authorities/local/root.crt > "$2.tmp" && mv "$2.tmp" "$2" && chmod 644 "$2"' \
    _ "$edge" "$(host_root "$host")/caddy/local-root.crt" \
    || log_warn "could not export Caddy's local root certificate on ${host} (practice heartbeats will fail TLS)"
}

deploy_publish_site() {
  local host="$1" id="$2" edge root
  edge="$(yaml_get "$(host_file "$host")" .edge.container opskit-caddy)"
  root="$(host_root "$host")"
  host_run "$host" docker inspect "$edge" >/dev/null 2>&1 \
    || { log_fail "edge ${edge} not running on ${host}: run opskit host bootstrap ${host}"; return 1; }
  host_put "$host" "$(rendered_dir "$id")/${id}.caddy" "${root}/caddy/etc/sites/${id}.caddy" 644 || return 1
  host_run "$host" docker exec "$edge" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 \
    || { log_fail "caddy reload failed on ${host}"; return 1; }
  deploy_export_local_ca "$host"
  log_ok "HTTPS site published via ${edge}"
}

deploy_check_https() {
  local host="$1" id="$2" domain port tls url body waited=0
  domain="$(yaml_get "$(client_file "$id")" .domain)"
  port="$(yaml_get "$(host_file "$host")" .edge.https_port 443)"
  tls="$(yaml_get "$(host_file "$host")" .edge.tls acme)"
  url="https://${domain}:${port}/api/v1/health"
  while [ "$waited" -lt "$DEPLOY_HTTPS_TIMEOUT" ]; do
    if [ "$tls" = "internal" ]; then
      body="$(host_run "$host" curl -sk -m 10 --noproxy '*' --resolve "${domain}:${port}:127.0.0.1" "$url" 2>/dev/null || true)"
    else
      body="$(curl -s -m 10 "$url" 2>/dev/null || true)"
    fi
    if [[ "$body" == *Healthy* ]]; then
      log_ok "HTTPS health OK: https://${domain}$([ "$port" = 443 ] || printf ':%s' "$port")"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  log_fail "HTTPS health check failed for ${url} (DNS pointing at the host? certificate issued?)"
  return 1
}

owner_age_pubkey() {
  printf '%s' "${OPSKIT_OWNER_AGE_PUB:-${OPSKIT_ROOT}/keys/owner.age.pub}"
}

host_installs_cron() {
  local default="true"
  [ "$(host_transport "$1")" = "local" ] && default="false"
  yaml_get "$(host_file "$1")" .install_cron "$default"
}

# deploy_check_scheduler <host>: hosts that get cron schedules need crontab (Ubuntu Minimal ships without it)
deploy_check_scheduler() {
  local host="$1"
  [ "$(host_installs_cron "$host")" = "true" ] || return 0
  if ! host_run "$host" sh -c 'command -v crontab' >/dev/null 2>&1; then
    log_fail "crontab not found on ${host} (Ubuntu Minimal has no cron): run opskit host bootstrap ${host}"
    return 1
  fi
  log_ok "cron available on ${host}"
}

# deploy_install_agents <host> <id>: monitoring always; backups only when the owner age key exists
deploy_install_agents() {
  local host="$1" id="$2" root out owner script template backups="true" cron
  root="$(host_root "$host")"
  out="$(rendered_dir "$id")"
  owner="$(registry_root)/owner"
  if [ ! -s "$(owner_age_pubkey)" ]; then
    backups="false"
    log_warn "backups NOT installed for ${id}: no owner age public key ($(owner_age_pubkey)); see docs/runbooks/backup-restore.md"
  fi
  for script in alert.sh cron-sync.sh detect-failed-runs.sh health.sh digest.sh; do
    host_put "$host" "${OPSKIT_ROOT}/agent/${script}" "${root}/agent/${script}" 755 || return 1
  done
  for template in "${OPSKIT_ROOT}"/templates/alerts/*.jq; do
    host_put "$host" "$template" "${root}/agent/alerts/$(basename "$template")" 644 || return 1
  done
  if [ -f "${owner}/alerts.conf" ]; then
    host_put "$host" "${owner}/alerts.conf" "${root}/agent/alerts.conf" 600 || return 1
  else
    log_warn "no owner alert channels (${owner}/alerts.conf): alerts are only logged on the host"
  fi
  host_put "$host" "${out}/alerts.conf" "${root}/clients/${id}/alerts.conf" 600 || return 1
  cron="${out}/cron"
  if [ "$backups" = "true" ]; then
    host_put "$host" "${OPSKIT_ROOT}/agent/backup.sh" "${root}/agent/backup.sh" 755 || return 1
    host_put "$host" "$(owner_age_pubkey)" "${root}/agent/owner.age.pub" 644 || return 1
    if [ -f "${owner}/rclone.conf" ]; then
      host_put "$host" "${owner}/rclone.conf" "${root}/agent/rclone.conf" 600 || return 1
    fi
    host_put "$host" "${out}/backup.conf" "${root}/clients/${id}/backup.conf" 600 || return 1
  else
    cron="${out}/cron.monitoring"
    grep -v '/agent/backup.sh ' "${out}/cron" > "$cron" || true
  fi
  host_put "$host" "$cron" "${root}/clients/${id}/cron" 644 || return 1
  host_run "$host" mkdir -p "${root}/logs" || return 1
  if [ "$(host_installs_cron "$host")" = "true" ]; then
    host_run "$host" "${root}/agent/cron-sync.sh" --root "$root" >/dev/null || { log_fail "cron sync failed on ${host}"; return 1; }
    if [ "$backups" = "true" ]; then
      log_ok "monitoring + backup agents installed; nightly backup ($(yaml_get "$(client_file "$id")" .backup.schedule "30 2 * * *"))"
    else
      log_ok "monitoring agents installed (failed runs every 5 min, health hourly, daily digest)"
    fi
  else
    log_ok "agents installed (no cron on practice host ${host}: run opskit backup ${id}; monitoring scripts by hand)"
  fi
}

deploy_record() {
  local id="$1" file tag last_tag status
  file="$(client_file "$id")"
  tag="$(yaml_get "$file" .image.tag)"
  status="$(yaml_get "$file" .status)"
  last_tag="$(yq -r '.history[] | select(.event == "deployed") | .tag' "$file" | tail -n 1)"
  if [ "$status" != "deployed" ] || [ "$last_tag" != "$tag" ]; then
    yaml_set "$file" '.status = "deployed"'
    client_history_add "$id" deployed "$tag"
  fi
}

# deploy_client <id>
# deploy_readonly_role <host> <id>: passwordless opskit_ro for detectors; local socket only (ASSUMPTIONS #13)
deploy_readonly_role() {
  local host="$1" id="$2" container
  container="$(stack_compose "$host" "$id" ps -q postgres | head -n 1)"
  [ -n "$container" ] || { log_fail "postgres of ${id} is not running"; return 1; }
  # shellcheck disable=SC2016
  host_run "$host" docker exec -i "$container" sh -c 'psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -v db="$POSTGRES_DB"' \
    < "${OPSKIT_ROOT}/templates/readonly-role.sql" >/dev/null \
    || { log_fail "could not set up the read-only database role for ${id}"; return 1; }
  log_ok "read-only database role opskit_ro ready"
}

deploy_client() {
  local id="$1" host status since
  require_client "$id" || return 1
  status="$(yaml_get "$(client_file "$id")" .status)"
  [ "$status" != "offboarded" ] || { log_fail "client ${id} is offboarded; refusing to deploy"; return 1; }
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  deploy_check_scheduler "$host" || return 1
  stack_render "$id" || return 1
  deploy_push_files "$host" "$id" || return 1
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local up_output
  if ! up_output="$(stack_compose "$host" "$id" up -d --remove-orphans 2>&1)"; then
    printf '%s\n' "$up_output" | tail -n 5
    log_fail "docker compose up failed for ${id}"
    return 1
  fi
  log_ok "stack ${id} up on ${host}"
  deploy_wait_healthy "$host" "$id" || return 1
  deploy_wait_worker "$host" "$id" "$since" || return 1
  deploy_readonly_role "$host" "$id" || return 1
  deploy_publish_site "$host" "$id" || return 1
  deploy_check_https "$host" "$id" || return 1
  if [ "${DEPLOY_SKIP_BACKUP:-false}" = "true" ]; then
    log_warn "backup and monitoring schedule not installed for ${id} (restore copy)"
  else
    deploy_install_agents "$host" "$id" || return 1
  fi
  deploy_record "$id"
  log_ok "deployed ${id}"
}
