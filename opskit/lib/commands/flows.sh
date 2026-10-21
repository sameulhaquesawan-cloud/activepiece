#!/usr/bin/env bash
# summary: flow template library: list, validate, import a template into a client's builder

for lib in validate schema registry stack host flows flows_import; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

flows_usage() {
  cat <<'USAGE'
Usage: opskit flows list
       opskit flows validate [<template>]
       opskit flows import <template> <client id> [--set KEY=value]... [--email <admin email>]
                           [--again] [--print-steps] [--url <https://…>]
       opskit flows import <template> --url <builder address> [--set KEY=value]... [--email …]

list                 every template in opskit/flows with its description and the connections
                     the client creates in their own builder.
validate [<template>] check one template (or all): flow.json is valid Activepieces export JSON,
                     template.yaml matches opskit/schema/template.schema.json, every {{OPSKIT:KEY}}
                     placeholder is declared and every declared one is used, pinned pieces match
                     the manifest, no real-looking emails, URLs, ids or keys, README.md,
                     CHECKLIST.md and the test payloads are present. Rules: opskit/flows/CONVENTIONS.md
import               validate, fill the {{OPSKIT:KEY}} placeholders (--set, else the template's
                     default), sign in to the client's builder (admin password asked at the prompt,
                     used once, never stored), install our custom pieces, create the flow switched
                     off and print the connections the client creates and the next steps.
                     Already imported (same flow name) → nothing changes unless --again.
                     --print-steps: no sign-in; writes the filled flow to clients/<id>/flows/ and
                     prints click-by-click import steps for the builder.
                     --url: builder address when it is not https://<domain> (tests, tunnels);
                     without a client id it imports into any builder, e.g. a practice Codespace
                     (http://localhost:8080).
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

# flows_target <client id> <url override>: sets FLOWS_BASE_URL and FLOWS_CURL_ARGS
flows_target() {
  local id="$1" url="$2" host port domain tls
  if [ -n "$url" ]; then
    FLOWS_BASE_URL="${url%/}"
    return 0
  fi
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  domain="$(yaml_get "$(client_file "$id")" .domain)"
  port="$(yaml_get "$(host_file "$host")" .edge.https_port 443)"
  tls="$(yaml_get "$(host_file "$host")" .edge.tls acme)"
  FLOWS_BASE_URL="$(stack_frontend_url "$domain" "$port")"
  if [ "$tls" = "internal" ]; then
    [ "$(host_transport "$host")" = "local" ] || die "${host} uses a practice certificate over SSH; use --print-steps"
    # shellcheck disable=SC2034 # used by flows_api in lib/flows_import.sh
    FLOWS_CURL_ARGS=(--noproxy '*' --resolve "${domain}:${port}:127.0.0.1" --cacert "$(host_root "$host")/caddy/local-root.crt")
  fi
}

flows_import() {
  local template="" id="" email="" url="" again=0 print_steps=0 sets=() dir values filled count i
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --set) [ -n "${2:-}" ] || { flows_usage >&2; return 1; }; sets+=("$2"); shift 2 ;;
      --email) email="${2:-}"; shift 2 || { flows_usage >&2; return 1; } ;;
      --url) url="${2:-}"; shift 2 || { flows_usage >&2; return 1; } ;;
      --again) again=1; shift ;;
      --print-steps) print_steps=1; shift ;;
      -*) flows_usage >&2; return 1 ;;
      *) if [ -z "$template" ]; then template="$1"; elif [ -z "$id" ]; then id="$1"; else flows_usage >&2; return 1; fi; shift ;;
    esac
  done
  if [ -z "$template" ] || { [ -z "$id" ] && [ -z "$url" ]; } || { [ -z "$id" ] && [ "$print_steps" = "1" ]; }; then
    flows_usage >&2
    return 1
  fi
  dir="$(flows_template_dir "$template")"
  flows_validate_one "$template" || return 1
  if [ -n "$id" ]; then
    require_client "$id" || return 1
  fi
  flows_target "$id" "$url"
  values="$(flows_values "$dir" "${sets[@]}")" || return 1
  FLOWS_TMP="$(mktemp -d)"
  trap 'rm -rf "${FLOWS_TMP:-}"' EXIT
  filled="${FLOWS_TMP}/filled.json"
  flows_fill "$dir" "$values" > "$filled"
  ! grep -q 'OPSKIT:' "$filled" || die "placeholders left after filling (template bug)"
  if [ "$print_steps" = "1" ]; then
    mkdir -p "$(client_dir "$id")/flows"
    flows_print_steps "$dir" "$filled" "$(client_dir "$id")/flows/${template}.json"
    return 0
  fi
  if [ -z "$email" ]; then
    IFS= read -r -p "Admin email for ${FLOWS_BASE_URL}: " email || true
  fi
  [ -n "$email" ] || die "no admin email given (--email)"
  flows_sign_in "$email" || return 1
  flows_ensure_pieces "$dir" || return 1
  count="$(jq '.flows | length' "$filled")"
  for i in $(seq 0 $((count - 1))); do
    flows_import_one "$filled" "$i" "$again" || return 1
  done
  flows_next_steps "$dir"
}

cmd_main() {
  case "${1:-}" in
    -h|--help) flows_usage; return 0 ;;
    list) flows_list ;;
    validate) flows_validate "${2:-}" ;;
    import) shift; flows_import "$@" ;;
    *) flows_usage >&2; return 1 ;;
  esac
}
