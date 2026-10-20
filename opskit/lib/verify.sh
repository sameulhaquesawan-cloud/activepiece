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
