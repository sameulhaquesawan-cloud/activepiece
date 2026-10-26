#!/usr/bin/env bash
# summary: prepare a host: cloud-init user data, read-only preflight, bootstrap (Docker, firewall, updates, swap, ssh, HTTPS edge)

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
# shellcheck source=../deploy.sh
source "${OPSKIT_ROOT}/lib/deploy.sh"
# shellcheck source=../preflight.sh
source "${OPSKIT_ROOT}/lib/preflight.sh"

host_usage() {
  cat <<'USAGE'
Usage: opskit host bootstrap <host> [--dry-run] [--harden-ssh]
       opskit host preflight <host>
       opskit host cloud-init --user <name> --key <public key file>

cloud-init  prints the user data to paste into the provider's "cloud config" box when creating a
            server: a non-root user with your SSH key and passwordless sudo, no root or password login
preflight   read-only: ssh, sudo, Ubuntu 24.04, CPU/memory/disk, IPv6, cron, Docker, outbound HTTPS,
            and the DNS A record of every client domain on the host (and its monitor domain)
bootstrap

Runs opskit/agent/bootstrap.sh for opskit/hosts/<host>.yaml:
  ssh hosts   full setup over SSH with sudo (Docker, ufw 22/80/443, unattended upgrades,
              swap if RAM <= 4 GB, ssh key-only check) + Caddy edge
              shared host: firewall: keep (host iptables), swap: 2G, edge.join_networks
              (an existing Docker install is always kept)
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
  printf '%s\n' --firewall "$(yaml_get "$file" .firewall ufw)"
  local swap net
  swap="$(yaml_get "$file" .swap)"
  [ -z "$swap" ] || printf '%s\n' --swap "$swap"
  while IFS= read -r net; do
    [ -z "$net" ] || printf '%s\n' --edge-join "$net"
  done < <(yq -r '.edge.join_networks // [] | .[]' "$file")
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

host_cloud_init_cmd() {
  local user="" key=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --user) user="${2:-}"; shift 2 || { host_usage >&2; return 1; } ;;
      --key) key="${2:-}"; shift 2 || { host_usage >&2; return 1; } ;;
      *) host_usage >&2; return 1 ;;
    esac
  done
  if [ -z "$user" ] || [ -z "$key" ]; then
    host_usage >&2
    return 1
  fi
  host_cloud_init "$user" "$key"
}

cmd_main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    bootstrap) host_bootstrap "$@" ;;
    preflight)
      [ "$#" -eq 1 ] || { host_usage >&2; return 1; }
      require_host "$1" || return 1
      host_preflight "$1"
      ;;
    cloud-init) host_cloud_init_cmd "$@" ;;
    -h|--help|"") host_usage ;;
    *) host_usage >&2; return 1 ;;
  esac
}
