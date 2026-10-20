#!/usr/bin/env bash
# summary: check a client.yaml or hosts/<host>.yaml against its schema

# shellcheck source=../schema.sh
source "${OPSKIT_ROOT}/lib/schema.sh"

validate_usage() {
  cat <<'EOF'
Usage: opskit validate <file> [--type client|host]

Checks the file against opskit/schema/<type>.schema.json and prints one
"[fail] field: problem" line per error. The type is detected from the
top-level client_id / host_id key unless --type is given.
EOF
}

detect_type() {
  local file="$1"
  if [ "$(yq '.client_id != null' "$file" 2>/dev/null)" = "true" ]; then
    printf 'client'
  elif [ "$(yq '.host_id != null' "$file" 2>/dev/null)" = "true" ]; then
    printf 'host'
  fi
}

cmd_main() {
  local file="" type=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) validate_usage; return 0 ;;
      --type) type="${2:-}"; shift 2 || { validate_usage >&2; return 1; } ;;
      -*) validate_usage >&2; return 1 ;;
      *) file="$1"; shift ;;
    esac
  done
  [ -n "$file" ] || { validate_usage >&2; return 1; }
  [ -f "$file" ] || die "file not found: ${file}"
  [ -n "$type" ] || type="$(detect_type "$file")"
  case "$type" in
    client|host) ;;
    "") die "$(basename "$file"): cannot tell client from host (no client_id/host_id); use --type" ;;
    *) die "unknown --type: ${type} (client or host)" ;;
  esac
  validate_against_schema "${OPSKIT_ROOT}/schema/${type}.schema.json" "$file"
}
