#!/usr/bin/env bash
# opskit upgrade, rollback (task 6.7): on any failure after the client was touched, and by hand with
# --rollback. App + worker stop, the pre-switch dump (taken with the app stopped) replaces the database
# (path "restore"; decrypted on this machine), or, when the run failed before that dump, nothing in the
# database changed (path "restart"); then the old tag is deployed and checked, and the owner is alerted.
# Upstream's migration undo is not used (ASSUMPTIONS #24). Needs upgrade_switch.sh, restore.sh, smoke.sh.

# shellcheck disable=SC2016 # jq filters use $vars
UPGRADE_ROLLBACK_MAX_DAYS="${OPSKIT_UPGRADE_ROLLBACK_MAX_DAYS:-7}"

# upgrade_restore_dump <host> <id> <dump.age on the host>: drop + recreate the client's database, pg_restore
upgrade_restore_dump() {
  local host="$1" id="$2" dump="$3" pg plain codes
  pg="$(stack_service_container "$host" "$id" postgres)"
  [ -n "$pg" ] || { log_fail "postgres of ${id} is not running"; return 1; }
  plain="${dump%.age}.restore"
  host_run "$host" cat "$dump" | age -d -i "$(owner_age_identity)" | host_run "$host" sh -c 'umask 077 && cat > "$1"' _ "$plain"
  codes=("${PIPESTATUS[@]}")
  if [ "${codes[0]}" -ne 0 ] || [ "${codes[1]}" -ne 0 ] || [ "${codes[2]}" -ne 0 ]; then
    host_run "$host" rm -f "$plain"
    log_fail "pre-switch dump does not decrypt with $(owner_age_identity)"
    return 1
  fi
  host_run "$host" sh -c '
    set -e
    trap "rm -f \"$2\"" EXIT
    docker exec "$1" sh -c "dropdb -U \"\$POSTGRES_USER\" --force \"\$POSTGRES_DB\" && createdb -U \"\$POSTGRES_USER\" \"\$POSTGRES_DB\""
    docker exec -i "$1" sh -c "pg_restore -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" --no-owner --no-privileges --exit-on-error" < "$2"' \
    _ "$pg" "$plain" || { log_fail "restoring the pre-switch dump into ${id} failed"; return 1; }
  log_ok "database of ${id} replaced by the pre-switch dump"
}

# upgrade_owner_alert <host> <id> <what> <action>: critical, owner's channels only (host agent)
upgrade_owner_alert() {
  local host="$1" id="$2" root
  root="$(host_root "$host")"
  if host_run "$host" "${root}/agent/alert.sh" --root "$root" --client "$id" --severity critical --owner-only \
    --what "${3:0:300}" --action "${4:0:300}" >/dev/null 2>&1; then
    log_ok "owner alerted (critical)"
  else
    log_warn "owner alert not delivered (check ${root}/agent/alerts.conf on ${host})"
  fi
}

# upgrade_rollback <id> <state file> <why>: back to the previous tag; releases the lock when the client is healthy
upgrade_rollback() {
  local id="$1" file="$2" why="$3" host from to run dump path="restart" baseline since failed=0
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  from="$(jq -r '.from' "$file")"
  to="$(jq -r '.to' "$file")"
  run="$(jq -r '.run' "$file")"
  dump="$(jq -r '.pre_switch_dump // empty' "$file")"
  since="$(upgrade_now)"
  log_warn "rolling back ${id} to ${from} (${why})"
  upgrade_state_set "$file" '.rollback = {started: $at, why: $why}' --arg why "$why"
  stack_compose "$host" "$id" stop app worker >/dev/null 2>&1 || true
  if [ -n "$dump" ]; then
    path="restore"
    upgrade_restore_dump "$host" "$id" "$dump" || failed=1
  fi
  if [ "$failed" -eq 0 ]; then
    upgrade_set_version "$id" "$from"
    deploy_client "$id" || failed=1
  fi
  if [ "$failed" -eq 0 ]; then
    baseline="$(jq -c '.switch_baseline // .baseline // {flows: 0, connections: 0, runs: 0, enabled: 0}' "$file")"
    SMOKE_SCOPE=rollback smoke_production "$host" "$id" "$baseline" "$since" || failed=1
  fi
  upgrade_state_set "$file" '.rollback += {path: $p, result: $r, ended: $at} | .status = $s | .ended = $at' \
    --arg p "$path" --arg r "$([ "$failed" -eq 0 ] && echo pass || echo fail)" \
    --arg s "$([ "$failed" -eq 0 ] && echo rolled_back || echo rollback_failed)"
  if [ "$failed" -ne 0 ]; then
    upgrade_owner_alert "$host" "$id" "Upgrade of ${id} to ${to} failed (${why}) AND the rollback to ${from} failed: the client may be down" \
      "Run opskit upgrade ${id} --rollback; if it fails again restore the latest backup (docs/runbooks/backup-restore.md)"
    log_fail "rollback of ${id} failed: the client may be down. Next: opskit upgrade ${id} --rollback, else restore the latest backup"
    return 1
  fi
  upgrade_lock_release "$host" "$id" "$run"
  upgrade_owner_alert "$host" "$id" "Upgrade of ${id} to ${to} failed (${why}); rolled back to ${from} ($([ "$path" = restore ] && echo 'database restored to the moment before the switch' || echo 'database untouched'))" \
    "Read clients/${id}/upgrades/${run}/ and the release notes, then plan again"
  log_ok "${id} is back on ${from} (path: ${path}); logs: $(dirname "$file")"
}

# upgrade_rollback_manual <id>: the newest run that reached the switch (unfinished, or done within the retention)
upgrade_rollback_manual() {
  local id="$1" file="" candidate host run ended days
  for candidate in "$(client_dir "$id")"/upgrades/*/state.json; do
    [ -f "$candidate" ] || continue
    if jq -e '(.steps | has("switch")) and (.status == "running" or .status == "done" or .status == "rollback_failed")' "$candidate" >/dev/null; then
      file="$candidate"
    fi
  done
  [ -n "$file" ] || { log_fail "no upgrade of ${id} to roll back"; return 1; }
  run="$(jq -r '.run' "$file")"
  if jq -e '.status == "done"' "$file" >/dev/null; then
    ended="$(jq -r '.ended' "$file")"
    days="$(( ($(date +%s) - $(date -u -d "$ended" +%s)) / 86400 ))"
    if [ "$days" -gt "$UPGRADE_ROLLBACK_MAX_DAYS" ]; then
      log_fail "upgrade ${run} finished ${days} days ago (rollback only within ${UPGRADE_ROLLBACK_MAX_DAYS} days): restore a backup instead"
      return 1
    fi
  fi
  confirm_destructive "$id" "$UPGRADE_YES" "roll ${id} back to $(jq -r '.from' "$file"): everything since $(jq -r '.switched_at // .app_stopped_at // "the switch"' "$file") is lost" \
    || return 1
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  if [ "$(upgrade_lock_owner "$host" "$id")" != "$run" ] && ! upgrade_lock_take "$host" "$id" "$run"; then
    log_fail "another upgrade holds the lock of ${id}"
    return 1
  fi
  upgrade_rollback "$id" "$file" "rolled back by hand"
}

# upgrade_prune_dumps <host> <id>: pre-switch dumps older than the rollback window are removed
upgrade_prune_dumps() {
  host_run "$1" sh -c '[ ! -d "$1" ] || find "$1" -mindepth 1 -maxdepth 1 -type d -mtime "+$2" -exec rm -rf {} +' \
    _ "$(host_root "$1")/clients/$2/upgrades" "$UPGRADE_ROLLBACK_MAX_DAYS" || true
}
