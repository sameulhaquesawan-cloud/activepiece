#!/usr/bin/env bash
# opskit daily digest — standalone. Cron runs it hourly; it sends once per day at DIGEST_HOUR
# (client time zone, default 08) one summary per client: last backup, failed runs in the last
# 24 h by flow, open health problems and alerts held during quiet hours (then cleared).
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: digest.sh <client id> [--root <dir>] [--now]

--now   send the digest immediately (manual run / tests), even if one was sent today.
Config: <root>/clients/<id>/alerts.conf TIMEZONE, DIGEST_HOUR. State: <root>/state/<id>/digest.last.
EOF
}

ROOT="/opt/opskit"
CLIENT=""
FORCE="false"

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) ROOT="$2"; shift 2 ;;
      --now) FORCE="true"; shift ;;
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

local_time() {
  TZ="${TZONE:-UTC}" date -d "@$(now)" "$1"
}

backup_line() {
  local dir="${ROOT}/backups/${CLIENT}" name status ts age remote
  name="$(cat "${dir}/latest" 2>/dev/null || true)"
  status="${dir}/${name}/status.json"
  if [ -z "$name" ] || [ ! -f "$status" ]; then
    printf 'Backup: NONE found — run %s/agent/backup.sh %s\n' "$ROOT" "$CLIENT"
    return 1
  fi
  ts="$(date -u -d "${name:0:4}-${name:4:2}-${name:6:2}T${name:9:2}:${name:11:2}:${name:13:2}Z" +%s)"
  age=$(( ($(now) - ts) / 3600 ))
  remote="$(jq -r '.remote // "not configured"' "$status")"
  printf 'Backup: last %s (%sh ago), off-server: %s\n' "$name" "$age" "$remote"
  [ "$age" -le 26 ] && [ "$remote" = "ok" ]
}

runs_lines() {
  local container rows
  container="$(docker ps -q --filter "label=com.docker.compose.project=${CLIENT}" --filter "label=com.docker.compose.service=postgres" | head -n 1)"
  if [ -z "$container" ]; then
    printf 'Runs: database not running\n'
    return 1
  fi
  # shellcheck disable=SC2016
  rows="$(docker exec -i "$container" sh -c 'psql -X -q -U opskit_ro -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -tA -F "|"' <<'SQL' || true
select coalesce(v."displayName", r."flowId"),
       count(*) filter (where r.status in ('FAILED','INTERNAL_ERROR','TIMEOUT','MEMORY_LIMIT_EXCEEDED','QUOTA_EXCEEDED','LOG_SIZE_EXCEEDED')),
       count(*)
from flow_run r left join flow_version v on v.id = r."flowVersionId"
where r.environment = 'PRODUCTION' and r."finishTime" > now() - interval '24 hours'
group by 1 order by 2 desc, 3 desc;
SQL
)"
  if [ -z "$rows" ]; then
    printf 'Runs (24 h): none\n'
    return 0
  fi
  awk -F'|' '{ total += $3; failed += $2 } END { printf "Runs (24 h): %d, failed: %d\n", total, failed }' <<< "$rows"
  awk -F'|' '$2 > 0 { printf "  - %s: %d of %d failed\n", $1, $2, $3 }' <<< "$rows" | head -n 10
  ! awk -F'|' '$2 > 0 { found = 1 } END { exit !found }' <<< "$rows"
}

health_lines() {
  local dir="${ROOT}/state/${CLIENT}/health" active
  active="$(find "$dir" -maxdepth 1 -name '*.active' -printf '%f\n' 2>/dev/null | sed 's/\.active$//' | sort | paste -sd, - | sed 's/,/, /g')"
  if [ -n "$active" ]; then
    printf 'Health: open problems: %s\n' "$active"
    return 1
  fi
  printf 'Health: OK\n'
}

held_lines() {
  local held="$1"
  [ -s "$held" ] || return 0
  printf 'Held during quiet hours: %s\n' "$(grep -c . "$held")"
  jq -r '"  - [\(.severity)] \(.what[0:120])"' "$held" | head -n 10
}

main() {
  parse_args "$@"
  local client_conf="${ROOT}/clients/${CLIENT}/alerts.conf" state="${ROOT}/state/${CLIENT}" hour today body problems
  TZONE="$(conf_value "$client_conf" TIMEZONE)"
  hour="$(conf_value "$client_conf" DIGEST_HOUR)"
  mkdir -p "$state"
  exec 9> "${state}/digest.lock"
  flock -n 9 || return 0
  today="$(local_time +%F)"
  if [ "$FORCE" = "false" ]; then
    [ "$(local_time +%H)" = "${hour:-08}" ] || return 0
    [ "$(cat "${state}/digest.last" 2>/dev/null || true)" != "$today" ] || return 0
  fi
  if [ -s "${state}/held.jsonl" ]; then
    mv "${state}/held.jsonl" "${state}/held.sending"
  fi
  body="$(
    backup_line || echo "!backup"
    runs_lines || echo "!failed runs"
    health_lines || echo "!health"
    held_lines "${state}/held.sending"
  )"
  problems="$(sed -n 's/^!//p' <<< "$body" | paste -sd, - | sed 's/,/, /g')"
  body="$(grep -v '^!' <<< "$body")"
  local what="Daily summary for ${today}: all good" action="Nothing to do"
  if [ -n "$problems" ]; then
    what="Daily summary for ${today}: check ${problems}"
    action="Look at ${problems} below"
  fi
  if "$(dirname "$0")/alert.sh" --root "$ROOT" --client "$CLIENT" --severity info --no-quiet \
    --what "$what" --action "$action" --body "$body"; then
    rm -f "${state}/held.sending"
  else
    echo "[warn] digest not fully delivered; held alerts kept for the next one" >&2
    [ ! -f "${state}/held.sending" ] || cat "${state}/held.sending" >> "${state}/held.jsonl"
    rm -f "${state}/held.sending"
  fi
  printf '%s\n' "$today" > "${state}/digest.last"
}

main "$@"
