#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client demo
  mkdir -p "${REG}/owner"
  printf 'TELEGRAM_BOT_TOKEN=123:registry-secret-marker\n' > "${REG}/owner/alerts.conf"
  KEYS="$(mktemp -d)"
  age-keygen -o "${KEYS}/owner.key" 2>/dev/null
  age-keygen -y "${KEYS}/owner.key" > "${KEYS}/owner.age.pub"
  REMOTE="$(mktemp -d)"
  printf '[offsite]\ntype = local\n' > "${REG}/owner/rclone.conf"
  export OPSKIT_OWNER_AGE_PUB="${KEYS}/owner.age.pub" OPSKIT_OWNER_AGE_KEY="${KEYS}/owner.key"
  export OPSKIT_REGISTRY_BACKUPS="${KEYS}/backups"
}

teardown() {
  rm -rf "$REG" "$KEYS" "$REMOTE"
}

archives() {
  find "$OPSKIT_REGISTRY_BACKUPS" -maxdepth 1 -name 'registry-*.tar.gz.age' | sort
}

@test "backup: one encrypted archive of clients, hosts and owner, private folder, checked with the key" {
  run "$OPSKIT" registry backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] registry backup registry-"*": clients hosts owner ("*"encrypted, checked with your private key)"* ]]
  [[ "$output" == *"kept on this machine only: add --to"* ]]
  [ "$(archives | grep -c .)" = "1" ]
  [ "$(stat -c %a "$OPSKIT_REGISTRY_BACKUPS")" = "700" ]
  [ "$(stat -c %a "$(archives)")" = "600" ]
  ! grep -q "registry-secret-marker" "$(archives)"
  age -d -i "${KEYS}/owner.key" "$(archives)" | tar -tzf - | grep -qx "owner/alerts.conf"
  age -d -i "${KEYS}/owner.key" "$(archives)" | tar -tzf - | grep -qx "clients/demo/client.yaml"
  [[ "$output" != *"registry-secret-marker"* ]]
}

@test "backup without the owner public key fails and writes nothing" {
  OPSKIT_OWNER_AGE_PUB="${KEYS}/missing.pub" run "$OPSKIT" registry backup
  [ "$status" -eq 1 ]
  [[ "$output" == *"no owner age public key"* ]]
  [ -z "$(archives 2>/dev/null)" ]
}

@test "backup --to copies it off the machine; the last 10 are kept locally" {
  run "$OPSKIT" registry backup --to "offsite:${REMOTE}/registry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] copied off this machine: offsite:${REMOTE}/registry/registry-"* ]]
  [ "$(find "${REMOTE}/registry" -name 'registry-*.tar.gz.age' | grep -c .)" = "1" ]
  local i
  for i in $(seq 1 11); do
    : > "${OPSKIT_REGISTRY_BACKUPS}/registry-20200101T0000$(printf '%02d' "$i")Z.tar.gz.age"
  done
  run "$OPSKIT" registry backup
  [ "$(archives | grep -c .)" = "10" ]
  ! archives | grep -q "registry-20200101T000001Z"
  run "$OPSKIT" registry backup --to "nosuchremote:x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"copy to nosuchremote:x failed"* ]]
}

@test "restore straight from the off-machine copy (remote:path) after this machine's archives are gone" {
  "$OPSKIT" registry backup --to "offsite:${REMOTE}/registry" >/dev/null
  local remote_file
  remote_file="offsite:${REMOTE}/registry/$(basename "$(archives)")"
  rm -rf "$OPSKIT_REGISTRY_BACKUPS" "${REG}/clients" "${REG}/hosts"
  run bash -c 'printf "registry\n" | "$0" registry restore "$1" --overwrite --yes' "$OPSKIT" "$remote_file"
  [ "$status" -eq 0 ]
  [ -f "${REG}/clients/demo/client.yaml" ]
  [ -f "${REG}/hosts/local-practice.yaml" ]
  run "$OPSKIT" registry restore "offsite:${REMOTE}/registry/registry-19990101T000000Z.tar.gz.age"
  [ "$status" -eq 1 ]
  [[ "$output" == *"registry backup not found"* ]]
}

@test "restore from the local latest archive; an existing registry needs --overwrite --yes and is moved aside" {
  "$OPSKIT" registry backup >/dev/null
  rm -rf "${REG}/clients" "${REG}/hosts" "${REG}/owner"
  run "$OPSKIT" registry restore latest
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] registry restored into ${REG}"* ]]
  grep -q "registry-secret-marker" "${REG}/owner/alerts.conf"
  [ -f "${REG}/clients/demo/client.yaml" ]
  [ -f "${REG}/hosts/local-practice.yaml" ]
  printf 'changed\n' > "${REG}/owner/alerts.conf"
  run "$OPSKIT" registry restore latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"already has clients hosts owner: nothing changed"* ]]
  grep -qx changed "${REG}/owner/alerts.conf"
  run bash -c 'printf "nope\n" | "$0" registry restore latest --overwrite --yes' "$OPSKIT"
  [ "$status" -eq 1 ]
  grep -qx changed "${REG}/owner/alerts.conf"
  run bash -c 'printf "registry\n" | "$0" registry restore latest --overwrite --yes' "$OPSKIT"
  [ "$status" -eq 0 ]
  grep -q "registry-secret-marker" "${REG}/owner/alerts.conf"
  grep -qx changed "$(find "$REG" -path '*/.registry-before-*/owner/alerts.conf')"
}

@test "restore with a wrong or missing private key changes nothing" {
  "$OPSKIT" registry backup >/dev/null
  age-keygen -o "${KEYS}/other.key" 2>/dev/null
  rm -rf "${REG}/clients"
  OPSKIT_OWNER_AGE_KEY="${KEYS}/other.key" run "$OPSKIT" registry restore latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not decrypt"* ]]
  [ ! -d "${REG}/clients" ]
  OPSKIT_OWNER_AGE_KEY="${KEYS}/missing.key" run "$OPSKIT" registry restore latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"owner private key not readable"* ]]
}

@test "usage errors" {
  run "$OPSKIT" registry
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: opskit registry backup"* ]]
  run "$OPSKIT" registry restore
  [ "$status" -eq 1 ]
  run "$OPSKIT" registry backup --to
  [ "$status" -eq 1 ]
  run "$OPSKIT" registry nope
  [ "$status" -eq 1 ]
}
