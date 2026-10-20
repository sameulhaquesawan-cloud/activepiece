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

cmd_main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    new) client_new "$@" ;;
    -h|--help|"") client_usage ;;
    *) client_usage >&2; return 1 ;;
  esac
}
