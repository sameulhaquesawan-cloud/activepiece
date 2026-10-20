#!/usr/bin/env bash
# Per-client secrets: generated once with openssl, stored in clients/<id>/secrets.env (mode 600),
# never regenerated (AP_ENCRYPTION_KEY decrypts stored connections). Values are never printed.

SECRET_SPECS=(
  "AP_API_KEY:64"
  "AP_POSTGRES_PASSWORD:32"
  "AP_JWT_SECRET:32"
  "AP_ENCRYPTION_KEY:16"
)

secrets_file() {
  printf '%s/secrets.env' "$(client_dir "$1")"
}

secret_valid() {
  local value="$1" bytes="$2"
  [[ "$value" =~ ^[0-9a-f]+$ ]] && [ "${#value}" -eq $((bytes * 2)) ]
}

secrets_check() {
  local file="$1" spec name bytes value bad=0
  for spec in "${SECRET_SPECS[@]}"; do
    name="${spec%%:*}"
    bytes="${spec#*:}"
    value="$(sed -n "s/^${name}=//p" "$file" | head -n 1)"
    if ! secret_valid "$value" "$bytes"; then
      log_fail "secret ${name} is missing or malformed in ${file}"
      bad=1
    fi
  done
  return "$bad"
}

# secrets_ensure <id>: create once; afterwards only verify
secrets_ensure() {
  local id="$1" file tmp spec name bytes value
  file="$(secrets_file "$id")"
  if [ -f "$file" ]; then
    chmod 600 "$file"
    secrets_check "$file" || { log_fail "refusing to regenerate secrets for ${id}: restore ${file} from escrow"; return 1; }
    log_ok "secrets: kept existing (${id})"
    return 0
  fi
  tmp="$(umask 077 && mktemp "${file}.XXXXXX")"
  for spec in "${SECRET_SPECS[@]}"; do
    name="${spec%%:*}"
    bytes="${spec#*:}"
    value="$(openssl rand -hex "$bytes" 2>/dev/null || true)"
    if ! secret_valid "$value" "$bytes"; then
      rm -f "$tmp"
      log_fail "secret generation produced an empty or malformed ${name}; nothing written"
      return 1
    fi
    printf '%s=%s\n' "$name" "$value" >> "$tmp"
  done
  chmod 600 "$tmp"
  mv "$tmp" "$file"
  log_ok "secrets: generated (${id}), stored with mode 600"
}

# secrets_export <id>: export the secrets into the current shell (use in a subshell)
secrets_export() {
  local file name value spec
  file="$(secrets_file "$1")"
  secrets_check "$file" || return 1
  for spec in "${SECRET_SPECS[@]}"; do
    name="${spec%%:*}"
    value="$(sed -n "s/^${name}=//p" "$file" | head -n 1)"
    export "${name}=${value}"
  done
}
