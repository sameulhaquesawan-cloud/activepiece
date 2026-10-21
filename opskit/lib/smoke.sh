#!/usr/bin/env bash
# Smoke checks for a running client stack (upgrade staging and production, selftest). Each prints one
# [ok]/[fail] line and returns non-zero on failure. OPSKIT_SMOKE_FAIL=<check> makes that check fail on
# purpose (tests of the rollback path); <scope>:<check> only where SMOKE_SCOPE is that scope
# (the upgrade sets staging / production). Needs deploy.sh, verify.sh (and roundtrip.sh for the flow checks).

SMOKE_ENGINE_ERRORS="'INTERNAL_ERROR', 'TIMEOUT', 'MEMORY_LIMIT_EXCEEDED'"
SMOKE_SERVICES=(app worker postgres redis)
SMOKE_MANIFEST="/usr/src/app/packages/server/api/dist/src/migration-manifest.json"

smoke_injected() {
  local want="${OPSKIT_SMOKE_FAIL:-}"
  if [[ "$want" == *:* ]]; then
    [ "${want%%:*}" = "${SMOKE_SCOPE:-}" ] || return 1
    want="${want#*:}"
  fi
  [ "$want" = "$1" ] || return 1
  log_fail "smoke ${1}: injected failure (OPSKIT_SMOKE_FAIL)"
}

smoke_health() {
  smoke_injected health && return 1
  deploy_wait_healthy "$1" "$2"
}

# smoke_containers <host> <id>: app, worker, postgres and redis exist and are running
smoke_containers() {
  local host="$1" id="$2" states service state problems=""
  smoke_injected containers && return 1
  states="$(stack_compose "$host" "$id" ps -a --format '{{.Service}} {{.State}}' 2>/dev/null || true)"
  for service in "${SMOKE_SERVICES[@]}"; do
    state="$(awk -v s="$service" '$1 == s { print $2; exit }' <<< "$states")"
    [ "$state" = "running" ] || problems+="${service} ${state:-missing}, "
  done
  if [ -n "$problems" ]; then
    log_fail "containers of ${id}: ${problems%, }"
    return 1
  fi
  log_ok "containers of ${id}: ${SMOKE_SERVICES[*]} running"
}

smoke_worker() {
  smoke_injected worker && return 1
  deploy_wait_worker "$1" "$2" "$3"
}

smoke_https() {
  smoke_injected https && return 1
  deploy_check_https "$1" "$2"
}

# smoke_baseline <host> <id>: {"flows","connections","runs","enabled"} of the running stack
smoke_baseline() {
  stack_psql "$1" "$2" "select json_build_object('flows', (select count(*) from flow), 'connections', (select count(*) from app_connection), 'runs', (select count(*) from flow_run), 'enabled', (select count(*) from flow where status = 'ENABLED'))"
}

# smoke_counts <host> <id> <baseline json>: flows, connections and runs are not fewer than before
smoke_counts() {
  local host="$1" id="$2" baseline="$3" now problems
  smoke_injected counts && return 1
  now="$(smoke_baseline "$host" "$id")" || { log_fail "counts of ${id}: database not readable"; return 1; }
  problems="$(jq -rn --argjson b "$baseline" --argjson n "$now" \
    '[("flows", "connections", "runs") | select($n[.] < $b[.]) | "\(.) \($n[.]) < \($b[.])"] | join(", ")')"
  if [ -n "$problems" ]; then
    log_fail "counts of ${id} dropped: ${problems}"
    return 1
  fi
  log_ok "counts of ${id}: $(jq -r '"\(.flows) flows, \(.connections) connections, \(.runs) runs"' <<< "$now") (none lower than before)"
}

# smoke_enabled_flows <host> <id> <baseline json>: the same number of flows is switched on
smoke_enabled_flows() {
  local host="$1" id="$2" baseline="$3" now before
  smoke_injected enabled_flows && return 1
  now="$(smoke_baseline "$host" "$id" | jq -r '.enabled')" || { log_fail "enabled flows of ${id}: database not readable"; return 1; }
  before="$(jq -r '.enabled' <<< "$baseline")"
  if [ "$now" != "$before" ]; then
    log_fail "enabled flows of ${id}: ${now} now, ${before} before"
    return 1
  fi
  log_ok "enabled flows of ${id}: ${now} (unchanged)"
}

smoke_connections_decrypt() {
  local host="$1" id="$2" result
  smoke_injected connections_decrypt && return 1
  result="$(stack_connections_decrypt "$host" "$id")" || true
  if [[ "$result" =~ ^([0-9]+)\ 0$ ]]; then
    log_ok "connections of ${id}: all ${BASH_REMATCH[1]} decrypt with the stack's key"
    return 0
  fi
  if [[ "$result" =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
    log_fail "connections of ${id}: ${BASH_REMATCH[2]} of $(( BASH_REMATCH[1] + BASH_REMATCH[2] )) do not decrypt (wrong AP_ENCRYPTION_KEY?)"
  else
    log_fail "connections of ${id}: decrypt check could not run"
  fi
  return 1
}

# smoke_no_failed_runs <host> <id> <since ISO time>: no production run hit an engine error since (read-only
# role). Plain FAILED runs are left to the failed-run alerts: they are usually the client's data, not the upgrade.
smoke_no_failed_runs() {
  local host="$1" id="$2" since="$3" pg count
  smoke_injected no_failed_runs && return 1
  pg="$(stack_service_container "$host" "$id" postgres)"
  [ -n "$pg" ] || { log_fail "failed runs of ${id}: postgres not running"; return 1; }
  # shellcheck disable=SC2016
  count="$(host_run "$host" docker exec "$pg" sh -c 'psql -U opskit_ro -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -tA -c "$1"' _ \
    "select count(*) from flow_run where environment = 'PRODUCTION' and status in (${SMOKE_ENGINE_ERRORS}) and \"finishTime\" > '${since}'::timestamptz" 2>/dev/null || true)"
  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    log_fail "failed runs of ${id}: read-only query did not run"
    return 1
  fi
  if [ "$count" != "0" ]; then
    log_fail "failed runs of ${id}: ${count} production run(s) ended in an engine error since ${since}"
    return 1
  fi
  log_ok "failed runs of ${id}: no engine errors since ${since}"
}

# smoke_schema <host> <id>: the database has every migration the running image ships, and no more
# unknown ones than the image's unnamed (null) manifest entries: else old code runs on a newer schema
smoke_schema() {
  local host="$1" id="$2" app manifest db missing extra unnamed
  smoke_injected schema && return 1
  app="$(stack_service_container "$host" "$id" app)"
  [ -n "$app" ] || { log_fail "schema of ${id}: app not running"; return 1; }
  manifest="$(host_run "$host" docker exec "$app" cat "$SMOKE_MANIFEST" 2>/dev/null)" \
    || { log_fail "schema of ${id}: the image has no migration manifest"; return 1; }
  db="$(stack_psql "$host" "$id" 'select name from migrations' | sort)" \
    || { log_fail "schema of ${id}: migrations table not readable"; return 1; }
  missing="$(comm -23 <(jq -r '.[] | select(. != null)' <<< "$manifest" | sort) <(printf '%s\n' "$db") | grep -c . || true)"
  extra="$(comm -13 <(jq -r '.[] | select(. != null)' <<< "$manifest" | sort) <(printf '%s\n' "$db") | grep -c . || true)"
  unnamed="$(jq '[.[] | select(. == null)] | length' <<< "$manifest")"
  if [ "$missing" != "0" ]; then
    log_fail "schema of ${id}: ${missing} migration(s) of the image are not applied"
    return 1
  fi
  if [ "$extra" -gt "$unnamed" ]; then
    log_fail "schema of ${id}: the database has $(( extra - unnamed )) migration(s) this image does not know (database newer than the code)"
    return 1
  fi
  log_ok "schema of ${id}: matches the image ($(jq length <<< "$manifest") migrations)"
}

# smoke_production <host> <id> <baseline json> <since ISO time>: the checks run on a client's stack
smoke_production() {
  local host="$1" id="$2" baseline="$3" since="$4" failed=0 check
  for check in health containers https schema; do
    "smoke_${check}" "$host" "$id" || failed=1
  done
  smoke_worker "$host" "$id" "$since" || failed=1
  smoke_counts "$host" "$id" "$baseline" || failed=1
  smoke_enabled_flows "$host" "$id" "$baseline" || failed=1
  smoke_connections_decrypt "$host" "$id" || failed=1
  smoke_no_failed_runs "$host" "$id" "$since" || failed=1
  return "$failed"
}
