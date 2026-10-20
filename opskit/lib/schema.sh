#!/usr/bin/env bash
# YAML/JSON schema validation via pinned ajv-cli (operator machine only; Node + npx required).

AJV_CLI_VERSION="5.0.0"
AJV_FORMATS_VERSION="3.0.1"

# schema_errors_to_lines: ajv JSON errors on stdin -> "field: message" lines
schema_errors_to_lines() {
  jq -r '.[] | (.instancePath | ltrimstr("/") | gsub("/"; ".")) as $path
    | def at($name): if $path == "" then $name else $path + "." + $name end;
    if .keyword == "required" then at(.params.missingProperty) + ": is required"
    elif .keyword == "additionalProperties" then at(.params.additionalProperty) + ": unknown field"
    elif .keyword == "enum" then $path + ": must be one of: " + (.params.allowedValues | map(tostring) | join(", "))
    elif .keyword == "not" then $path + ": this value is not allowed"
    elif .keyword == "pattern" then $path + ": has an invalid format"
    else $path + ": " + .message end' | sort -u
}

# validate_against_schema <schema.json> <file.yaml|json>
validate_against_schema() {
  local schema="$1" file="$2" tmp json errors status=0
  tmp="$(mktemp -d)"
  json="${tmp}/data.json"
  if ! yq -o=json '.' "$file" > "$json" 2>/dev/null || [ "$(jq -r 'type' "$json")" != "object" ]; then
    rm -rf "$tmp"
    log_fail "$(basename "$file"): not a valid YAML/JSON mapping"
    return 1
  fi
  errors="$(cd "$tmp" && npm_config_update_notifier=false npx -y -p "ajv-cli@${AJV_CLI_VERSION}" -p "ajv-formats@${AJV_FORMATS_VERSION}" \
    ajv validate --spec=draft2020 -c ajv-formats --all-errors --errors=json -s "$schema" -d "$json" 2>&1 >/dev/null)" || status=$?
  if [ "$status" -eq 0 ]; then
    rm -rf "$tmp"
    log_ok "$(basename "$file"): valid"
    return 0
  fi
  if ! printf '%s\n' "$errors" | tail -n +2 | jq -e 'type == "array"' >/dev/null 2>&1; then
    rm -rf "$tmp"
    log_fail "$(basename "$file"): validator did not run (needs node/npx and network on first use)"
    return 1
  fi
  printf '%s\n' "$errors" | tail -n +2 | schema_errors_to_lines | while IFS= read -r line; do
    log_fail "${line}"
  done
  rm -rf "$tmp"
  log_fail "$(basename "$file"): invalid"
  return 1
}
