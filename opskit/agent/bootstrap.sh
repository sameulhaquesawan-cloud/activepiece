#!/usr/bin/env bash
# opskit host bootstrap — standalone, idempotent. Run as root on a fresh Ubuntu 24.04 server
# (full mode) or with --edge-only on a practice machine (only the Caddy edge + directories).
set -euo pipefail
IFS=$'\n\t'

CADDY_IMAGE="caddy:2.10.0"
EDGE_NETWORK="opskit_edge"

usage() {
  cat <<'EOF'
Usage: bootstrap.sh --ssh-user <user> [options]

  --root <dir>          opskit root on the host (default /opt/opskit)
  --http-port <n>       edge HTTP port (default 80)
  --https-port <n>      edge HTTPS port (default 443)
  --tls acme|internal   certificates: Let's Encrypt (acme) or Caddy local CA (internal)
  --email <addr>        ACME account email (optional)
  --edge-name <name>    Caddy container name (default opskit-caddy)
  --edge-join <network> also connect the edge to this Docker network (repeatable; shared host)
  --firewall ufw|keep   ufw 22/80/443 (default) or keep the host's iptables (checked, e.g. Oracle)
  --swap <size>         always make a swapfile of this size (e.g. 2G); default only if RAM <= 4 GB
  --edge-only           practice machine: only directories + Caddy edge, no system changes
  --harden-ssh          write sshd drop-in: key-only, no root login (needs authorized_keys)
  --dry-run             print the plan, change nothing
EOF
}

ok() { printf '[ok] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*"; }
fail() { printf '[fail] %s\n' "$*" >&2; }

ROOT="/opt/opskit"
HTTP_PORT="80"
HTTPS_PORT="443"
TLS="acme"
EMAIL=""
EDGE_NAME="opskit-caddy"
SSH_USER=""
EDGE_ONLY="false"
HARDEN_SSH="false"
DRY_RUN="false"
FIREWALL="ufw"
SWAP_SIZE=""
EDGE_JOIN=()

run() {
  if [ "$DRY_RUN" = "true" ]; then
    local IFS=' '
    printf '[plan] %s\n' "$*"
  else
    "$@"
  fi
}

run_quiet() {
  if [ "$DRY_RUN" = "true" ]; then
    run "$@"
  else
    "$@" >/dev/null
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) ROOT="$2"; shift 2 ;;
      --http-port) HTTP_PORT="$2"; shift 2 ;;
      --https-port) HTTPS_PORT="$2"; shift 2 ;;
      --tls) TLS="$2"; shift 2 ;;
      --email) EMAIL="$2"; shift 2 ;;
      --edge-name) EDGE_NAME="$2"; shift 2 ;;
      --ssh-user) SSH_USER="$2"; shift 2 ;;
      --edge-join) EDGE_JOIN+=("$2"); shift 2 ;;
      --firewall) FIREWALL="$2"; shift 2 ;;
      --swap) SWAP_SIZE="$2"; shift 2 ;;
      --edge-only) EDGE_ONLY="true"; shift ;;
      --harden-ssh) HARDEN_SSH="true"; shift ;;
      --dry-run) DRY_RUN="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit 1 ;;
    esac
  done
  [[ "$ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || { fail "--root must be an absolute path"; exit 1; }
  [[ "$HTTP_PORT" =~ ^[0-9]{1,5}$ && "$HTTPS_PORT" =~ ^[0-9]{1,5}$ ]] || { fail "ports must be numbers"; exit 1; }
  [[ "$TLS" =~ ^(acme|internal)$ ]] || { fail "--tls must be acme or internal"; exit 1; }
  [[ "$EDGE_NAME" =~ ^[a-z][a-z0-9-]{1,40}$ ]] || { fail "invalid --edge-name"; exit 1; }
  [[ "$FIREWALL" =~ ^(ufw|keep)$ ]] || { fail "--firewall must be ufw or keep"; exit 1; }
  [[ -z "$SWAP_SIZE" || "$SWAP_SIZE" =~ ^[1-9][0-9]{0,2}[MG]$ ]] || { fail "--swap must look like 2G or 512M"; exit 1; }
  local net
  for net in "${EDGE_JOIN[@]}"; do
    [[ "$net" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,62}$ ]] || { fail "invalid --edge-join network name"; exit 1; }
  done
  if [ "$EDGE_ONLY" = "false" ]; then
    if [[ ! "$SSH_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || [ "$SSH_USER" = "root" ]; then
      fail "--ssh-user (non-root) is required"
      exit 1
    fi
  fi
}

check_os() {
  local id="" version=""
  if [ -r /etc/os-release ]; then
    id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')"
    version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')"
  fi
  if [ "$id" = "ubuntu" ] && [ "$version" = "24.04" ]; then
    ok "OS: Ubuntu 24.04"
  else
    warn "OS: ${id:-unknown} ${version:-?} (tested on Ubuntu 24.04 only)"
  fi
}

# docker.io conflicts with docker-ce: installing it over an existing Docker removes the running engine
install_packages() {
  local packages=()
  if docker compose version >/dev/null 2>&1; then
    ok "docker: existing install kept ($(docker --version 2>/dev/null || printf 'version unknown'))"
  else
    packages+=(docker.io docker-compose-v2)
  fi
  [ "$FIREWALL" = "keep" ] || packages+=(ufw)
  packages+=(unattended-upgrades cron logrotate curl age rclone)
  run env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
  run systemctl enable --now docker
  run systemctl enable --now cron
  run usermod -aG docker "$SSH_USER"
  local IFS=' '
  ok "packages: ${packages[*]} (user ${SSH_USER} in docker group)"
}

ssh_port() {
  local port
  port="$({ sshd -T 2>/dev/null || true; } | sed -n 's/^port //p' | head -n 1)"
  printf '%s' "${port:-22}"
}

# runs before any package is installed. Oracle images ship their own iptables rules
# (netfilter-persistent); ufw on top of them is unsupported
check_firewall() {
  local ssh_port rules
  ssh_port="$(ssh_port)"
  rules="$(iptables -S 2>/dev/null || true)"
  if [ "$FIREWALL" = "keep" ]; then
    check_kept_firewall "$ssh_port" "$rules"
  elif printf '%s\n' "$rules" | grep -q -- '-N InstanceServices'; then
    fail "firewall: Oracle image iptables rules found; use firewall: keep in the host yaml"
    return 1
  fi
}

setup_firewall() {
  [ "$FIREWALL" = "ufw" ] || return 0
  local ssh_port
  ssh_port="$(ssh_port)"
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw allow "${ssh_port}/tcp"
  run ufw allow 80/tcp
  run ufw allow 443/tcp
  run ufw --force enable
  ok "firewall: only ${ssh_port}/tcp, 80/tcp, 443/tcp open"
}

check_kept_firewall() {
  local ssh_port="$1" rules="$2" port
  for port in "$ssh_port" 80 443; do
    printf '%s\n' "$rules" | grep -qE -- "^-A INPUT .*--dport ${port} .*-j ACCEPT" \
      || { fail "firewall: iptables does not allow ${port}/tcp"; return 1; }
  done
  if ! printf '%s\n' "$rules" | grep -qE -- '^-A INPUT -j (REJECT|DROP)|^-P INPUT DROP'; then
    fail "firewall: iptables INPUT does not reject other traffic"
    return 1
  fi
  ok "firewall: existing iptables kept (${ssh_port}/tcp, 80/tcp, 443/tcp open, rest rejected)"
}

setup_unattended_upgrades() {
  if [ "$DRY_RUN" = "true" ]; then
    printf '[plan] write /etc/apt/apt.conf.d/20auto-upgrades\n'
  else
    printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
  fi
  ok "unattended security upgrades enabled"
}

logrotate_rule() {
  printf '%s/logs/*.log {\n  weekly\n  rotate 8\n  compress\n  delaycompress\n  missingok\n  notifempty\n  copytruncate\n}\n' "$ROOT"
}

setup_logrotate() {
  if [ "$DRY_RUN" = "true" ]; then
    printf '[plan] write /etc/logrotate.d/opskit:\n'
    logrotate_rule | sed 's/^/[plan]   /'
  else
    logrotate_rule > /etc/logrotate.d/opskit
    chmod 644 /etc/logrotate.d/opskit
  fi
  ok "log rotation: ${ROOT}/logs/*.log weekly, 8 kept, compressed"
}

setup_swap() {
  local ram_kb size="${SWAP_SIZE:-2G}"
  ram_kb="$(sed -n 's/^MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo)"
  if [ -z "$SWAP_SIZE" ] && [ "${ram_kb:-0}" -gt 4194304 ]; then
    ok "swap: not needed (RAM > 4 GB)"
    return
  fi
  if swapon --show=NAME --noheadings 2>/dev/null | grep -q .; then
    ok "swap: already active"
    return
  fi
  run fallocate -l "$size" /swapfile
  run chmod 600 /swapfile
  run mkswap /swapfile
  run swapon /swapfile
  if [ "$DRY_RUN" = "false" ] && ! grep -q '^/swapfile ' /etc/fstab; then
    printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
  fi
  ok "swap: ${size} /swapfile"
}

check_ssh() {
  local settings password root
  settings="$(sshd -T 2>/dev/null || true)"
  password="$(printf '%s\n' "$settings" | sed -n 's/^passwordauthentication //p')"
  root="$(printf '%s\n' "$settings" | sed -n 's/^permitrootlogin //p')"
  if [ "$password" = "no" ] && [ "$root" = "no" ]; then
    ok "ssh: key-only, root login disabled"
    return 0
  fi
  if [ "$HARDEN_SSH" = "true" ]; then
    local keys
    keys="$(getent passwd "$SSH_USER" | cut -d: -f6)/.ssh/authorized_keys"
    [ -s "$keys" ] || { fail "ssh: ${SSH_USER} has no authorized_keys; refusing to disable passwords (lockout risk)"; return 1; }
    if [ "$DRY_RUN" = "true" ]; then
      printf '[plan] write /etc/ssh/sshd_config.d/99-opskit.conf and reload ssh\n'
    else
      printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/99-opskit.conf
      sshd -t && systemctl reload ssh
    fi
    ok "ssh: hardened (key-only, no root login)"
    return 0
  fi
  fail "ssh: password login '${password:-?}', root login '${root:-?}' — re-run with --harden-ssh (after confirming key login works)"
  return 1
}

write_caddyfile() {
  local file="${ROOT}/caddy/etc/Caddyfile" tmp
  tmp="$(mktemp)"
  {
    printf '{\n'
    printf '\thttp_port %s\n\thttps_port %s\n' "$HTTP_PORT" "$HTTPS_PORT"
    [ -n "$EMAIL" ] && printf '\temail %s\n' "$EMAIL"
    [ "$TLS" = "internal" ] && printf '\tlocal_certs\n'
    printf '}\n\nimport /etc/caddy/sites/*.caddy\n'
  } > "$tmp"
  if [ "$DRY_RUN" = "true" ]; then
    printf '[plan] write %s\n' "$file"
    rm -f "$tmp"
  else
    install -m 644 "$tmp" "$file"
    rm -f "$tmp"
  fi
}

setup_edge() {
  run mkdir -p "${ROOT}/clients" "${ROOT}/caddy/etc/sites" "${ROOT}/caddy/data" "${ROOT}/caddy/config" "${ROOT}/agent" "${ROOT}/logs"
  if [ "$EDGE_ONLY" = "false" ]; then
    run chown -R "${SSH_USER}:${SSH_USER}" "$ROOT"
  fi
  write_caddyfile
  if [ "$DRY_RUN" = "false" ] && ! docker network inspect "$EDGE_NETWORK" >/dev/null 2>&1; then
    docker network create "$EDGE_NETWORK" >/dev/null
  elif [ "$DRY_RUN" = "true" ]; then
    printf '[plan] docker network create %s (if missing)\n' "$EDGE_NETWORK"
  fi
  local current=""
  current="$(docker inspect -f '{{.Config.Image}}' "$EDGE_NAME" 2>/dev/null || true)"
  if [ "$current" = "$CADDY_IMAGE" ]; then
    run_quiet docker start "$EDGE_NAME"
    run_quiet docker exec "$EDGE_NAME" caddy reload --config /etc/caddy/Caddyfile
  else
    [ -z "$current" ] || run_quiet docker rm -f "$EDGE_NAME"
    run_quiet docker run -d --name "$EDGE_NAME" --restart unless-stopped \
      --network "$EDGE_NETWORK" \
      -p "${HTTP_PORT}:${HTTP_PORT}" -p "${HTTPS_PORT}:${HTTPS_PORT}" \
      -v "${ROOT}/caddy/etc:/etc/caddy:ro" \
      -v "${ROOT}/caddy/data:/data" -v "${ROOT}/caddy/config:/config" \
      "$CADDY_IMAGE"
  fi
  join_edge_networks || return 1
  wait_edge_ready || return 1
  ok "edge: ${EDGE_NAME} (${CADDY_IMAGE}) on ${HTTP_PORT}/${HTTPS_PORT}, network ${EDGE_NETWORK}, TLS ${TLS}"
}

# shared host: the edge also proxies sites of other compose projects on their own networks
join_edge_networks() {
  local net
  for net in "${EDGE_JOIN[@]}"; do
    if [ "$DRY_RUN" = "true" ]; then
      printf '[plan] docker network connect %s %s (if not joined)\n' "$net" "$EDGE_NAME"
      continue
    fi
    docker network inspect "$net" >/dev/null 2>&1 || { fail "edge: Docker network ${net} not found"; return 1; }
    if ! docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$EDGE_NAME" | tr ' ' '\n' | grep -qxF "$net"; then
      docker network connect "$net" "$EDGE_NAME"
    fi
    ok "edge: joined network ${net}"
  done
}

# Caddy accepts reloads only once its admin endpoint is up; a reload of the same config is harmless
wait_edge_ready() {
  local _
  [ "$DRY_RUN" = "false" ] || return 0
  for _ in $(seq 1 30); do
    docker exec "$EDGE_NAME" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 && return 0
    sleep 1
  done
  fail "edge ${EDGE_NAME} started but does not accept a config reload after 30 s (docker logs ${EDGE_NAME})"
  return 1
}

main() {
  parse_args "$@"
  [ "$DRY_RUN" = "true" ] && warn "dry run: nothing will be changed"
  if [ "$EDGE_ONLY" = "false" ]; then
    [ "$(id -u)" -eq 0 ] || [ "$DRY_RUN" = "true" ] || { fail "run as root (sudo)"; exit 1; }
    check_os
    if ! check_firewall; then
      [ "$DRY_RUN" = "true" ] || exit 1
      PLAN_PROBLEM="firewall"
    fi
    install_packages
    [ -n "${PLAN_PROBLEM:-}" ] || setup_firewall
    setup_unattended_upgrades
    setup_logrotate
    setup_swap
    if ! check_ssh; then
      [ "$DRY_RUN" = "true" ] || exit 1
      PLAN_PROBLEM="${PLAN_PROBLEM:+${PLAN_PROBLEM}, }ssh"
    fi
  fi
  setup_edge
  if [ -n "${PLAN_PROBLEM:-}" ]; then
    fail "plan incomplete: fix the ${PLAN_PROBLEM} problem above"
    exit 1
  fi
  ok "bootstrap complete"
}

main "$@"
