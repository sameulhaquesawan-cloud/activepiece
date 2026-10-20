#!/usr/bin/env bash
# Client/host registry: paths, YAML getters, validated loading, history.
# OPSKIT_REGISTRY overrides the registry root (tests, alternate workspaces).

registry_root() {
  printf '%s' "${OPSKIT_REGISTRY:-${OPSKIT_ROOT}}"
}

client_dir() {
  printf '%s/clients/%s' "$(registry_root)" "$1"
}

client_file() {
  printf '%s/client.yaml' "$(client_dir "$1")"
}

host_file() {
  printf '%s/hosts/%s.yaml' "$(registry_root)" "$1"
}

# yaml_get <file> <yq path> [default]
yaml_get() {
  local value
  value="$(yq -r "${2} // \"\"" "$1")"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    printf '%s' "${3:-}"
  else
    printf '%s' "$value"
  fi
}

# yaml_set <file> <yq assignment expression>
yaml_set() {
  local tmp
  tmp="$(mktemp "${1}.XXXXXX")"
  yq "$2" "$1" > "$tmp" && mv "$tmp" "$1"
}

require_client() {
  local id="$1" file
  is_slug "$id" || { log_fail "invalid client id: ${id}"; return 1; }
  file="$(client_file "$id")"
  [ -f "$file" ] || { log_fail "unknown client: ${id} (no ${file})"; return 1; }
  validate_against_schema "${OPSKIT_ROOT}/schema/client.schema.json" "$file" >/dev/null 2>&1 \
    || { validate_against_schema "${OPSKIT_ROOT}/schema/client.schema.json" "$file"; return 1; }
}

require_host() {
  local name="$1" file
  is_slug "$name" || { log_fail "invalid host name: ${name}"; return 1; }
  file="$(host_file "$name")"
  [ -f "$file" ] || { log_fail "unknown host: ${name} (no ${file})"; return 1; }
  validate_against_schema "${OPSKIT_ROOT}/schema/host.schema.json" "$file" >/dev/null 2>&1 \
    || { validate_against_schema "${OPSKIT_ROOT}/schema/host.schema.json" "$file"; return 1; }
}

# client_history_add <id> <event> [tag] [note]
client_history_add() {
  local file entry
  file="$(client_file "$1")"
  entry="$(jq -nc --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg event "$2" --arg tag "${3:-}" --arg note "${4:-}" \
    '{at: $at, event: $event} + (if $tag != "" then {tag: $tag} else {} end) + (if $note != "" then {note: $note} else {} end)')"
  yaml_set "$file" ".history += [${entry}]"
}
