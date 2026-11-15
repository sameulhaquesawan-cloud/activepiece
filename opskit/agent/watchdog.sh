#!/usr/bin/env bash
# opskit container watchdog — standalone, run by cron every 2 minutes per client.
# Docker marks a container "unhealthy" but never restarts it (a hung app, e.g. JavaScript heap
# exhausted, spins at 100 % CPU without exiting). Restart it, at most 3 times in 6 hours.
set -euo pipefail
IFS=$'\n\t'

GRACE_SECONDS=600
WINDOW_SECONDS=21600
MAX_RESTARTS=3

usage() {
  cat <<'EOF'
Usage: watchdog.sh <client id> [--root <dir>]

Restarts a container of the client that Docker reports "unhealthy", unless it started less than
10 min ago (first start, migrations) or was already restarted 3 times in 6 h (then: critical
alert, no restart). Every restart sends a critical alert. State: <root>/state/<id>/watchdog/.
EOF
}

ROOT="/opt/opskit"
CLIENT=""

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

alert() {
  "$(dirname "$0")/alert.sh" --root "$ROOT" --client "$CLIENT" --severity critical --what "$2" --action "$3" \
    --dedupe-key "watchdog:$1" --window "$4" || echo "[warn] watchdog alert $1 not fully delivered" >&2
}

# recent_restarts <name>: keeps only restarts inside the window and prints how many remain
recent_restarts() {
  local file="${STATE}/$1.restarts" now kept
  now="$(date +%s)"
  [ -f "$file" ] || { printf '0'; return; }
  kept="$(awk -v min="$((now - WINDOW_SECONDS))" '$1 >= min' "$file")"
  printf '%s\n' "$kept" | sed '/^$/d' > "$file"
  wc -l < "$file" | tr -d ' '
}

check_container() {
  local name="$1" started="$2" age count
  age=$(( $(date +%s) - $(date -d "$started" +%s) ))
  if [ "$age" -lt "$GRACE_SECONDS" ]; then
    echo "[warn] ${CLIENT}: ${name} unhealthy but started less than 10 min ago; not restarting yet"
    return
  fi
  count="$(recent_restarts "$name")"
  if [ "$count" -ge "$MAX_RESTARTS" ]; then
    echo "[fail] ${CLIENT}: ${name} restarted ${count} times in 6 h; not restarting again"
    alert "giveup:${name}" "Container ${name} keeps hanging: restarted ${count} times in 6 hours, now left unhealthy" \
      "Check docker logs --tail 200 ${name} (heap out of memory? raise app.memory_limit), then docker restart ${name}" 360
    return
  fi
  docker restart "$name" >/dev/null
  date +%s >> "${STATE}/${name}.restarts"
  echo "[warn] ${CLIENT}: restarted unhealthy container ${name}"
  alert "restart:${name}:$(date +%s)" "Container ${name} stopped answering its health check and was restarted" \
    "Check docker logs --tail 200 ${name} for the cause (heap out of memory? raise app.memory_limit)" 1
}

main() {
  parse_args "$@"
  STATE="${ROOT}/state/${CLIENT}/watchdog"
  mkdir -p "$STATE"
  exec 9> "${STATE}/.lock"
  flock -n 9 || { echo "[ok] watchdog already running for ${CLIENT}"; return 0; }
  local line name health started unhealthy=0
  for line in $(docker ps -q --filter "label=com.docker.compose.project=${CLIENT}" \
    | xargs -r docker inspect -f '{{.Name}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} {{.State.StartedAt}}'); do
    IFS=' ' read -r name health started <<< "$line"
    name="${name#/}"
    [ "$health" = "unhealthy" ] || continue
    unhealthy=$((unhealthy + 1))
    check_container "$name" "$started"
  done
  [ "$unhealthy" -gt 0 ] || echo "[ok] ${CLIENT}: no unhealthy containers"
}

main "$@"
