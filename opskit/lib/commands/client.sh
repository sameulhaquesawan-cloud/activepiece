#!/usr/bin/env bash
# summary: manage clients: new | pause | resume | offboard

# shellcheck source=../validate.sh
source "${OPSKIT_ROOT}/lib/validate.sh"
# shellcheck source=../schema.sh
source "${OPSKIT_ROOT}/lib/schema.sh"
# shellcheck source=../registry.sh
source "${OPSKIT_ROOT}/lib/registry.sh"
# shellcheck source=../render.sh
source "${OPSKIT_ROOT}/lib/render.sh"
# shellcheck source=../fork.sh
source "${OPSKIT_ROOT}/lib/fork.sh"
# shellcheck source=../confirm.sh
source "${OPSKIT_ROOT}/lib/confirm.sh"
# shellcheck source=../secrets.sh
source "${OPSKIT_ROOT}/lib/secrets.sh"
# shellcheck source=../stack.sh
source "${OPSKIT_ROOT}/lib/stack.sh"
# shellcheck source=../ssh.sh
source "${OPSKIT_ROOT}/lib/ssh.sh"
# shellcheck source=../host.sh
source "${OPSKIT_ROOT}/lib/host.sh"
# shellcheck source=../deploy.sh
source "${OPSKIT_ROOT}/lib/deploy.sh"

client_usage() {
  cat <<'EOF'
Usage:
  opskit client new <id> --domain <domain> --host <host> --contact <email> [--name <name>] [--timezone <tz>]
  opskit client pause <id>
  opskit client resume <id>
  opskit client offboard <id> [--purge --yes]

new       create opskit/clients/<id>/client.yaml (status draft) for a host in opskit/hosts/
pause     stop the client's containers (data kept)
resume    start them again
offboard  stop the stack and mark it offboarded; --purge deletes it and its data volumes,
          only after offboard_retention_days, with --yes and the client id typed to confirm
EOF
}

client_new() {
  local id="${1:-}" domain="" host="" contact="" name="" timezone="UTC"
  shift || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --domain) domain="${2:-}"; shift 2 ;;
      --host) host="${2:-}"; shift 2 ;;
      --contact) contact="${2:-}"; shift 2 ;;
      --name) name="${2:-}"; shift 2 ;;
      --timezone) timezone="${2:-}"; shift 2 ;;
      *) client_usage >&2; return 1 ;;
    esac
  done
  is_slug "$id" || die "client id must be a lowercase slug (e.g. acme-dental): '${id}'"
  is_domain "$domain" || die "--domain must be a lowercase domain (e.g. auto.acme.com): '${domain}'"
  is_email "$contact" || die "--contact must be an email address: '${contact}'"
  [[ "${name:-$id}" =~ ^[^\"\\]{1,120}$ ]] || die "--name must be 1-120 characters without quotes or backslashes"
  [ -n "$host" ] || die "--host is required (a file in opskit/hosts/)"
  require_host "$host" || return 1
  local dir file hfile
  dir="$(client_dir "$id")"
  file="$(client_file "$id")"
  [ ! -e "$file" ] || die "client ${id} already exists (${file})"
  hfile="$(host_file "$host")"
  mkdir -p "$dir"
  chmod 700 "$dir"
  CLIENT_ID="$id" CLIENT_NAME="${name:-$id}" CLIENT_CONTACT="$contact" CLIENT_DOMAIN="$domain" \
    HOST_ID="$host" HOST_IP="$(yaml_get "$hfile" .ip)" HOST_SSH_USER="$(yaml_get "$hfile" .ssh_user)" \
    HOST_MODE="$(yaml_get "$hfile" .mode)" AP_TAG="$(fork_pinned_tag "${OPSKIT_ROOT}/..")" \
    CLIENT_TIMEZONE="$timezone" CREATED_AT="$(date -u +%Y-%m-%d)" \
    render_template "${OPSKIT_ROOT}/templates/client.yaml.tmpl" "$file" >/dev/null || { rm -rf "$dir"; return 1; }
  client_history_add "$id" created
  if ! validate_against_schema "${OPSKIT_ROOT}/schema/client.schema.json" "$file"; then
    rm -rf "$dir"
    die "client ${id} not created"
  fi
  log_ok "client ${id} created: ${file} (status draft). Next: opskit render ${id}"
}

client_status() {
  yaml_get "$(client_file "$1")" .status
}

client_host() {
  yaml_get "$(client_file "$1")" .host.name
}

client_pause() {
  local id="${1:-}"
  require_client "$id" || return 1
  [ "$(client_status "$id")" = "deployed" ] || die "client ${id} is $(client_status "$id"); only deployed clients can be paused"
  stack_compose "$(client_host "$id")" "$id" stop >/dev/null 2>&1 || die "could not stop ${id}"
  yaml_set "$(client_file "$id")" '.status = "paused"'
  client_history_add "$id" paused
  log_ok "client ${id} paused (containers stopped, data kept). Resume: opskit client resume ${id}"
}

client_resume() {
  local id="${1:-}" host
  require_client "$id" || return 1
  [ "$(client_status "$id")" = "paused" ] || die "client ${id} is $(client_status "$id"); only paused clients can be resumed"
  host="$(client_host "$id")"
  stack_compose "$host" "$id" start >/dev/null 2>&1 || die "could not start ${id}"
  deploy_wait_healthy "$host" "$id" || return 1
  yaml_set "$(client_file "$id")" '.status = "deployed"'
  client_history_add "$id" resumed
  log_ok "client ${id} resumed"
}

client_remove_site() {
  local host="$1" id="$2" edge
  edge="$(yaml_get "$(host_file "$host")" .edge.container opskit-caddy)"
  host_run "$host" rm -f "$(host_root "$host")/caddy/etc/sites/${id}.caddy"
  host_run "$host" docker exec "$edge" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true
}

purge_allowed_from() {
  local id="$1" since days
  since="$(yaml_get "$(client_file "$id")" .offboarded_at)"
  days="$(yaml_get "$(client_file "$id")" .offboard_retention_days 30)"
  date -u -d "${since} + ${days} days" +%Y-%m-%d
}

client_offboard() {
  local id="${1:-}" purge="false" yes="false" host
  shift || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --purge) purge="true"; shift ;;
      --yes) yes="true"; shift ;;
      *) client_usage >&2; return 1 ;;
    esac
  done
  require_client "$id" || return 1
  host="$(client_host "$id")"
  if [ "$purge" = "true" ]; then
    [ "$(client_status "$id")" = "offboarded" ] || die "purge only after offboarding (client ${id} is $(client_status "$id"))"
    local allowed
    allowed="$(purge_allowed_from "$id")"
    [[ "$(date -u +%Y-%m-%d)" > "$allowed" || "$(date -u +%Y-%m-%d)" == "$allowed" ]] \
      || die "retention not over: ${id} can be purged from ${allowed} (offboard_retention_days)"
    confirm_destructive "$id" "$yes" "DELETE stack and data volumes of ${id} on ${host}" || return 1
    stack_compose "$host" "$id" down -v --remove-orphans >/dev/null 2>&1 || die "docker compose down -v failed for ${id}"
    host_run "$host" rm -rf "$(stack_remote_dir "$host" "$id")"
    client_remove_site "$host" "$id"
    client_history_add "$id" purged
    log_ok "client ${id} purged on ${host} (registry entry kept for records)"
    return 0
  fi
  [ "$(client_status "$id")" != "offboarded" ] || die "client ${id} is already offboarded"
  log_warn "before offboarding: take a final backup and export the flows (automated in Phase 3)"
  confirm_destructive "$id" "$yes" "take ${id} offline (stop stack, remove HTTPS site)" || return 1
  stack_compose "$host" "$id" stop >/dev/null 2>&1 || die "could not stop ${id}"
  client_remove_site "$host" "$id"
  yaml_set "$(client_file "$id")" ".status = \"offboarded\" | .offboarded_at = \"$(date -u +%Y-%m-%d)\""
  client_history_add "$id" offboarded
  log_ok "client ${id} offboarded; data kept until $(purge_allowed_from "$id"), then: opskit client offboard ${id} --purge --yes"
}

cmd_main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    new) client_new "$@" ;;
    pause) client_pause "$@" ;;
    resume) client_resume "$@" ;;
    offboard) client_offboard "$@" ;;
    -h|--help|"") client_usage ;;
    *) client_usage >&2; return 1 ;;
  esac
}
