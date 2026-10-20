#!/usr/bin/env bash
# opskit host health check — standalone, run by cron hourly per client.
# Disk, memory, container restarts/stops and HTTPS certificate expiry. Each problem alerts at most
# once per 24 h; when it clears, one "recovered" info alert follows.
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: health.sh <client id> [--root <dir>]

warn: disk > 85 %, memory available < 10 %, a container restarted, certificate < 14 days.
critical: disk > 95 %, a container is not running, certificate < 3 days or unreadable.
Certificates are not checked on hosts with Caddy internal TLS (practice). State: <root>/state/<id>/health/.
EOF
}

ROOT="/opt/opskit"
CLIENT=""
PROC="${OPSKIT_PROC:-/proc}"

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) ROOT="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      -*) usage >&2; exit 1 ;;
      *) CLIENT="$1"; shift ;;
    esac
  done
  [[ "$CLIENT" =~ ^[a-z][a-z0-9-]{0,30}[a-z0-9]$ ]] || { usage >&2; exit 1; }
}

conf_value() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  sed -n "s/^${key}=//p" "$file" | tail -n 1
}

now() {
  printf '%s' "${OPSKIT_NOW:-$(date +%s)}"
}

# problem <key> <severity> <what> <action>: alert (once per 24 h) and mark the condition active
problem() {
  local key="$1" severity="$2" what="$3" action="$4"
  touch "${STATE}/${key}.active"
  PROBLEMS=$((PROBLEMS + 1))
  "$(dirname "$0")/alert.sh" --root "$ROOT" --client "$CLIENT" --severity "$severity" --what "$what" --action "$action" \
    --dedupe-key "health:${key}:${severity}" --window 1440 || echo "[warn] health alert ${key} not fully delivered" >&2
}

# resolved <key> <what>: condition is fine now; one info alert if it was active
resolved() {
  local key="$1" what="$2"
  [ -e "${STATE}/${key}.active" ] || return 0
  rm -f "${STATE}/${key}.active"
  "$(dirname "$0")/alert.sh" --root "$ROOT" --client "$CLIENT" --severity info --what "Recovered: ${what}" \
    --action "Nothing to do" || true
}

check_disk() {
  local path used
  for path in "$ROOT" /var/lib/docker; do
    [ -d "$path" ] || continue
    used="$(df -P "$path" | awk 'NR == 2 { gsub("%", "", $5); print $5 }')"
    [[ "$used" =~ ^[0-9]+$ ]] || continue
    if [ "$used" -gt 95 ]; then
      problem disk critical "Disk almost full: ${used}% used on ${path}" "Free space now (old images: docker image prune; logs), or resize the disk"
      return
    elif [ "$used" -gt 85 ]; then
      problem disk warn "Disk ${used}% full on ${path}" "Free space this week (docker image prune, old logs) or resize the disk"
      return
    fi
  done
  resolved disk "disk usage is below 85%"
}

check_memory() {
  local total available percent
  total="$(awk '/^MemTotal:/ { print $2 }' "${PROC}/meminfo")"
  available="$(awk '/^MemAvailable:/ { print $2 }' "${PROC}/meminfo")"
  [[ "$total" =~ ^[0-9]+$ && "$available" =~ ^[0-9]+$ && "$total" -gt 0 ]] || return 0
  percent=$((available * 100 / total))
  if [ "$percent" -lt 10 ]; then
    problem memory warn "Low memory: ${percent}% available" "Check docker stats; lower worker replicas or move to a bigger server"
  else
    resolved memory "memory available is ${percent}%"
  fi
}

check_containers() {
  local line name count state before baseline="${STATE}/restarts" next stopped=""
  next="$(mktemp)"
  for line in $(docker ps -aq --filter "label=com.docker.compose.project=${CLIENT}" \
    | xargs -r docker inspect -f '{{.Name}} {{.RestartCount}} {{.State.Status}}'); do
    name="${line%% *}"
    name="${name#/}"
    count="$(cut -d' ' -f2 <<< "$line")"
    state="$(cut -d' ' -f3 <<< "$line")"
    printf '%s %s\n' "$name" "$count" >> "$next"
    [ "$state" = "running" ] || stopped+="${name} (${state}) "
    before="$(awk -v n="$name" '$1 == n { print $2 }' "$baseline" 2>/dev/null || true)"
    if [[ "$before" =~ ^[0-9]+$ ]] && [ "$count" -gt "$before" ]; then
      problem "restart-${name}" warn "Container ${name} restarted $((count - before)) time(s) in the last hour" \
        "Check its logs: docker logs --tail 100 ${name}"
    else
      resolved "restart-${name}" "container ${name} is stable"
    fi
  done
  mv "$next" "$baseline"
  if [ -n "$stopped" ]; then
    problem stopped critical "Containers not running: ${stopped% }" "docker compose -p ${CLIENT} up -d, then check the logs"
  else
    resolved stopped "all containers of ${CLIENT} are running"
  fi
}

check_certificate() {
  local url host_port domain port end days
  [ "$(conf_value "${ROOT}/clients/${CLIENT}/alerts.conf" TLS_MODE)" != "internal" ] || return 0
  url="$(conf_value "${ROOT}/clients/${CLIENT}/alerts.conf" APP_URL)"
  [[ "$url" =~ ^https://([^/]+) ]] || return 0
  host_port="${BASH_REMATCH[1]}"
  domain="${host_port%%:*}"
  port="443"
  [ "$host_port" = "$domain" ] || port="${host_port##*:}"
  end="$(openssl s_client -connect "127.0.0.1:${port}" -servername "$domain" < /dev/null 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | sed -n 's/^notAfter=//p' || true)"
  if [ -z "$end" ] || ! end="$(date -d "$end" +%s 2>/dev/null)"; then
    problem cert-read critical "HTTPS certificate of ${domain} could not be read" "Check Caddy: docker logs opskit-caddy; is DNS pointing here?"
    return
  fi
  resolved cert-read "certificate of ${domain} can be read again"
  days=$(( (end - $(now)) / 86400 ))
  if [ "$days" -lt 3 ]; then
    problem cert critical "HTTPS certificate of ${domain} expires in ${days} day(s)" "Check Caddy logs for ACME errors (docker logs opskit-caddy) and DNS"
  elif [ "$days" -lt 14 ]; then
    problem cert warn "HTTPS certificate of ${domain} expires in ${days} days (renewal should have happened)" "Check Caddy logs for ACME errors (docker logs opskit-caddy)"
  else
    resolved cert "certificate of ${domain} is valid for ${days} days"
  fi
}

main() {
  parse_args "$@"
  STATE="${ROOT}/state/${CLIENT}/health"
  PROBLEMS=0
  mkdir -p "$STATE"
  exec 9> "${STATE}/.lock"
  flock -n 9 || { echo "[ok] health check already running for ${CLIENT}"; return 0; }
  check_disk
  check_memory
  check_containers
  check_certificate
  if [ "$PROBLEMS" -eq 0 ]; then
    echo "[ok] ${CLIENT}: host healthy"
  else
    echo "[warn] ${CLIENT}: ${PROBLEMS} health problem(s) reported"
  fi
}

main "$@"
