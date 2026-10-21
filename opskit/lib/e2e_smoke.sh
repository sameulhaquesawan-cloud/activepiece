#!/usr/bin/env bash
# Selftest for the upgrade smoke checks (task 6.4): every check passes on the throwaway stack, then each
# fails with its own message when its condition is broken (lowered baseline, stopped worker, a connection
# stored with another key, a migration the image does not know), and the stack is put back each time.
# The flow checks (webhook, schedule) need piece metadata: skipped offline unless OPSKIT_REQUIRE_PIECES=1.

# e2e_smoke_expect_fail <label> <check command...>: the check must fail and say why
e2e_smoke_expect_fail() {
  local label="$1" out
  shift
  if out="$("$@" 2>&1)"; then
    log_fail "smoke e2e: ${label} was not detected"
    return 1
  fi
  log_ok "smoke e2e: ${label} detected: $(grep -m 1 '^\[fail\]' <<< "$out" | cut -c 8-)"
}

e2e_smoke_wrong_key_connection() {
  local host="$1" id="$2" app value
  app="$(stack_service_container "$host" "$id" app)"
  value="$(host_run "$host" docker exec -e "AP_ENCRYPTION_KEY=$(openssl rand -hex 16)" -e RT_MARKER=smoke "$app" node -e "$RT_ENCRYPT_JS")" || return 1
  stack_psql "$host" "$id" "insert into app_connection (id, \"externalId\", \"pieceName\", value, type, status, \"ownerId\", \"projectIds\", \"displayName\", \"platformId\", scope, \"pieceVersion\") select '$(openssl rand -hex 10)s', 'opskit-smoke-wrong-key', \"pieceName\", '${value}'::jsonb, type, status, \"ownerId\", \"projectIds\", 'smoke wrong key', \"platformId\", scope, \"pieceVersion\" from app_connection limit 1" >/dev/null
}

# e2e_smoke <host> <id> <domain> <https port>: needs RT_EMAIL/RT_PASSWORD from rt_seed
e2e_smoke() {
  local host="$1" id="$2" domain="$3" port="$4" baseline since lowered auth token project
  since="$(date -u -d '-10 min' +%Y-%m-%dT%H:%M:%SZ)"
  baseline="$(smoke_baseline "$host" "$id")" || { log_fail "smoke e2e: no baseline"; return 1; }
  smoke_production "$host" "$id" "$baseline" "$since" >/dev/null || { smoke_production "$host" "$id" "$baseline" "$since" | grep -F '[fail]'; log_fail "smoke e2e: checks fail on a healthy stack"; return 1; }
  log_ok "smoke e2e: all production checks pass on ${id}"
  lowered="$(jq -c '.flows += 1' <<< "$baseline")"
  e2e_smoke_expect_fail "a lowered flow count" smoke_counts "$host" "$id" "$lowered" || return 1
  stack_compose "$host" "$id" stop worker >/dev/null 2>&1
  e2e_smoke_expect_fail "a stopped worker" smoke_containers "$host" "$id" || return 1
  stack_compose "$host" "$id" start worker >/dev/null 2>&1
  e2e_smoke_wrong_key_connection "$host" "$id" || { log_fail "smoke e2e: could not store the wrong-key connection"; return 1; }
  e2e_smoke_expect_fail "a connection stored with another key" smoke_connections_decrypt "$host" "$id" || return 1
  stack_psql "$host" "$id" "delete from app_connection where \"externalId\" = 'opskit-smoke-wrong-key'" >/dev/null
  stack_psql "$host" "$id" "insert into migrations (timestamp, name) values (1999999999999, 'OpskitSmokeProbe1999999999999')" >/dev/null
  e2e_smoke_expect_fail "a database newer than the image" smoke_schema "$host" "$id" || return 1
  stack_psql "$host" "$id" "delete from migrations where name = 'OpskitSmokeProbe1999999999999'" >/dev/null
  smoke_production "$host" "$id" "$baseline" "$since" >/dev/null || { log_fail "smoke e2e: ${id} not back to healthy"; return 1; }
  log_ok "smoke e2e: ${id} healthy again after the broken-condition checks"
  auth="$(rt_sign_in "$domain" "$port")"
  token="$(jq -r '.token // empty' <<< "$auth")"
  project="$(jq -r '.projectId // empty' <<< "$auth")"
  [ -n "$token" ] || { log_fail "smoke e2e: cannot sign in"; return 1; }
  [ -n "$(smoke_piece_version "$domain" "$port" "$token" "$project" @activepieces/piece-webhook)" ] \
    || { e2e_skip "piece metadata is not available (no internet for the app)" "smoke flow checks"; return; }
  smoke_webhook_flow "$domain" "$port" "$token" "$project" || return 1
  smoke_schedule_dry_run "$domain" "$port" "$token" "$project" || return 1
}
