#!/usr/bin/env bash
# summary: check a client.yaml, hosts/<host>.yaml, template.yaml, owner/business.yaml or notes.yaml against its schema

# shellcheck source=../schema.sh
source "${OPSKIT_ROOT}/lib/schema.sh"

validate_usage() {
  cat <<'EOF'
Usage: opskit validate <file> [--type client|host|template|business|notes]

Checks the file against opskit/schema/<type>.schema.json and prints one
"[fail] field: problem" line per error. The type is detected from the
top-level client_id / host_id / template_id / business_name / notes_for key unless --type is given.
EOF
}

detect_type() {
  local file="$1"
  if [ "$(yq '.client_id != null' "$file" 2>/dev/null)" = "true" ]; then
    printf 'client'
  elif [ "$(yq '.host_id != null' "$file" 2>/dev/null)" = "true" ]; then
    printf 'host'
  elif [ "$(yq '.template_id != null' "$file" 2>/dev/null)" = "true" ]; then
    printf 'template'
  elif [ "$(yq '.business_name != null' "$file" 2>/dev/null)" = "true" ]; then
    printf 'business'
  elif [ "$(yq '.notes_for != null' "$file" 2>/dev/null)" = "true" ]; then
    printf 'notes'
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
    client|host|template|business|notes) ;;
    "") die "$(basename "$file"): cannot tell the file type (no client_id/host_id/template_id/business_name/notes_for); use --type" ;;
    *) die "unknown --type: ${type} (client, host, template, business or notes)" ;;
  esac
  validate_against_schema "${OPSKIT_ROOT}/schema/${type}.schema.json" "$file"
}
