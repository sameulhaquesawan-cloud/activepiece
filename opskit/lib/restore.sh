#!/usr/bin/env bash
# Restore a client backup into a fresh stack (new client id, same or another host) or, with
# --overwrite --yes, over the client itself. The owner's age private key stays on this machine.

owner_age_identity() {
  printf '%s' "${OPSKIT_OWNER_AGE_KEY:-${HOME}/.config/opskit/owner.key}"
}

backup_dir_on() {
  printf '%s/backups/%s/%s' "$(host_root "$1")" "$2" "$3"
}

# restore_locate <source host> <target host> <id> <name|latest>
# sets RESTORE_NAME and RESTORE_FROM_HOST (the host that holds db.dump + env.age)
restore_locate() {
  local src="$1" dst="$2" id="$3" from="$4" name=""
  RESTORE_NAME=""
  RESTORE_FROM_HOST=""
  if [ "$from" = "latest" ]; then
    name="$(host_run "$src" cat "$(host_root "$src")/backups/${id}/latest" 2>/dev/null || true)"
    [ -n "$name" ] || name="$(restore_remote_latest "$dst" "$id")"
  else
    name="$from"
  fi
  [[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { log_fail "no backup '${from}' for ${id} (see: opskit backups ${id})"; return 1; }
  if host_run "$src" test -s "$(backup_dir_on "$src" "$id" "$name")/db.dump" 2>/dev/null; then
    RESTORE_FROM_HOST="$src"
  elif [ "$dst" != "$src" ] && host_run "$dst" test -s "$(backup_dir_on "$dst" "$id" "$name")/db.dump" 2>/dev/null; then
    RESTORE_FROM_HOST="$dst"
  else
    restore_fetch_offsite "$dst" "$id" "$name" || return 1
    RESTORE_FROM_HOST="$dst"
  fi
  RESTORE_NAME="$name"
}

# a new target host needs the owner's rclone config to fetch from the off-server remote
restore_prepare_host() {
  local src="$1" dst="$2" conf
  conf="$(registry_root)/owner/rclone.conf"
  [ "$dst" != "$src" ] && [ -f "$conf" ] || return 0
  host_put "$dst" "$conf" "$(host_root "$dst")/agent/rclone.conf" 600
}

restore_rclone() {
  local host="$1"
  shift
  # shellcheck disable=SC2016
  host_run "$host" sh -c 'conf="$1"; shift; if [ -f "$conf" ]; then rclone --config "$conf" "$@"; else rclone "$@"; fi' _ \
    "$(host_root "$host")/agent/rclone.conf" "$@"
}

restore_remote_latest() {
  local host="$1" id="$2" remote
  remote="$(yaml_get "$(client_file "$id")" .backup.remote)"
  [ -n "$remote" ] || return 0
  restore_rclone "$host" lsf --dirs-only "${remote%/}/${id}/" 2>/dev/null | tr -d '/' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort | tail -n 1 || true
}

restore_fetch_offsite() {
  local host="$1" id="$2" name="$3" remote
  remote="$(yaml_get "$(client_file "$id")" .backup.remote)"
  [ -n "$remote" ] || { log_fail "backup ${name} is not on a reachable host and no off-server remote is configured"; return 1; }
  restore_rclone "$host" copy "${remote%/}/${id}/${name}" "$(backup_dir_on "$host" "$id" "$name")" \
    || { log_fail "could not fetch ${name} from ${remote}"; return 1; }
  log_ok "fetched ${name} from off-server ${remote} to ${host}"
}

# restore_copy_dump <from host> <to host> <id> <name>: via this machine when the hosts differ
restore_copy_dump() {
  local from="$1" to="$2" id="$3" name="$4" tmp
  [ "$from" != "$to" ] || return 0
  tmp="$(mktemp -d)"
  chmod 700 "$tmp"
  if host_get "$from" "$(backup_dir_on "$from" "$id" "$name")/db.dump" "${tmp}/db.dump" \
    && host_put "$to" "${tmp}/db.dump" "$(backup_dir_on "$to" "$id" "$name")/db.dump" 600; then
    rm -rf "$tmp"
    log_ok "copied backup ${name} from ${from} to ${to}"
    return 0
  fi
  rm -rf "$tmp"
  log_fail "could not copy backup ${name} from ${from} to ${to}"
  return 1
}

# restore_secrets <host> <id> <name> <target>: decrypt env.age locally → clients/<target>/secrets.env
restore_secrets() {
  local host="$1" id="$2" name="$3" target="$4" tmp identity spec key
  identity="$(owner_age_identity)"
  [ -s "$identity" ] || { log_fail "owner age private key not found: ${identity} (or set OPSKIT_OWNER_AGE_KEY)"; return 1; }
  tmp="$(mktemp -d)"
  chmod 700 "$tmp"
  host_get "$host" "$(backup_dir_on "$host" "$id" "$name")/env.age" "${tmp}/env.age" || { rm -rf "$tmp"; return 1; }
  if ! (umask 077 && age -d -i "$identity" -o "${tmp}/env" "${tmp}/env.age"); then
    rm -rf "$tmp"
    log_fail "env.age does not decrypt with ${identity} (wrong owner key?)"
    return 1
  fi
  : > "${tmp}/secrets.env"
  for spec in "${SECRET_SPECS[@]}"; do
    key="${spec%%:*}"
    printf '%s=%s\n' "$key" "$(sed -n "s/^${key}=//p" "${tmp}/env" | head -n 1)" >> "${tmp}/secrets.env"
  done
  if ! secrets_check "${tmp}/secrets.env" >/dev/null 2>&1; then
    rm -rf "$tmp"
    log_fail "decrypted .env of ${id}/${name} lacks valid AP_* secrets; nothing restored"
    return 1
  fi
  mkdir -p "$(client_dir "$target")"
  chmod 700 "$(client_dir "$target")"
  install -m 600 "${tmp}/secrets.env" "$(secrets_file "$target")"
  rm -rf "$tmp"
  log_ok "secrets restored from escrow (encryption key preserved)"
}

restore_new_client() {
  local source="$1" target="$2" domain="$3" name="$4" host="$5" file
  file="$(client_file "$target")"
  yq ".client_id = \"${target}\" | .domain = \"${domain}\" | .host.name = \"${host}\" | .status = \"draft\" | .offboard_retention_days = 1 | .history = [] | del(.offboarded_at) | del(.backup.heartbeat_url)" \
    "$(client_file "$source")" > "$file"
  client_history_add "$target" restored "" "from ${source}/${name}"
  require_client "$target" || return 1
}

wait_service_healthy() {
  local host="$1" id="$2" service="$3" container state="" waited=0
  container="$(stack_compose "$host" "$id" ps -q "$service" | head -n 1)"
  [ -n "$container" ] || { log_fail "${service} container not found"; return 1; }
  while [ "$waited" -lt 180 ]; do
    state="$(host_run "$host" docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || true)"
    [ "$state" = "healthy" ] && return 0
    sleep 3
    waited=$((waited + 3))
  done
  log_fail "${service} not healthy (${state:-unknown})"
  return 1
}

restore_database() {
  local host="$1" source="$2" name="$3" target="$4" container dump
  container="$(stack_compose "$host" "$target" ps -q postgres | head -n 1)"
  dump="$(backup_dir_on "$host" "$source" "$name")/db.dump"
  # shellcheck disable=SC2016
  host_run "$host" sh -c 'docker exec -i "$1" sh -c '"'"'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --exit-on-error'"'"' < "$2"' _ "$container" "$dump" \
    || { log_fail "pg_restore failed"; return 1; }
  log_ok "database restored from ${source}/${name}"
}

restore_report() {
  local host="$1" target="$2" counts decrypt
  counts="$(stack_data_counts "$host" "$target")" || return 1
  read -r RESTORED_FLOWS RESTORED_CONNECTIONS RESTORED_RUNS <<< "$counts"
  log_ok "restored data: ${RESTORED_FLOWS} flows, ${RESTORED_CONNECTIONS} connections, ${RESTORED_RUNS} runs"
  decrypt="$(stack_connections_decrypt "$host" "$target")" \
    || { log_fail "stored connections do not decrypt in ${target} (ok/failed: ${decrypt:-?}): wrong AP_ENCRYPTION_KEY"; return 1; }
  log_ok "all ${decrypt%% *} stored connections decrypt with the restored key"
}

# restore_client <source id> <from> <target id> <domain> <target host|""> <overwrite> <yes>
restore_client() {
  local source="$1" from="$2" target="$3" domain="$4" dst="$5" overwrite="$6" yes="$7" src name
  require_client "$source" || return 1
  src="$(yaml_get "$(client_file "$source")" .host.name)"
  dst="${dst:-$src}"
  require_host "$dst" || return 1
  restore_prepare_host "$src" "$dst" || return 1
  restore_locate "$src" "$dst" "$source" "$from" || return 1
  name="$RESTORE_NAME"
  if [ "$target" = "$source" ]; then
    [ "$overwrite" = "true" ] || { log_fail "restoring over ${source} replaces its data; needs --overwrite --yes (or use --target <new id>)"; return 1; }
    confirm_destructive "$source" "$yes" "REPLACE all data of ${source} on ${dst} with backup ${name}" || return 1
    restore_secrets "$RESTORE_FROM_HOST" "$source" "$name" "$target" || return 1
    if [ "$dst" != "$src" ]; then
      yaml_set "$(client_file "$source")" ".host.name = \"${dst}\""
      log_warn "${source} now lives on ${dst}; its stack on ${src} was not touched (stop it there if it still runs)"
    fi
    stack_compose "$dst" "$source" down -v --remove-orphans >/dev/null 2>&1 || true
  else
    is_slug "$target" || { log_fail "invalid --target: ${target}"; return 1; }
    [ ! -e "$(client_file "$target")" ] || { log_fail "target client ${target} already exists; choose another --target"; return 1; }
    if [ -z "$domain" ]; then
      [ "$(yaml_get "$(host_file "$dst")" .edge.tls acme)" = "internal" ] || { log_fail "--domain is required for a restore copy on ${dst}"; return 1; }
      domain="${target}.localhost"
    fi
    is_domain "$domain" || { log_fail "invalid --domain: ${domain}"; return 1; }
    restore_secrets "$RESTORE_FROM_HOST" "$source" "$name" "$target" || return 1
    restore_new_client "$source" "$target" "$domain" "$name" "$dst" || return 1
  fi
  restore_copy_dump "$RESTORE_FROM_HOST" "$dst" "$source" "$name" || return 1
  stack_render "$target" >/dev/null || return 1
  deploy_push_files "$dst" "$target" >/dev/null || return 1
  stack_compose "$dst" "$target" up -d postgres redis >/dev/null 2>&1 || { log_fail "could not start postgres/redis for ${target}"; return 1; }
  wait_service_healthy "$dst" "$target" postgres || return 1
  restore_database "$dst" "$source" "$name" "$target" || return 1
  if [ "$target" = "$source" ]; then
    deploy_client "$target" || return 1
  else
    DEPLOY_SKIP_BACKUP=true deploy_client "$target" || return 1
  fi
  restore_report "$dst" "$target" || return 1
  [ "$target" = "$source" ] && client_history_add "$target" restored "" "from ${name}"
  log_ok "restore of ${source}/${name} into ${target} on ${dst} complete"
}
