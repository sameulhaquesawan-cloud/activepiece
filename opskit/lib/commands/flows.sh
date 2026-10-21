#!/usr/bin/env bash
# summary: flow template library: list templates, validate them

for lib in schema flows; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

flows_usage() {
  cat <<'USAGE'
Usage: opskit flows list
       opskit flows validate [<template>]

list                 every template in opskit/flows with its description and the connections
                     the client creates in their own builder.
validate [<template>] check one template (or all): flow.json is valid Activepieces export JSON,
                     template.yaml matches opskit/schema/template.schema.json, every {{OPSKIT:KEY}}
                     placeholder is declared and every declared one is used, pinned pieces match
                     the manifest, no real-looking emails, URLs, ids or keys, README.md,
                     CHECKLIST.md and the test payloads are present. Rules: opskit/flows/CONVENTIONS.md
USAGE
}

flows_validate() {
  local id failed=0 ids
  if [ -n "${1:-}" ]; then
    ids="$1"
  else
    ids="$(flows_ids)"
    [ -n "$ids" ] || die "no templates found in $(flows_dir)"
  fi
  while IFS= read -r id; do
    flows_validate_one "$id" || failed=1
  done <<< "$ids"
  return "$failed"
}

cmd_main() {
  case "${1:-}" in
    -h|--help) flows_usage; return 0 ;;
    list) flows_list ;;
    validate) flows_validate "${2:-}" ;;
    *) flows_usage >&2; return 1 ;;
  esac
}
