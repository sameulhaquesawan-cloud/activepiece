#!/usr/bin/env bash
# Template rendering: substitute ${NAME} from the environment with envsubst.
# Fails (naming the variables, never their values) if any referenced variable is unset or empty.

template_vars() {
  grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$1" | sort -u | sed -E 's/^\$\{(.*)\}$/\1/' || true
}

# render_template <template file> <output file>
render_template() {
  local template="$1" output="$2" name shell_format="" missing=()
  [ -f "$template" ] || { log_fail "template not found: ${template}"; return 1; }
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -z "${!name:-}" ]; then
      missing+=("$name")
    fi
    shell_format+="\${${name}} "
  done < <(template_vars "$template")
  if [ "${#missing[@]}" -gt 0 ]; then
    log_fail "$(basename "$template"): unresolved variables: ${missing[*]}"
    return 1
  fi
  local tmp
  tmp="$(mktemp "${output}.XXXXXX")"
  if ! envsubst "$shell_format" < "$template" > "$tmp"; then
    rm -f "$tmp"
    log_fail "$(basename "$template"): envsubst failed"
    return 1
  fi
  mv "$tmp" "$output"
  log_ok "rendered $(basename "$output")"
}
