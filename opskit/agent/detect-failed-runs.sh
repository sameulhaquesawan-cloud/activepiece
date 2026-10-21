#!/usr/bin/env bash
# opskit failed-run detector — standalone, run by cron every 5 minutes per client.
# Reads flow_run with the read-only role opskit_ro (read-only SQL only) and sends one alert per
# failing flow per 30 minutes through alert.sh (flow name, run id, error excerpt, run link).
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: detect-failed-runs.sh <client id> [--root <dir>] [--window <minutes>]

Looks at PRODUCTION runs that finished since the last check with status FAILED, INTERNAL_ERROR,
TIMEOUT, MEMORY_LIMIT_EXCEEDED, QUOTA_EXCEEDED or LOG_SIZE_EXCEEDED. The first run only records
the starting point (no alerts for old history). State: <root>/state/<id>/detector.since.
Run links use APP_URL from <root>/clients/<id>/alerts.conf; ERROR_EXCERPTS=false there leaves the
error text out of alerts (client setting alerts.include_error_excerpt).
EOF
}

ROOT="/opt/opskit"
CLIENT=""
WINDOW=30

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) ROOT="$2"; shift 2 ;;
      --window) WINDOW="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      -*) usage >&2; exit 1 ;;
      *) CLIENT="$1"; shift ;;
    esac
  done
  [[ "$CLIENT" =~ ^[a-z][a-z0-9-]{0,30}[a-z0-9]$ ]] || { usage >&2; exit 1; }
  [[ "$WINDOW" =~ ^[0-9]{1,5}$ ]] || { echo "[fail] --window must be minutes" >&2; exit 1; }
}

conf_value() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  sed -n "s/^${key}=//p" "$file" | tail -n 1
}

postgres_container() {
  docker ps -q --filter "label=com.docker.compose.project=${CLIENT}" --filter "label=com.docker.compose.service=postgres" | head -n 1
}

# ro_query <container> <sql> [psql -v name=value...]: read-only role, unaligned, no headers
ro_query() {
  local container="$1" sql="$2"
  shift 2
  # shellcheck disable=SC2016
  docker exec -i "$container" sh -c 'psql -X -q -U opskit_ro -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -tA "$@"' _ "$@" <<< "$sql"
}

db_now() {
  ro_query "$1" "select to_char(now() at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"');"
}

failed_runs() {
  local container="$1" since="$2" until="$3"
  ro_query "$container" "
    select json_build_object(
      'id', r.id, 'projectId', r.\"projectId\", 'flowId', r.\"flowId\",
      'flow', coalesce(v.\"displayName\", r.\"flowId\"), 'status', r.status,
      'step', coalesce(r.\"failedStep\"->>'displayName', r.\"failedStep\"->>'name', ''),
      'message', coalesce(r.\"failedStep\"->>'message', ''))
    from flow_run r
    left join flow_version v on v.id = r.\"flowVersionId\"
    where r.environment = 'PRODUCTION'
      and r.status in ('FAILED', 'INTERNAL_ERROR', 'TIMEOUT', 'MEMORY_LIMIT_EXCEEDED', 'QUOTA_EXCEEDED', 'LOG_SIZE_EXCEEDED')
      and r.\"finishTime\" > :'since'::timestamptz and r.\"finishTime\" <= :'until'::timestamptz
    order by r.\"finishTime\";" -v "since=${since}" -v "until=${until}"
}

# alert_flow <runs json array of one flow>: one alert for the newest run, counting the others
alert_flow() {
  local runs="$1" app_url count latest what link excerpts
  app_url="$(conf_value "${ROOT}/clients/${CLIENT}/alerts.conf" APP_URL)"
  excerpts="$(conf_value "${ROOT}/clients/${CLIENT}/alerts.conf" ERROR_EXCERPTS)"
  count="$(jq 'length' <<< "$runs")"
  latest="$(jq -c '.[-1]' <<< "$runs")"
  what="$(jq -r --argjson count "$count" --arg excerpts "${excerpts:-true}" '
    (if $excerpts == "false" then "" else
      (.message | (try (fromjson | .message // tostring) catch .) | tostring | gsub("[\r\n\t]+"; " ") | .[0:160]) end) as $excerpt
    | (if $count > 1 then "\($count) runs of flow \"\(.flow)\" failed" else "Flow \"\(.flow)\" failed" end)
      + " (\(.status)" + (if .step != "" then " at step \"\(.step)\"" else "" end) + ")"
      + (if $excerpt != "" then ": \($excerpt)" else "" end)
      + " — run \(.id)"' <<< "$latest")"
  link=()
  [ -z "$app_url" ] || link=(--link "${app_url%/}/projects/$(jq -r .projectId <<< "$latest")/runs/$(jq -r .id <<< "$latest")")
  "$(dirname "$0")/alert.sh" --root "$ROOT" --client "$CLIENT" --severity critical --what "$what" \
    --action "Open the run, fix the failing step, then retry the failed runs" \
    "${link[@]}" --dedupe-key "failed-run:$(jq -r .flowId <<< "$latest")" --window "$WINDOW" \
    || echo "[warn] alert for flow $(jq -r .flowId <<< "$latest") not fully delivered" >&2
}

main() {
  parse_args "$@"
  local state="${ROOT}/state/${CLIENT}" container since until rows
  mkdir -p "$state"
  exec 9> "${state}/detector.lock"
  flock -n 9 || { echo "[ok] detector already running for ${CLIENT}"; return 0; }
  container="$(postgres_container)"
  [ -n "$container" ] || { echo "[warn] postgres of ${CLIENT} is not running; nothing checked" >&2; return 1; }
  until="$(db_now "$container")" || { echo "[fail] cannot query ${CLIENT} as opskit_ro" >&2; return 1; }
  since="$(cat "${state}/detector.since" 2>/dev/null || true)"
  if [ -z "$since" ]; then
    printf '%s\n' "$until" > "${state}/detector.since"
    echo "[ok] detector started for ${CLIENT}; runs that finish from now on are checked"
    return 0
  fi
  rows="$(failed_runs "$container" "$since" "$until")" || { echo "[fail] failed-run query on ${CLIENT} failed" >&2; return 1; }
  if [ -n "$rows" ]; then
    jq -sc 'group_by(.flowId)[]' <<< "$rows" | while IFS= read -r runs; do
      alert_flow "$runs"
    done
  fi
  printf '%s\n' "$until" > "${state}/detector.since"
  echo "[ok] ${CLIENT}: $(grep -c . <<< "$rows" || true) failed runs since ${since}"
}

main "$@"
