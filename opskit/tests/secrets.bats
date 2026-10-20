#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/validate.sh"
  source "${OPSKIT_ROOT}/lib/registry.sh"
  source "${OPSKIT_ROOT}/lib/secrets.sh"
  mkdir -p "${REG}/clients/demo"
  STUB="$(mktemp -d)"
}

teardown() {
  rm -rf "$REG" "$STUB"
}

fake_openssl() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "${STUB}/openssl"
  chmod +x "${STUB}/openssl"
}

@test "generates four secrets with the right lengths and mode 600" {
  run secrets_ensure demo
  [ "$status" -eq 0 ]
  local file="${REG}/clients/demo/secrets.env"
  [ "$(stat -c %a "$file")" = "600" ]
  grep -qE '^AP_API_KEY=[0-9a-f]{128}$' "$file"
  grep -qE '^AP_POSTGRES_PASSWORD=[0-9a-f]{64}$' "$file"
  grep -qE '^AP_JWT_SECRET=[0-9a-f]{64}$' "$file"
  grep -qE '^AP_ENCRYPTION_KEY=[0-9a-f]{32}$' "$file"
}

@test "never prints secret values" {
  run secrets_ensure demo
  local key
  key="$(sed -n 's/^AP_ENCRYPTION_KEY=//p' "${REG}/clients/demo/secrets.env")"
  [[ "$output" != *"$key"* ]]
}

@test "empty openssl output aborts and writes nothing" {
  fake_openssl 'exit 0'
  PATH="${STUB}:${PATH}" run secrets_ensure demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty or malformed AP_API_KEY"* ]]
  [ -z "$(ls -A "${REG}/clients/demo")" ]
}

@test "malformed openssl output aborts" {
  fake_openssl 'echo not-hex'
  PATH="${STUB}:${PATH}" run secrets_ensure demo
  [ "$status" -eq 1 ]
  [ ! -e "${REG}/clients/demo/secrets.env" ]
}

@test "re-running keeps the existing secrets" {
  secrets_ensure demo
  local before
  before="$(sha256sum "${REG}/clients/demo/secrets.env")"
  run secrets_ensure demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept existing"* ]]
  [ "$(sha256sum "${REG}/clients/demo/secrets.env")" = "$before" ]
}

@test "a damaged secrets file is never regenerated" {
  secrets_ensure demo
  sed -i '/^AP_ENCRYPTION_KEY=/d' "${REG}/clients/demo/secrets.env"
  run secrets_ensure demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to regenerate"* ]]
  run grep -c AP_ENCRYPTION_KEY "${REG}/clients/demo/secrets.env"
  [ "$output" = "0" ]
}

@test "secrets_export exports values into the shell" {
  secrets_ensure demo
  secrets_export demo
  [[ "$AP_ENCRYPTION_KEY" =~ ^[0-9a-f]{32}$ ]]
  [[ "$AP_JWT_SECRET" =~ ^[0-9a-f]{64}$ ]]
}
