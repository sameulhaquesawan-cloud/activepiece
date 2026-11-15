#!/usr/bin/env bash
# opskit upgrade, staging step (task 6.5): fresh backup of the client → restore into a temporary stack on
# THIS machine running the target image → throwaway admin password in that copy only → smoke set incl.
# a webhook and a schedule flow → temporary stack removed. The client's own stack is never touched.
# Needs upgrade_run.sh, smoke.sh, smoke_flows.sh, practice.sh, roundtrip.sh, e2e.sh, restore pieces.

# shellcheck disable=SC2016 # jq filters use $vars

# upgrade_stage_backup <host> <id>: runs the backup agent (allowed during the upgrade); prints the backup name
upgrade_stage_backup() {
  local host="$1" id="$2" root rc=0
  root="$(host_root "$host")"
  host_run "$host" "${root}/agent/backup.sh" "$id" --root "$root" --during-upgrade >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    log_fail "fresh backup of ${id} failed (exit ${rc}): run opskit backup ${id} to see why"
    return 1
  fi
  host_run "$host" cat "${root}/backups/${id}/latest"
}

# upgrade_stage_password <host> <stack id>: sets a random password for the platform owner in that
# (throwaway) database only; prints "<email> <password>"
upgrade_stage_password() {
  local host="$1" stack="$2" email password
  password="Stage-$(openssl rand -hex 12)"
  email="$(stack_psql "$host" "$stack" "select ui.email from platform p join \"user\" u on u.id = p.\"ownerId\" join user_identity ui on ui.id = u.\"identityId\" order by p.created limit 1")" \
    || return 1
  [ -n "$email" ] || return 1
  stack_psql "$host" "$stack" "create extension if not exists pgcrypto" >/dev/null || return 1
  stack_psql "$host" "$stack" "update user_identity set password = crypt('${password}', gen_salt('bf', 10)), verified = true where email = '${email//\'/\'\'}'" >/dev/null || return 1
  printf '%s %s' "$email" "$password"
}

# upgrade_stage_checks <id> <baseline json> <since>: runs inside the temporary registry (OPSKIT_REGISTRY=$TEMP_WORK)
upgrade_stage_checks() {
  local id="$1" baseline="$2" since="$3" failed=0 creds auth token project domain
  smoke_production "$TEMP_HOST" "$TEMP_ID" "$baseline" "$since" || failed=1
  domain="${TEMP_ID}.localhost"
  if ! creds="$(upgrade_stage_password "$TEMP_HOST" "$TEMP_ID")"; then
    log_fail "staging: could not set a temporary admin password in the copy"
    return 1
  fi
  # shellcheck disable=SC2034 # read by rt_sign_in
  RT_EMAIL="${creds%% *}" RT_PASSWORD="${creds#* }"
  auth="$(rt_sign_in "$domain" "$TEMP_PORT")"
  token="$(jq -r '.token // empty' <<< "$auth" 2>/dev/null || true)"
  project="$(jq -r '.projectId // empty' <<< "$auth" 2>/dev/null || true)"
  if [ -z "$token" ]; then
    log_fail "staging: sign-in to the copy failed"
    return 1
  fi
  log_ok "staging: signed in to the copy with a temporary password"
  if [ -z "$(smoke_piece_version "$domain" "$TEMP_PORT" "$token" "$project" @activepieces/piece-webhook)" ]; then
    OPSKIT_REQUIRE_PIECES="${OPSKIT_REQUIRE_PIECES:-1}" e2e_skip "piece metadata is not available (no internet for the app)" "staging flow checks" \
      || failed=1
    return "$failed"
  fi
  smoke_webhook_flow "$domain" "$TEMP_PORT" "$token" "$project" || failed=1
  smoke_schedule_dry_run "$domain" "$TEMP_PORT" "$token" "$project" || failed=1
  return "$failed"
}

# upgrade_do_stage <id> <state file>
upgrade_do_stage() {
  local id="$1" file="$2" host to name baseline since start rc=0 dir
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  to="$(jq -r '.to' "$file")"
  dir="$(dirname "$file")"
  start="$(date +%s)"
  since="$(upgrade_now)"
  baseline="$(smoke_baseline "$host" "$id")" || { log_fail "staging: could not read ${id}'s counts"; return 1; }
  upgrade_state_set "$file" '.baseline = $b' --argjson b "$baseline"
  name="$(upgrade_stage_backup "$host" "$id")" || return 1
  [ -n "$name" ] || { log_fail "staging: the fresh backup of ${id} left no name"; return 1; }
  upgrade_state_set "$file" '.stage_backup = $n' --arg n "$name"
  log_ok "fresh backup ${id}/${name}"
  log_info "Staging: restoring ${name} into a temporary stack on this machine with ${to} (a few minutes)"
  if temp_stack_restore "$id" "$name" upgrade-stage "$to"; then
    log_ok "staging copy ${TEMP_ID} restored and started on ${to}"
    ( export OPSKIT_REGISTRY="$TEMP_WORK" SMOKE_SCOPE=staging; upgrade_stage_checks "$id" "$baseline" "$since" ) 2>&1 | tee "${dir}/stage-checks.log" \
      || true
    grep -q '^\[fail\]' "${dir}/stage-checks.log" && rc=1
  else
    rc=1
    log_fail "staging: ${TEMP_REASON}"
  fi
  cp "$TEMP_LOG" "${dir}/stage-restore.log" 2>/dev/null || true
  temp_stack_remove
  upgrade_state_set "$file" '.stage = {result: $r, seconds: $s}' --arg r "$([ "$rc" -eq 0 ] && echo pass || echo fail)" \
    --argjson s "$(( $(date +%s) - start ))"
  if [ "$rc" -ne 0 ]; then
    log_fail "staging of ${id} on ${to} failed (logs: ${dir}); the client was not touched"
    return 1
  fi
  log_ok "staging of ${id} on ${to} passed ($(( $(date +%s) - start ))s); temporary stack removed"
}
