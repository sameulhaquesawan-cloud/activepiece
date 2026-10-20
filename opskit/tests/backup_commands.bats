#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client demo
  HOSTROOT="$(mktemp -d)"
  yq -i ".opskit_root = \"${HOSTROOT}\"" "${REG}/hosts/local-practice.yaml"
}

teardown() {
  rm -rf "$REG" "$HOSTROOT"
}

@test "backup refuses when the agent is not installed" {
  run "$OPSKIT" backup demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup agent not installed"* ]]
}

@test "backup reports local-only (exit 2) from the agent" {
  mkdir -p "${HOSTROOT}/agent"
  printf '#!/usr/bin/env bash\necho "[warn] local only"\nexit 2\n' > "${HOSTROOT}/agent/backup.sh"
  chmod +x "${HOSTROOT}/agent/backup.sh"
  run "$OPSKIT" backup demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"backup of demo is local only"* ]]
}

@test "backups lists host backups with size and off-server status" {
  local name
  for name in 20261001T023000Z 20261002T023000Z; do
    mkdir -p "${HOSTROOT}/backups/demo/${name}"
    printf '{"backup":"%s","db_bytes":1234,"remote":"ok"}\n' "$name" > "${HOSTROOT}/backups/demo/${name}/status.json"
  done
  run "$OPSKIT" backups demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"20261001T023000Z  db 1234 bytes  off-server: ok"* ]]
  [[ "$output" == *"20261002T023000Z"* ]]
  [[ "$output" == *"no off-server remote configured"* ]]
}
