#!/usr/bin/env bash
# flows check-pieces: compare every piece step's input with the piece's own property definitions from
# the Activepieces catalog (needs internet; OPSKIT_PIECES_METADATA_DIR serves saved metadata instead).
# The builder marks a step "Incomplete" when an optional list property is missing (0.92.3
# pieces-framework buildSchema), so lists must be present, required inputs filled, keys known.

FLOWS_CATALOG_URL="${OPSKIT_PIECES_CATALOG_URL:-https://cloud.activepieces.com/api/v1/pieces}"

# flows_piece_metadata <name> <version>: metadata file path (cached in FLOWS_META_DIR)
flows_piece_metadata() {
  local name="$1" version="$2" file
  file="${FLOWS_META_DIR}/$(sed -E 's#^@##; s#/#_#' <<< "$name")@${version}.json"
  if [ -n "${OPSKIT_PIECES_METADATA_DIR:-}" ]; then
    printf '%s/%s' "$OPSKIT_PIECES_METADATA_DIR" "$(basename "$file")"
    return 0
  fi
  if [ ! -s "$file" ]; then
    curl -sS -m 30 -o "$file" "${FLOWS_CATALOG_URL}/${name}?version=${version}" 2>/dev/null || rm -f "$file"
  fi
  printf '%s' "$file"
}

# flows_piece_input_problems <flow.json> <step json line> <metadata file>
flows_piece_input_problems() {
  jq -r --argjson step "$2" '
    ($step.settings) as $s
    | (if $step.type == "PIECE_TRIGGER" then .triggers[$s.triggerName] else .actions[$s.actionName] end) as $c
    | if $c == null then "\($step.name): \($s.triggerName // $s.actionName) does not exist in \($s.pieceName) \($s.pieceVersion)"
      else ($s.input // {}) as $in
      | ($c.props | to_entries[] | . as $e
          | select($e.value.type == "ARRAY" and ($in | has($e.key) | not))
          | "\($step.name): list input \($e.key) must be present (use []) or the builder marks the step Incomplete"),
        ($c.props | to_entries[] | . as $e
          | select($e.value.required == true)
          | select($e.value.type as $t | ["DROPDOWN", "MULTI_SELECT_DROPDOWN", "DYNAMIC", "MARKDOWN"] | index($t) | not)
          | select($in[$e.key] == null or $in[$e.key] == "")
          | "\($step.name): required input \($e.key) is empty"),
        ($in | keys[] | select(. as $k | $c.props | has($k) | not) | "\($step.name): unknown input \(.)")
      end' "$3"
}

# flows_check_pieces_one <id>: [ok]/[fail] lines
flows_check_pieces_one() {
  local id="$1" dir step name version meta found problems=""
  dir="$(flows_template_dir "$id")"
  while IFS= read -r step; do
    name="$(jq -r '.settings.pieceName' <<< "$step")"
    version="$(jq -r '.settings.pieceVersion' <<< "$step")"
    [ "$(KEY="$name" yq -r '.pieces[] | select(.name == strenv(KEY)) | .custom // ""' "${dir}/template.yaml")" = "" ] || continue
    meta="$(flows_piece_metadata "$name" "$version")"
    if ! jq -e '.actions' "$meta" >/dev/null 2>&1; then
      problems+="$(jq -r '.name' <<< "$step"): no metadata for ${name} ${version} (offline or unknown version)"$'\n'
      continue
    fi
    if ! found="$(flows_piece_input_problems "${dir}/flow.json" "$step" "$meta" 2>&1)"; then
      found="$(jq -r '.name' <<< "$step"): could not compare with the catalog: ${found:0:200}"
    fi
    problems+="${found}"$'\n'
  done < <(jq -c '.. | objects | select((.type == "PIECE" or .type == "PIECE_TRIGGER") and has("settings"))' "${dir}/flow.json")
  problems="$(grep -v '^$' <<< "$problems" || true)"
  if [ -n "$problems" ]; then
    while IFS= read -r line; do log_fail "${id}: ${line}"; done <<< "$problems"
    return 1
  fi
  log_ok "${id}: piece inputs match the catalog"
}
