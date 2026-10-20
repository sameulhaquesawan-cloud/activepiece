#!/usr/bin/env bash
# summary: prepare a host: bootstrap (Docker, firewall, updates, swap, ssh check, HTTPS edge)

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

host_usage() {
  cat <<'USAGE'
Usage: opskit host bootstrap <host> [--dry-run] [--harden-ssh]

Runs opskit/agent/bootstrap.sh for opskit/hosts/<host>.yaml:
  ssh hosts   full setup over SSH with sudo (Docker, ufw 22/80/443, unattended upgrades,
              swap if RAM <= 4 GB, ssh key-only check) + Caddy edge
  local hosts edge only (directories + Caddy) — practice machine, selftest
USAGE
}

bootstrap_args() {
  local file
  file="$(host_file "$1")"
  printf '%s\n' --root "$(yaml_get "$file" .opskit_root /opt/opskit)" \
    --http-port "$(yaml_get "$file" .edge.http_port 80)" \
    --https-port "$(yaml_get "$file" .edge.https_port 443)" \
    --tls "$(yaml_get "$file" .edge.tls acme)" \
    --edge-name "$(yaml_get "$file" .edge.container opskit-caddy)"
  local email
  email="$(yaml_get "$file" .edge.acme_email)"
  [ -z "$email" ] || printf '%s\n' --email "$email"
}

host_bootstrap() {
  local host="${1:-}" extra=() args script
  shift || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run|--harden-ssh) extra+=("$1"); shift ;;
      *) host_usage >&2; return 1 ;;
    esac
  done
  require_host "$host" || return 1
  mapfile -t args < <(bootstrap_args "$host")
  script="${OPSKIT_ROOT}/agent/bootstrap.sh"
  if [ "$(host_transport "$host")" = "local" ]; then
    bash "$script" --edge-only "${args[@]}" "${extra[@]}"
    return
  fi
  local user
  user="$(yaml_get "$(host_file "$host")" .ssh_user)"
  host_put "$host" "$script" /tmp/opskit-bootstrap.sh 700 || return 1
  host_run "$host" sudo -n bash /tmp/opskit-bootstrap.sh --ssh-user "$user" "${args[@]}" "${extra[@]}"
}

cmd_main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    bootstrap) host_bootstrap "$@" ;;
    -h|--help|"") host_usage ;;
    *) host_usage >&2; return 1 ;;
  esac
}
