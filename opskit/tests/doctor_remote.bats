#!/usr/bin/env bats

load helpers/common

setup() {
  REG="$(mktemp -d)"
  STORE="$(mktemp -d)"
  STUB="$(mktemp -d)"
  export OPSKIT_REGISTRY="$REG"
  mkdir -p "${REG}/owner" "${STORE}/my-backups"
  printf '[b2]\ntype = local\n' > "${REG}/owner/rclone.conf"
  chmod 600 "${REG}/owner/rclone.conf"
}

teardown() {
  rm -rf "$REG" "$STORE" "$STUB"
}

remote() {
  cd "$STORE"
  run "$OPSKIT" doctor --remote "$@"
}

fake_rclone() {
  printf '%s\n' "$1" > "${STUB}/message"
  printf '#!/usr/bin/env bash\ncase " $* " in *" listremotes "*) echo b2: ;; *) cat "%s" >&2; exit 1 ;; esac\n' "${STUB}/message" > "${STUB}/rclone"
  chmod +x "${STUB}/rclone"
  export PATH="${STUB}:${PATH}"
}

@test "remote: an existing bucket and a path the first backup will create pass" {
  remote "b2:my-backups/clients"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] remote: b2:my-backups answers with this key"* ]]
  [[ "$output" == *"does not exist yet (the first backup creates it)"* ]]
}

@test "remote: --write-test writes and removes a test file" {
  remote "b2:my-backups" --write-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] remote: write and delete work (test file removed)"* ]]
  [ -z "$(ls -A "${STORE}/my-backups")" ]
}

@test "remote: missing rclone.conf, unknown remote name and bad syntax are clear failures" {
  remote "nope"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not <remote>:<bucket>[/path]"* ]]
  remote "other:bucket"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] remote: 'other' is not defined in"* ]]
  rm "${REG}/owner/rclone.conf"
  remote "b2:bucket"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] remote: no ${REG}/owner/rclone.conf"* ]]
}

@test "remote: a missing bucket fails" {
  remote "b2:missing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] remote: b2:"*"not found"* ]]
}

@test "remote: a world-readable rclone.conf is a warning" {
  chmod 644 "${REG}/owner/rclone.conf"
  remote "b2:my-backups"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] remote: ${REG}/owner/rclone.conf should be private"* ]]
}

@test "remote: a refused key is named and rclone's own text (key ids) is never printed" {
  fake_rclone 'ERROR : couldn'"'"'t list: Unauthorized (401 bad_auth_token) account 0012abcdKEYID'
  remote "b2:my-backups"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the key was refused"* ]]
  [[ "$output" != *"0012abcdKEYID"* ]]
}

@test "remote: a network failure is not reported as a wrong key" {
  fake_rclone 'Failed to create file system: failed to authorize account: Get "https://api.backblazeb2.com/b2api/v1/b2_authorize_account": Forbidden'
  remote "b2:my-backups"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not be reached from this machine (network)"* ]]
}

@test "--write-test without --remote is a usage error" {
  run "$OPSKIT" doctor --write-test
  [ "$status" -eq 1 ]
}
