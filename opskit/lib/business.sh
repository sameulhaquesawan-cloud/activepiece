#!/usr/bin/env bash
# The owner's business profile (<registry>/owner/business.yaml) for client-facing documents. Missing file or
# field → placeholder from opskit/templates/business.example.yaml, with one warning per run.

business_file() {
  printf '%s/owner/business.yaml' "$(registry_root)"
}

# business_get <field>: the owner's value, else the placeholder
business_get() {
  local file value=""
  file="$(business_file)"
  if [ -f "$file" ]; then
    value="$(yq -r ".${1} // \"\"" "$file" 2>/dev/null || true)"
  fi
  if [ -z "$value" ]; then
    if [ -z "${BUSINESS_WARNED:-}" ]; then
      log_warn "owner business profile incomplete (${file}): using placeholders like \"YourBrand\"; copy opskit/templates/business.example.yaml there" >&2
      BUSINESS_WARNED=1
    fi
    value="$(yq -r ".${1} // \"\"" "${OPSKIT_ROOT}/templates/business.example.yaml")"
  fi
  printf '%s' "$value"
}

# business_check: the profile exists and is valid (needs schema.sh)
business_check() {
  local file
  file="$(business_file)"
  [ -f "$file" ] || { log_warn "no owner business profile at ${file} (placeholders will be used)"; return 0; }
  validate_against_schema "${OPSKIT_ROOT}/schema/business.schema.json" "$file" >/dev/null || {
    log_fail "owner business profile ${file} is invalid: opskit/bin/opskit validate ${file}"
    return 1
  }
}

# client_notes_file <id>
client_notes_file() {
  printf '%s/notes.yaml' "$(client_dir "$1")"
}
