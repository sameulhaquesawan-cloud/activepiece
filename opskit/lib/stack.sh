#!/usr/bin/env bash
# Render a client's stack (compose, .env, Caddy site, cron) into clients/<id>/rendered/.

POSTGRES_IMAGE_PINNED="pgvector/pgvector:0.8.0-pg14"
REDIS_IMAGE_PINNED="redis:7.0.7"
POSTGRES_MEMORY_DEFAULT="1g"
REDIS_MEMORY_DEFAULT="256m"

rendered_dir() {
  printf '%s/rendered' "$(client_dir "$1")"
}

stack_frontend_url() {
  local domain="$1" https_port="$2"
  if [ "$https_port" = "443" ]; then
    printf 'https://%s' "$domain"
  else
    printf 'https://%s:%s' "$domain" "$https_port"
  fi
}

# stack_render <id>: requires a valid client + host; generates secrets on first use
stack_render() {
  local id="$1" cfile hfile host out tls
  require_client "$id" || return 1
  cfile="$(client_file "$id")"
  host="$(yaml_get "$cfile" .host.name)"
  require_host "$host" || return 1
  hfile="$(host_file "$host")"
  secrets_ensure "$id" >/dev/null || return 1
  out="$(rendered_dir "$id")"
  (umask 077 && mkdir -p "$out")
  tls="$(yaml_get "$hfile" .edge.tls acme)"
  (
    set -e
    secrets_export "$id"
    export CLIENT_ID="$id"
    CLIENT_DOMAIN="$(yaml_get "$cfile" .domain)"
    export CLIENT_DOMAIN
    CLIENT_TIMEZONE="$(yaml_get "$cfile" .timezone UTC)"
    export CLIENT_TIMEZONE
    AP_IMAGE="$(yaml_get "$cfile" .image.repo):$(yaml_get "$cfile" .image.tag)"
    export AP_IMAGE
    WORKER_REPLICAS="$(yaml_get "$cfile" .workers.replicas 1)"
    export WORKER_REPLICAS
    WORKER_MEMORY="$(yaml_get "$cfile" .workers.memory_limit 1g)"
    export WORKER_MEMORY
    APP_MEMORY="$(yaml_get "$cfile" .app.memory_limit 1g)"
    export APP_MEMORY
    export POSTGRES_IMAGE="$POSTGRES_IMAGE_PINNED" REDIS_IMAGE="$REDIS_IMAGE_PINNED"
    export POSTGRES_MEMORY="$POSTGRES_MEMORY_DEFAULT" REDIS_MEMORY="$REDIS_MEMORY_DEFAULT"
    AP_FRONTEND_URL="$(stack_frontend_url "$CLIENT_DOMAIN" "$(yaml_get "$hfile" .edge.https_port 443)")"
    export AP_FRONTEND_URL
    BACKUP_SCHEDULE="$(yaml_get "$cfile" .backup.schedule "30 2 * * *")"
    export BACKUP_SCHEDULE
    HOST_OPSKIT_ROOT="$(yaml_get "$hfile" .opskit_root /opt/opskit)"
    export HOST_OPSKIT_ROOT
    if [ "$tls" = "internal" ]; then
      export CADDY_TLS="tls internal"
    else
      export CADDY_TLS="# tls: automatic HTTPS (ACME)"
    fi
    umask 077
    render_template "${OPSKIT_ROOT}/templates/compose.yml.tmpl" "${out}/compose.yml" >/dev/null
    render_template "${OPSKIT_ROOT}/templates/env.tmpl" "${out}/.env" >/dev/null
    render_template "${OPSKIT_ROOT}/templates/caddy-site.tmpl" "${out}/${id}.caddy" >/dev/null
    render_template "${OPSKIT_ROOT}/templates/cron.tmpl" "${out}/cron" >/dev/null
  ) || { log_fail "render ${id}: failed"; return 1; }
  chmod 600 "${out}/.env"
  if [ "$(yaml_get "$hfile" .practice_quirks.ipv4_listen_shim false)" = "true" ]; then
    cp "${OPSKIT_ROOT}/templates/compose.practice.yml.tmpl" "${out}/compose.practice.yml"
    cp "${OPSKIT_ROOT}/templates/ipv4-shim.js" "${out}/ipv4-shim.js"
    log_warn "render ${id}: practice-only IPv4 shim enabled by host ${host}"
  else
    rm -f "${out}/compose.practice.yml" "${out}/ipv4-shim.js"
  fi
  log_ok "rendered ${id}: compose.yml, .env (600), ${id}.caddy, cron → ${out}"
}
