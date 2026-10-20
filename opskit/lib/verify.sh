#!/usr/bin/env bash
# Read-only data checks on a running stack: row counts and "every stored connection decrypts
# with this stack's AP_ENCRYPTION_KEY" (same AES-256-CBC scheme as the app; values never printed).

# shellcheck disable=SC2016
CONNECTION_DECRYPT_JS='
const crypto = require("crypto");
const key = Buffer.from(process.env.AP_ENCRYPTION_KEY || "", "binary");
let ok = 0, failed = 0;
for (const line of require("fs").readFileSync(0, "utf8").split("\n")) {
  const [iv, data] = line.trim().split(" ");
  if (!iv || !data) continue;
  try {
    const d = crypto.createDecipheriv("aes-256-cbc", key, Buffer.from(iv, "hex"));
    JSON.parse(d.update(data, "hex", "utf8") + d.final("utf8"));
    ok++;
  } catch (e) { failed++; }
}
console.log(ok + " " + failed);
'

stack_service_container() {
  stack_compose "$1" "$2" ps -q "$3" | head -n 1
}

# stack_psql <host> <id> <sql>: read-only query, unaligned output
stack_psql() {
  local host="$1" id="$2" sql="$3" container
  container="$(stack_service_container "$host" "$id" postgres)"
  [ -n "$container" ] || { log_fail "postgres of ${id} is not running"; return 1; }
  # shellcheck disable=SC2016
  host_run "$host" docker exec "$container" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -tA -F " " -c "$1"' _ "$sql"
}

# stack_data_counts <host> <id>: prints "<flows> <connections> <runs>"
stack_data_counts() {
  stack_psql "$1" "$2" 'select (select count(*) from flow), (select count(*) from app_connection), (select count(*) from flow_run)'
}

# stack_connections_decrypt <host> <id>: prints "<ok> <failed>"; fails if any connection does not decrypt
stack_connections_decrypt() {
  local host="$1" id="$2" pg app result
  pg="$(stack_service_container "$host" "$id" postgres)"
  app="$(stack_service_container "$host" "$id" app)"
  if [ -z "$pg" ] || [ -z "$app" ]; then
    log_fail "stack ${id} is not running"
    return 1
  fi
  # shellcheck disable=SC2016
  result="$(host_run "$host" sh -c 'docker exec "$1" sh -c "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tA -F \" \" -c \"select value->>'"'"'iv'"'"', value->>'"'"'data'"'"' from app_connection\"" | docker exec -i "$2" node -e "$3"' \
    _ "$pg" "$app" "$CONNECTION_DECRYPT_JS")" || { log_fail "connection decrypt check could not run on ${id}"; return 1; }
  printf '%s\n' "$result"
  [[ "$result" =~ ^[0-9]+\ 0$ ]]
}

# ro_psql <host> <postgres container> <sql>: as opskit_ro with read-only switched off (permissions must hold)
ro_psql() {
  # shellcheck disable=SC2016
  host_run "$1" docker exec "$2" sh -c 'psql -U opskit_ro -d "$POSTGRES_DB" -tA -c "set default_transaction_read_only = off" -c "$1" 2>&1' _ "$3" || true
}

# stack_readonly_check <host> <id>: opskit_ro reads runs, cannot write, create or log in over the network
stack_readonly_check() {
  local host="$1" id="$2" pg out problems=""
  pg="$(stack_service_container "$host" "$id" postgres)"
  [ -n "$pg" ] || { log_fail "postgres of ${id} is not running"; return 1; }
  [[ "$(ro_psql "$host" "$pg" 'select count(*) from flow_run')" =~ [0-9]+$ ]] || problems+="cannot read flow_run; "
  [[ "$(ro_psql "$host" "$pg" 'delete from flow_run')" == *"permission denied"* ]] || problems+="can delete runs; "
  [[ "$(ro_psql "$host" "$pg" 'create table opskit_probe (i int)')" == *"permission denied"* ]] || problems+="can create tables; "
  [[ "$(ro_psql "$host" "$pg" 'select count(*) from app_connection')" == *"permission denied"* ]] || problems+="can read connections; "
  # shellcheck disable=SC2016
  out="$(host_run "$host" docker exec "$pg" sh -c 'psql -h "$(hostname -i | cut -d" " -f1)" -U opskit_ro -d "$POSTGRES_DB" -w -tAc "select 1" 2>&1' || true)"
  [[ "$out" == *"password"* ]] || problems+="can log in over the network; "
  if [ -n "$problems" ]; then
    log_fail "read-only role of ${id}: ${problems%; }"
    return 1
  fi
  log_ok "read-only role of ${id}: reads runs, cannot write, create, read connections or log in over the network"
}
