#!/usr/bin/env bash
# Restore a client backup into a fresh stack (new client id) or, with --overwrite --yes, over itself.

owner_age_identity() {
  printf '%s' "${OPSKIT_OWNER_AGE_KEY:-${HOME}/.config/opskit/owner.key}"
}

# restore_resolve <host> <id> <ts|latest>: prints the backup name present on the host
restore_resolve() {
  local host="$1" id="$2" from="$3" root name
  root="$(host_root "$host")"
  if [ "$from" = "latest" ]; then
    name="$(host_run "$host" cat "${root}/backups/${id}/latest" 2>/dev/null || true)"
  else
    name="$from"
  fi
  [[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { log_fail "no backup '${from}' for ${id} (see: opskit backups ${id})"; return 1; }
  if ! host_run "$host" test -s "${root}/backups/${id}/${name}/db.dump"; then
    restore_fetch_offsite "$host" "$id" "$name" || return 1
  fi
  printf '%s' "$name"
}

restore_fetch_offsite() {
  local host="$1" id="$2" name="$3" root remote
  root="$(host_root "$host")"
  remote="$(yaml_get "$(client_file "$id")" .backup.remote)"
  [ -n "$remote" ] || { log_fail "backup ${name} is not on ${host} and no off-server remote is configured"; return 1; }
  # shellcheck disable=SC2016
  host_run "$host" sh -c 'if [ -f "$1" ]; then rclone --config "$1" copy "$2" "$3"; else rclone copy "$2" "$3"; fi' _ \
    "${root}/agent/rclone.conf" "${remote%/}/${id}/${name}" "${root}/backups/${id}/${name}" \
    || { log_fail "could not fetch ${name} from ${remote}"; return 1; }
  log_ok "fetched ${name} from off-server ${remote}"
}

# restore_secrets <host> <id> <name> <target>: decrypt env.age locally → clients/<target>/secrets.env
restore_secrets() {
  local host="$1" id="$2" name="$3" target="$4" tmp identity spec key
  identity="$(owner_age_identity)"
  [ -s "$identity" ] || { log_fail "owner age private key not found: ${identity} (or set OPSKIT_OWNER_AGE_KEY)"; return 1; }
  tmp="$(mktemp -d)"
  chmod 700 "$tmp"
  host_get "$host" "$(host_root "$host")/backups/${id}/${name}/env.age" "${tmp}/env.age" || { rm -rf "$tmp"; return 1; }
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
  local source="$1" target="$2" domain="$3" name="$4" file
  file="$(client_file "$target")"
  yq ".client_id = \"${target}\" | .domain = \"${domain}\" | .status = \"draft\" | .history = [] | del(.offboarded_at) | del(.backup.heartbeat_url)" \
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
  dump="$(host_root "$host")/backups/${source}/${name}/db.dump"
  # shellcheck disable=SC2016
  host_run "$host" sh -c 'docker exec -i "$1" sh -c '"'"'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --exit-on-error'"'"' < "$2"' _ "$container" "$dump" \
    || { log_fail "pg_restore failed"; return 1; }
  log_ok "database restored from ${source}/${name}"
}

restore_report() {
  local host="$1" target="$2" container counts
  container="$(stack_compose "$host" "$target" ps -q postgres | head -n 1)"
  # shellcheck disable=SC2016
  counts="$(host_run "$host" docker exec "$container" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -c "select (select count(*) from flow), (select count(*) from app_connection), (select count(*) from flow_run)"')"
  IFS='|' read -r RESTORED_FLOWS RESTORED_CONNECTIONS RESTORED_RUNS <<< "$counts"
  log_ok "restored data: ${RESTORED_FLOWS} flows, ${RESTORED_CONNECTIONS} connections, ${RESTORED_RUNS} runs"
}

# restore_client <source id> <from> <target id> <domain> <overwrite> <yes>
restore_client() {
  local source="$1" from="$2" target="$3" domain="$4" overwrite="$5" yes="$6" host name
  require_client "$source" || return 1
  host="$(yaml_get "$(client_file "$source")" .host.name)"
  require_host "$host" || return 1
  name="$(restore_resolve "$host" "$source" "$from")" || return 1
  if [ "$target" = "$source" ]; then
    [ "$overwrite" = "true" ] || { log_fail "restoring over ${source} replaces its data; needs --overwrite --yes (or use --target <new id>)"; return 1; }
    confirm_destructive "$source" "$yes" "REPLACE all data of ${source} with backup ${name}" || return 1
    restore_secrets "$host" "$source" "$name" "$target" || return 1
    stack_compose "$host" "$source" down -v --remove-orphans >/dev/null 2>&1 || true
  else
    is_slug "$target" || { log_fail "invalid --target: ${target}"; return 1; }
    [ ! -e "$(client_file "$target")" ] || { log_fail "target client ${target} already exists; choose another --target"; return 1; }
    if [ -z "$domain" ]; then
      [ "$(yaml_get "$(host_file "$host")" .edge.tls acme)" = "internal" ] || { log_fail "--domain is required for a restore copy on ${host}"; return 1; }
      domain="${target}.localhost"
    fi
    is_domain "$domain" || { log_fail "invalid --domain: ${domain}"; return 1; }
    restore_secrets "$host" "$source" "$name" "$target" || return 1
    restore_new_client "$source" "$target" "$domain" "$name" || return 1
  fi
  stack_render "$target" >/dev/null || return 1
  deploy_push_files "$host" "$target" >/dev/null || return 1
  stack_compose "$host" "$target" up -d postgres redis >/dev/null 2>&1 || { log_fail "could not start postgres/redis for ${target}"; return 1; }
  wait_service_healthy "$host" "$target" postgres || return 1
  restore_database "$host" "$source" "$name" "$target" || return 1
  if [ "$target" = "$source" ]; then
    deploy_client "$target" || return 1
  else
    DEPLOY_SKIP_BACKUP=true deploy_client "$target" || return 1
  fi
  restore_report "$host" "$target"
  [ "$target" = "$source" ] && client_history_add "$target" restored "" "from ${name}"
  log_ok "restore of ${source}/${name} into ${target} complete"
}
