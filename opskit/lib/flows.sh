#!/usr/bin/env bash
# Flow template library: locate, list and validate templates in opskit/flows (or OPSKIT_FLOWS_DIR).

FLOWS_REQUIRED_FILES=(flow.json template.yaml README.md CHECKLIST.md)
FLOWS_EXAMPLE_DOMAINS='example\.(com|org|net)'
FLOWS_SECRET_PATTERNS=(
  'sk-[A-Za-z0-9_-]{20,}'
  'xox[abposr]-[A-Za-z0-9-]{10,}'
  'AKIA[0-9A-Z]{16}'
  'gh[pousr]_[A-Za-z0-9]{30,}'
  'pat-(na|eu)[0-9]-[A-Za-z0-9-]{20,}'
  'AIza[0-9A-Za-z_-]{35}'
  'EAA[A-Za-z0-9]{40,}'
  '[0-9]{8,10}:AA[A-Za-z0-9_-]{30,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'hooks\.slack\.com/services/'
  'docs\.google\.com/spreadsheets/d/'
)

flows_dir() {
  printf '%s' "${OPSKIT_FLOWS_DIR:-${OPSKIT_ROOT}/flows}"
}

# flows_ids: template ids (folders with a template.yaml), sorted
flows_ids() {
  local dir manifest
  dir="$(flows_dir)"
  for manifest in "${dir}"/*/template.yaml; do
    [ -f "$manifest" ] || continue
    basename "$(dirname "$manifest")"
  done
}

flows_template_dir() {
  local id="$1" dir
  dir="$(flows_dir)/${id}"
  [ -f "${dir}/template.yaml" ] || die "unknown template: ${id} (see: opskit flows list)"
  printf '%s' "$dir"
}

flows_list() {
  local id dir name connections
  printf '%-18s %-40s %s\n' "TEMPLATE" "NAME" "CONNECTIONS THE CLIENT CREATES"
  while IFS= read -r id; do
    dir="$(flows_dir)/${id}"
    name="$(yq -r '.name // ""' "${dir}/template.yaml")"
    connections="$(yq -r '[.connections[]?.piece | sub("^@[a-z]+/piece-"; "")] | join(", ")' "${dir}/template.yaml")"
    printf '%-18s %-40s %s\n' "$id" "$name" "${connections:-none}"
    printf '%-18s %s\n' "" "$(yq -r '.description // ""' "${dir}/template.yaml")"
  done < <(flows_ids)
}

# flows_problems <template dir>: one problem per line on stdout (empty = valid); schema checked separately
flows_problems() {
  local dir="$1" id file
  id="$(basename "$dir")"
  for file in "${FLOWS_REQUIRED_FILES[@]}"; do
    [ -f "${dir}/${file}" ] || printf 'missing file: %s\n' "$file"
  done
  [ -f "${dir}/flow.json" ] && [ -f "${dir}/template.yaml" ] || return 0
  if ! jq -e . "${dir}/flow.json" >/dev/null 2>&1; then
    printf 'flow.json: not valid JSON\n'
    return 0
  fi
  flows_format_problems "${dir}/flow.json"
  [ "$(yq -r '.template_id // ""' "${dir}/template.yaml")" = "$id" ] \
    || printf 'template.yaml: template_id must be the folder name (%s)\n' "$id"
  flows_placeholder_problems "$dir"
  flows_reference_problems "${dir}/flow.json"
  flows_piece_problems "$dir"
  flows_custom_piece_problems "$dir"
  flows_connection_step_problems "$dir"
  flows_failure_problems "$dir"
  flows_leak_problems "$dir"
  flows_test_problems "$dir"
}

flows_format_problems() {
  jq -r '
    if (.name | type) != "string" or (.name | length) == 0 then "flow.json: needs a name (Activepieces export format)" else empty end,
    if (.flows | type) != "array" or (.flows | length) == 0 then "flow.json: needs a non-empty flows list (Activepieces export format)"
    else (.flows | to_entries[] | .key as $i | .value |
      (if (.displayName | type) != "string" then "flow.json: flows[\($i)] has no displayName" else empty end),
      (if (.trigger | type) != "object" or .trigger.name != "trigger" then "flow.json: flows[\($i)] has no trigger step" else empty end),
      ([.. | objects | select(has("type") and has("name") and has("settings")) | select(has("lastUpdatedDate") | not) | .name] |
        if length > 0 then "flow.json: steps without lastUpdatedDate: \(join(", "))" else empty end))
    end' "$1"
}

# flows_reference_problems <flow.json>: step references must use the flow schema 22+ form step_1['output']
flows_reference_problems() {
  jq -r '[.. | objects | del(.code) | .[] | strings | scan("\\{\\{(.*?)\\}\\}"; "s") | .[0]
      | select(startswith("OPSKIT:") | not)
      | select(test("\\b(trigger|step_[0-9]+)\\b(?!\\[.(output|error).\\])"))] | unique | .[:3] |
    if length > 0 then "flow.json: write step references as {{step_1[\u0027output\u0027]…}} (flow schema 27): \(map("{{" + . + "}}") | join(" "))" else empty end' "$1"
}

flows_placeholder_problems() {
  local dir="$1" used declared key
  used="$(grep -oE '\{\{OPSKIT:[A-Z][A-Z0-9_]*\}\}' "${dir}/flow.json" | sed -E 's/^\{\{OPSKIT:(.*)\}\}$/\1/' | sort -u || true)"
  declared="$(yq -r '.placeholders[]?.key' "${dir}/template.yaml" | sort -u)"
  if [ "$(grep -oE 'OPSKIT:' "${dir}/flow.json" | wc -l)" -ne "$(grep -oE '\{\{OPSKIT:[A-Z][A-Z0-9_]*\}\}' "${dir}/flow.json" | wc -l)" ]; then
    printf 'flow.json: malformed placeholder (write {{OPSKIT:KEY}}, KEY in capitals)\n'
  fi
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    grep -qxF "$key" <<< "$declared" || printf 'placeholder %s is used in flow.json but not declared in template.yaml\n' "$key"
  done <<< "$used"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    grep -qxF "$key" <<< "$used" || printf 'placeholder %s is declared in template.yaml but not used in flow.json\n' "$key"
  done <<< "$declared"
}

flows_piece_problems() {
  local dir="$1" in_flow in_manifest piece
  in_flow="$(jq -r '[.. | objects | select(has("pieceName")) | "\(.pieceName)@\(.pieceVersion)"] | unique | .[]' "${dir}/flow.json")"
  in_manifest="$(yq -r '.pieces[]? | .name + "@" + .version' "${dir}/template.yaml" | sort -u)"
  while IFS= read -r piece; do
    [ -n "$piece" ] || continue
    grep -qxF "$piece" <<< "$in_manifest" || printf 'piece %s is in flow.json but not in template.yaml pieces\n' "$piece"
  done <<< "$in_flow"
  while IFS= read -r piece; do
    [ -n "$piece" ] || continue
    grep -qxF "$piece" <<< "$in_flow" || printf 'piece %s is in template.yaml pieces but not used in flow.json\n' "$piece"
  done <<< "$in_manifest"
}

# flows_custom_piece_problems <template dir>: our pieces need their archive committed in <custom>/release/
flows_custom_piece_problems() {
  local dir="$1" name version custom release file manifest
  while IFS=$'\t' read -r name version custom; do
    [ -n "$custom" ] || continue
    release="${OPSKIT_REPO_ROOT:-$(cd "${OPSKIT_ROOT}/.." && pwd)}/${custom}/release"
    file="$(sed -E 's#^@##; s#/#-#' <<< "$name")-${version}.tgz"
    if [ ! -f "${release}/${file}" ]; then
      printf 'custom piece archive missing: %s/release/%s (build it, copy it there, update SHA256SUMS)\n' "$custom" "$file"
      continue
    fi
    manifest="$(tar -xzOf "${release}/${file}" package/package.json 2>/dev/null | jq -r '.name + "@" + .version' 2>/dev/null || true)"
    [ "$manifest" = "${name}@${version}" ] || printf 'custom piece archive %s contains %s, expected %s@%s\n' "$file" "${manifest:-nothing readable}" "$name" "$version"
    (cd "$release" && grep -F " ${file}" SHA256SUMS 2>/dev/null | sha256sum -c --status 2>/dev/null) \
      || printf 'custom piece archive %s does not match %s/release/SHA256SUMS\n' "$file" "$custom"
  done < <(yq -r '.pieces[] | [.name, .version, .custom // ""] | @tsv' "${dir}/template.yaml")
}

# flows_connection_step_problems <template dir>: steps that need the client's account start incomplete
flows_connection_step_problems() {
  local dir="$1"
  jq -r --argjson pieces "$(yq -o=json -I=0 '[.connections[]?.piece]' "${dir}/template.yaml")" '
    [.. | objects | select(has("settings") and .valid == true and (.settings.pieceName as $p | $pieces | index($p))) | .name]
    | if length > 0 then "steps that need the client'"'"'s connection must be \"valid\": false: \(join(", "))" else empty end' "${dir}/flow.json"
}

flows_failure_problems() {
  local dir="$1" mode
  mode="$(yq -r '.failure // ""' "${dir}/template.yaml")"
  [ "$mode" = "fail-run" ] || return 0
  jq -r '[.. | objects | select(.settings?.errorHandlingOptions?.continueOnFailure?.value? == true) | .name] | unique |
    if length > 0 then "failure is fail-run but these steps continue on failure: \(join(", "))" else empty end' "${dir}/flow.json"
}

flows_leak_problems() {
  local dir="$1" pattern found
  found="$(grep -rhoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$dir" | grep -viE "@([a-z0-9-]+\.)*${FLOWS_EXAMPLE_DOMAINS}$" | sort -u | head -n 3 || true)"
  [ -z "$found" ] || printf 'real-looking email address (use example.com): %s\n' "$(paste -sd ' ' <<< "$found")"
  found="$(cat "${dir}/flow.json" "${dir}/template.yaml" "${dir}"/test/*.json 2>/dev/null \
    | grep -oE 'https?://[^]["'"'"' )<>}\\]+' | grep -viE "^https?://([a-z0-9-]+\.)*${FLOWS_EXAMPLE_DOMAINS}([/:?#]|$)" | sort -u | head -n 3 || true)"
  [ -z "$found" ] || printf 'real-looking URL in flow/test data (use example.com or a placeholder): %s\n' "$(paste -sd ' ' <<< "$found")"
  for pattern in "${FLOWS_SECRET_PATTERNS[@]}"; do
    if grep -rqE -- "$pattern" "$dir"; then
      printf 'looks like a real key, token or private link (pattern %s) — remove it\n' "$pattern"
    fi
  done
  grep -qF "connections[" "${dir}/flow.json" \
    && printf 'flow.json: a connection is referenced; leave step connections empty (the client picks their own)\n'
  jq -r '[.. | objects | select(has("input")) | .input | .. | strings
      | select(test("^[A-Za-z0-9_-]{25,}$") or test("^[0-9]{8,}$"))] | unique | .[:3] |
    if length > 0 then "flow.json: real-looking ids in step inputs (use a placeholder): \(join(" "))" else empty end' "${dir}/flow.json"
}

flows_placeholder_value_problems() {
  local dir="$1"
  yq -o=json '.' "${dir}/template.yaml" | jq -r '
    def bad($p; $v): ($p.type == "number" and ($v | test("^-?[0-9]+([.][0-9]+)?$") | not))
      or ($p.choices != null and ($p.choices | index($v)) == null);
    (.placeholders // []) as $ps
    | ($ps[] | . as $p | ([.example] + (if has("default") then [.default] else [] end))[]
        | select(bad($p; .)) | "placeholder \($p.key): \(.) is not a valid \($p.type // "string")\(if $p.choices then " (one of: " + ($p.choices | join(", ")) + ")" else "" end)"),
    ((.test.set // {}) | to_entries[] | . as $e | ($ps | map(select(.key == $e.key)) | first) as $p
      | if $p == null then "test.set: \($e.key) is not a declared placeholder"
        elif bad($p; $e.value) then "test.set: \($e.key)=\($e.value) is not valid for that placeholder"
        else empty end)'
}

flows_test_problems() {
  local dir="$1" payload steps
  flows_placeholder_value_problems "$dir"
  steps="$(jq -c '[.. | objects | select(has("type") and has("name") and has("settings")) | .name]' "${dir}/flow.json")"
  yq -o=json '.test.runs // []' "${dir}/template.yaml" | jq -r --argjson steps "$steps" '
    .[] | ((.stubs // {}) | keys[]), (.ran // [])[], (.not_ran // [])[]
    | select(. as $s | $steps | index($s) | not) | "test step \(.) does not exist in flow.json"' | sort -u
  while IFS= read -r payload; do
    [ -n "$payload" ] || continue
    if [ ! -f "${dir}/${payload}" ]; then
      printf 'test payload missing: %s\n' "$payload"
    elif ! jq -e . "${dir}/${payload}" >/dev/null 2>&1; then
      printf 'test payload is not valid JSON: %s\n' "$payload"
    fi
  done < <(yq -r '.test.runs[]? | [.payload] + ((.stubs // {}) | to_entries | map(.value)) | .[]' "${dir}/template.yaml" | sort -u)
}

# flows_validate_one <id>: prints [ok]/[fail] lines; returns 1 when invalid
flows_validate_one() {
  local id="$1" dir problems schema_out line schema_ok=0
  dir="$(flows_template_dir "$id")"
  schema_out="$(validate_against_schema "${OPSKIT_ROOT}/schema/template.schema.json" "${dir}/template.yaml" 2>&1)" || schema_ok=1
  if [ "$schema_ok" -ne 0 ]; then
    while IFS= read -r line; do
      case "$line" in
        "[fail] template.yaml: invalid") ;;
        "[fail] "*) log_fail "${id}: template.yaml ${line#\[fail\] }" ;;
      esac
    done <<< "$schema_out"
  fi
  problems="$(flows_problems "$dir")"
  if [ -n "$problems" ]; then
    while IFS= read -r line; do log_fail "${id}: ${line}"; done <<< "$problems"
  fi
  if [ -n "$problems" ] || [ "$schema_ok" -ne 0 ]; then
    log_fail "${id}: invalid"
    return 1
  fi
  log_ok "${id}: valid"
}
