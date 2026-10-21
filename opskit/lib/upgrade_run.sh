#!/usr/bin/env bash
# opskit upgrade: per-client lock on the host, run state on this machine, image pre-pull (task 6.3).
# Lock: <host root>/state/<id>/upgrade.lock/ (mkdir is atomic; holds the run id). The backup agent skips
# while it exists (unless older than 12 h), and the upgrade waits for a running backup before it starts.
# State: clients/<id>/upgrades/<run>/state.json, one entry per step, so a killed run names its next action.

# shellcheck disable=SC2016 # jq filters use $vars
UPGRADE_STEPS=(pull stage switch verify)
UPGRADE_LOCK_STALE_H=12
UPGRADE_BACKUP_WAIT_S="${OPSKIT_UPGRADE_BACKUP_WAIT_S:-900}"

upgrade_lock_dir() {
  printf '%s/state/%s/upgrade.lock' "$(host_root "$1")" "$2"
}

# upgrade_lock_take <host> <id> <run>: false if another run holds the lock
upgrade_lock_take() {
  host_run "$1" sh -c 'mkdir -p "$(dirname "$1")" && mkdir "$1" 2>/dev/null && printf "%s\n" "$2" > "$1/run"' \
    _ "$(upgrade_lock_dir "$1" "$2")" "$3"
}

upgrade_lock_owner() {
  host_run "$1" cat "$(upgrade_lock_dir "$1" "$2")/run" 2>/dev/null || true
}

# upgrade_lock_release <host> <id> <run>: only the run that holds the lock releases it
upgrade_lock_release() {
  [ "$(upgrade_lock_owner "$1" "$2")" = "$3" ] || return 0
  host_run "$1" rm -rf "$(upgrade_lock_dir "$1" "$2")"
}

# upgrade_wait_backup <host> <id>: waits for a running backup of the client to finish
upgrade_wait_backup() {
  host_run "$1" sh -c 'mkdir -p "$1" && exec 9>"$1/.lock" && flock -w "$2" 9' \
    _ "$(host_root "$1")/backups/$2" "$UPGRADE_BACKUP_WAIT_S"
}

upgrade_state_file() {
  printf '%s/upgrades/%s/state.json' "$(client_dir "$1")" "$2"
}

# upgrade_state_init <id> <run> <repo> <from> <to>
upgrade_state_init() {
  local file
  file="$(upgrade_state_file "$1" "$2")"
  mkdir -p "$(dirname "$file")"
  jq -n --arg client "$1" --arg run "$2" --arg repo "$3" --arg from "$4" --arg to "$5" --arg at "$(upgrade_now)" \
    '{client: $client, run: $run, repo: $repo, from: $from, to: $to, started: $at, status: "running", steps: {}}' > "$file"
}

# upgrade_state_set <file> <jq filter> [jq args...]: rewrites the state file in place
upgrade_state_set() {
  local file="$1" filter="$2" tmp
  shift 2
  tmp="$(mktemp "${file}.XXXXXX")"
  jq --arg at "$(upgrade_now)" "$@" "$filter" "$file" > "$tmp" && mv "$tmp" "$file"
}

upgrade_step_mark() {
  upgrade_state_set "$1" '.steps[$step] = ((.steps[$step] // {}) + {status: $status, at: $at})' \
    --arg step "$2" --arg status "$3"
}

# upgrade_next_action <id> <state file>: the safe way on for an unfinished run
upgrade_next_action() {
  if jq -e '.steps | has("switch")' "$2" >/dev/null; then
    printf 'the client may already run the new version: opskit upgrade %s --rollback' "$1"
  else
    printf 'nothing changed on the client yet: opskit upgrade %s --resume (or --unlock to give up)' "$1"
  fi
}

# upgrade_lock_check <id>: [ok] when no upgrade holds the lock; clears the lock of a finished run
upgrade_lock_check() {
  local id="$1" host run file status age
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  run="$(upgrade_lock_owner "$host" "$id")"
  if [ -z "$run" ]; then
    log_ok "no other upgrade of ${id} is running"
    return 0
  fi
  file="$(upgrade_state_file "$id" "$run")"
  status="$(jq -r '.status' "$file" 2>/dev/null || true)"
  case "$status" in
    running)
      log_fail "upgrade ${run} of ${id} to $(jq -r '.to' "$file") was interrupted at step $(upgrade_current_step "$file"): $(upgrade_next_action "$id" "$file")"
      return 1
      ;;
    "")
      age="$(upgrade_age_hours "$run" || printf '?')"
      log_fail "upgrade ${run} (${age} h ago, from another machine) holds the lock of ${id}$([ "$age" != "?" ] && [ "$age" -ge "$UPGRADE_LOCK_STALE_H" ] && printf ' and looks stale'): if no upgrade is running, opskit upgrade ${id} --unlock"
      return 1
      ;;
    *)
      upgrade_lock_release "$host" "$id" "$run"
      log_warn "removed the leftover lock of finished upgrade ${run} (${status})"
      ;;
  esac
}

upgrade_current_step() {
  local step
  for step in "${UPGRADE_STEPS[@]}"; do
    upgrade_step_done "$1" "$step" || { printf '%s' "$step"; return 0; }
  done
  printf 'finish'
}

upgrade_step_done() {
  jq -e --arg s "$2" '.steps[$s].status == "done"' "$1" >/dev/null
}

# upgrade_latest_running <id>: state file of the newest unfinished run, or nothing
upgrade_latest_running() {
  local file
  for file in "$(client_dir "$1")"/upgrades/*/state.json; do
    if [ -f "$file" ] && jq -e '.status == "running"' "$file" >/dev/null; then
      printf '%s\n' "$file"
    fi
  done | sort | tail -n 1
}

# upgrade_unlock <id>: gives up an unfinished run that never reached the switch
upgrade_unlock() {
  local id="$1" host run file
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  run="$(upgrade_lock_owner "$host" "$id")"
  [ -n "$run" ] || { log_ok "no upgrade lock on ${id}"; return 0; }
  file="$(upgrade_state_file "$id" "$run")"
  if [ -f "$file" ] && jq -e '.status == "running" and (.steps | has("switch"))' "$file" >/dev/null; then
    log_fail "upgrade ${run} reached the switch: opskit upgrade ${id} --rollback instead"
    return 1
  fi
  [ -f "$file" ] && upgrade_state_set "$file" '.status = (if .status == "running" then "abandoned" else .status end) | .ended = $at'
  upgrade_lock_release "$host" "$id" "$run"
  log_ok "upgrade lock of ${id} released (run ${run})"
}

# upgrade_image_digest <host|""> <repo> <tag>: registry digest of a pulled image (here, or on the host)
upgrade_image_digest() {
  local cmd=(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "${2}:${3}")
  if [ -n "$1" ]; then host_run "$1" "${cmd[@]}"; else "${cmd[@]}"; fi 2>/dev/null \
    | awk -v repo="$2" -F@ '$1 == repo { print $2; exit }'
}

# upgrade_do_pull <id> <state file>: target image on this machine (staging) and on the host, same digest
upgrade_do_pull() {
  local id="$1" file="$2" host repo to here there
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  repo="$(jq -r '.repo' "$file")"
  to="$(jq -r '.to' "$file")"
  docker pull -q "${repo}:${to}" >/dev/null || { log_fail "could not pull ${repo}:${to} here"; return 1; }
  host_run "$host" docker pull -q "${repo}:${to}" >/dev/null || { log_fail "could not pull ${repo}:${to} on ${host}"; return 1; }
  here="$(upgrade_image_digest "" "$repo" "$to")"
  there="$(upgrade_image_digest "$host" "$repo" "$to")"
  if [ -z "$here" ] || [ "$here" != "$there" ]; then
    log_fail "${repo}:${to} differs between here (${here:-?}) and ${host} (${there:-?}): pull again later"
    return 1
  fi
  upgrade_state_set "$file" '.digest = $digest' --arg digest "$here"
  log_ok "${repo}:${to} pulled here and on ${host} (${here})"
}

# upgrade_steps <id> <state file>: runs every step not yet done; on failure before the switch the lock goes
upgrade_steps() {
  local id="$1" file="$2" host step
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  for step in "${UPGRADE_STEPS[@]}"; do
    upgrade_step_done "$file" "$step" && continue
    upgrade_step_mark "$file" "$step" running
    if "upgrade_do_${step}" "$id" "$file"; then
      upgrade_step_mark "$file" "$step" "done"
      continue
    fi
    upgrade_step_mark "$file" "$step" failed
    if jq -e '.steps | has("switch")' "$file" >/dev/null; then
      log_fail "upgrade of ${id} failed at ${step}: $(upgrade_next_action "$id" "$file")"
      return 1
    fi
    upgrade_state_set "$file" '.status = "failed" | .ended = $at | .failed_step = $step' --arg step "$step"
    upgrade_lock_release "$host" "$id" "$(jq -r '.run' "$file")"
    log_fail "upgrade of ${id} stopped at ${step}; nothing changed on the client (log: $(dirname "$file"))"
    return 1
  done
  upgrade_state_set "$file" '.status = "done" | .ended = $at'
  upgrade_lock_release "$host" "$id" "$(jq -r '.run' "$file")"
  log_ok "${id} upgraded to $(jq -r '.to' "$file")"
}

# upgrade_start <id> <to>: gates, lock, wait for a running backup, state, steps
upgrade_start() {
  local id="$1" to="$2" cfile host run
  upgrade_plan "$id" "$to" || { log_fail "a gate failed: nothing was changed"; return 1; }
  upgrade_confirm "$id" "$to" || return 1
  cfile="$(client_file "$id")"
  host="$(yaml_get "$cfile" .host.name)"
  run="$(date -u +%Y%m%dT%H%M%SZ)"
  upgrade_lock_take "$host" "$id" "$run" || { log_fail "another upgrade of ${id} started just now"; return 1; }
  if ! upgrade_wait_backup "$host" "$id"; then
    upgrade_lock_release "$host" "$id" "$run"
    log_fail "a backup of ${id} is still running after ${UPGRADE_BACKUP_WAIT_S} s: try again later"
    return 1
  fi
  upgrade_state_init "$id" "$run" "$(yaml_get "$cfile" .image.repo ghcr.io/activepieces/activepieces)" \
    "$(yaml_get "$cfile" .image.tag)" "$to"
  log_info "Upgrade run ${run} (state: $(upgrade_state_file "$id" "$run"))"
  upgrade_steps "$id" "$(upgrade_state_file "$id" "$run")"
}

# upgrade_resume <id>: continues the newest unfinished run if it never reached the switch
upgrade_resume() {
  local id="$1" file host run
  file="$(upgrade_latest_running "$id")"
  [ -n "$file" ] || { log_fail "no unfinished upgrade of ${id} to resume"; return 1; }
  if jq -e '.steps | has("switch")' "$file" >/dev/null; then
    log_fail "upgrade $(jq -r '.run' "$file") reached the switch: opskit upgrade ${id} --rollback"
    return 1
  fi
  upgrade_confirm "$id" "$(jq -r '.to' "$file")" || return 1
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  run="$(jq -r '.run' "$file")"
  if [ "$(upgrade_lock_owner "$host" "$id")" != "$run" ] && ! upgrade_lock_take "$host" "$id" "$run"; then
    log_fail "another upgrade holds the lock of ${id}"
    return 1
  fi
  log_info "Resuming upgrade ${run} of ${id} to $(jq -r '.to' "$file") at step $(upgrade_current_step "$file")"
  upgrade_steps "$id" "$file"
}

upgrade_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}
