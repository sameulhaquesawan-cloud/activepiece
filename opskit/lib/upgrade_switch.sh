#!/usr/bin/env bash
# opskit upgrade, production part (task 6.6): confirmation and quiet-hours gate, then the switch: stop app +
# worker, encrypted pre-switch dump on the host (<root>/clients/<id>/upgrades/<run>/pre-switch.dump.age),
# baseline, new tag in client.yaml, deploy; then the production smoke set against that baseline.
# Needs upgrade_run.sh, smoke.sh, deploy.sh (deploy_client), confirm.sh.

# shellcheck disable=SC2016 # jq filters use $vars
UPGRADE_YES="${UPGRADE_YES:-false}"
UPGRADE_NOW="${UPGRADE_NOW:-false}"

# upgrade_in_quiet_hours <id>: the client's local time is inside alerts.quiet_hours (may cross midnight)
upgrade_in_quiet_hours() {
  local cfile from to tz current
  cfile="$(client_file "$1")"
  from="$(upgrade_hhmm "$(yaml_get "$cfile" .alerts.quiet_hours.from)")" || return 1
  to="$(upgrade_hhmm "$(yaml_get "$cfile" .alerts.quiet_hours.to)")" || return 1
  [ "$from" != "$to" ] || return 1
  tz="$(yaml_get "$cfile" .timezone UTC)"
  current="$(upgrade_hhmm "$(TZ="$tz" date -d "@${OPSKIT_UPGRADE_CLOCK:-$(date +%s)}" +%H:%M)")"
  if [ "$from" -lt "$to" ]; then
    [ "$current" -ge "$from" ] && [ "$current" -lt "$to" ]
  else
    [ "$current" -ge "$from" ] || [ "$current" -lt "$to" ]
  fi
}

upgrade_hhmm() {
  [[ "$1" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]] || return 1
  printf '%s' $(( 10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]} ))
}

# upgrade_confirm <id> <to>: quiet hours (or --now), then --yes and the typed client id
upgrade_confirm() {
  local id="$1" to="$2" cfile quiet
  cfile="$(client_file "$id")"
  if [ "$UPGRADE_NOW" != "true" ] && ! upgrade_in_quiet_hours "$id"; then
    quiet="$(yaml_get "$cfile" .alerts.quiet_hours.from)"
    if [ -n "$quiet" ]; then
      log_fail "outside ${id}'s quiet hours (${quiet}–$(yaml_get "$cfile" .alerts.quiet_hours.to) $(yaml_get "$cfile" .timezone UTC)): run then, or add --now"
    else
      log_fail "${id} has no quiet hours (alerts.quiet_hours): agree a time with the client and add --now"
    fi
    return 1
  fi
  confirm_destructive "$id" "$UPGRADE_YES" "upgrade ${id} to ${to} (the app is down for 1–3 minutes)"
}

upgrade_host_dir() {
  printf '%s/clients/%s/upgrades/%s' "$(host_root "$1")" "$2" "$3"
}

# upgrade_pre_switch_dump <host> <id> <run>: pg_dump (app stopped), integrity-checked, encrypted to the owner key.
# OPSKIT_UPGRADE_FAIL=pre-switch-dump makes it fail on purpose (tests of the rollback "restart" path).
upgrade_pre_switch_dump() {
  local host="$1" id="$2" run="$3" pg dir
  if [ "${OPSKIT_UPGRADE_FAIL:-}" = "pre-switch-dump" ]; then
    log_fail "pre-switch dump: injected failure (OPSKIT_UPGRADE_FAIL)"
    return 1
  fi
  pg="$(stack_service_container "$host" "$id" postgres)"
  [ -n "$pg" ] || { log_fail "postgres of ${id} is not running"; return 1; }
  dir="$(upgrade_host_dir "$host" "$id" "$run")"
  host_run "$host" sh -c '
    set -e
    umask 077
    mkdir -p "$2"
    docker exec "$1" sh -c "pg_dump -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" --no-owner -Fc" > "$2/pre-switch.dump"
    trap "rm -f \"$2/pre-switch.dump\"" EXIT
    [ -s "$2/pre-switch.dump" ]
    docker exec -i "$1" pg_restore --list < "$2/pre-switch.dump" > /dev/null
    age -R "$3" -o "$2/pre-switch.dump.age" "$2/pre-switch.dump"
    [ -s "$2/pre-switch.dump.age" ]' _ "$pg" "$dir" "$(host_root "$host")/agent/owner.age.pub" \
    || { log_fail "pre-switch dump of ${id} failed"; return 1; }
  log_ok "pre-switch dump of ${id} taken with the app stopped (encrypted, ${dir}/pre-switch.dump.age)"
}

upgrade_set_version() {
  yaml_set "$(client_file "$1")" ".image.tag = \"$2\" | .ap_version = \"$2\""
}

# upgrade_do_switch <id> <state file>
upgrade_do_switch() {
  local id="$1" file="$2" host run to baseline
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  run="$(jq -r '.run' "$file")"
  to="$(jq -r '.to' "$file")"
  stack_compose "$host" "$id" stop app worker >/dev/null 2>&1 || { log_fail "could not stop app and worker of ${id}"; return 1; }
  upgrade_state_set "$file" '.app_stopped_at = $at'
  log_ok "app and worker of ${id} stopped (downtime starts)"
  upgrade_pre_switch_dump "$host" "$id" "$run" || return 1
  upgrade_state_set "$file" '.pre_switch_dump = $d' --arg d "$(upgrade_host_dir "$host" "$id" "$run")/pre-switch.dump.age"
  baseline="$(smoke_baseline "$host" "$id")" || { log_fail "could not read ${id}'s counts"; return 1; }
  upgrade_state_set "$file" '.switch_baseline = $b' --argjson b "$baseline"
  upgrade_set_version "$id" "$to"
  upgrade_state_set "$file" '.switched_at = $at'
  deploy_client "$id" || { log_fail "deploy of ${id} on ${to} failed"; return 1; }
  log_ok "${id} runs ${to} (downtime ends)"
}

# upgrade_do_verify <id> <state file>: production smoke against the baseline taken with the app stopped
upgrade_do_verify() {
  local id="$1" file="$2" host
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  SMOKE_SCOPE=production smoke_production "$host" "$id" "$(jq -c '.switch_baseline' "$file")" "$(jq -r '.switched_at' "$file")"
}
