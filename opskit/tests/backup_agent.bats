#!/usr/bin/env bats

load helpers/common

AGENT="${BATS_TEST_DIRNAME}/../agent/backup.sh"

setup() {
  ROOT="$(mktemp -d)"
  STUB="$(mktemp -d)"
  mkdir -p "${ROOT}/agent" "${ROOT}/clients/acme"
  echo "age1testpublickeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" > "${ROOT}/agent/owner.age.pub"
  printf 'AP_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef\n' > "${ROOT}/clients/acme/.env"
  echo "name: acme" > "${ROOT}/clients/acme/compose.yml"
  cat > "${STUB}/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  ps) [ "${FAKE_PG_DOWN:-}" = "1" ] || echo cid ;;
  exec)
    if [ "$2" = "-i" ]; then cat >/dev/null; exit "${FAKE_RESTORE_LIST_RC:-0}"; fi
    [ "${FAKE_EMPTY_DUMP:-}" = "1" ] || printf 'PGDMP-fake-dump'
    ;;
esac
SH
  cat > "${STUB}/age" <<'SH'
#!/usr/bin/env bash
out=""; in=""
while [ "$#" -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; -R) shift 2 ;; *) in="$1"; shift ;; esac; done
printf 'age-encrypted:%s' "$(wc -c < "$in")" > "$out"
SH
  chmod +x "${STUB}/docker" "${STUB}/age"
  export PATH="${STUB}:${PATH}"
}

teardown() {
  rm -rf "$ROOT" "$STUB"
}

backups() {
  find "${ROOT}/backups/acme" -mindepth 1 -maxdepth 1 -type d | wc -l
}

@test "successful backup writes db, encrypted env, compose and status, all private" {
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  local dir="${ROOT}/backups/acme/$(cat "${ROOT}/backups/acme/latest")"
  for f in db.dump env.age compose.yml status.json; do
    [ -s "${dir}/${f}" ]
    [ "$(stat -c %a "${dir}/${f}")" = "600" ]
  done
  ! grep -q 0123456789abcdef "${dir}/env.age"
  [ "$(jq -r .backup "${dir}/status.json")" = "$(cat "${ROOT}/backups/acme/latest")" ]
  [ "$(jq -r .local "${dir}/status.json")" = "ok" ]
}

@test "stopped database fails without leaving a backup" {
  FAKE_PG_DOWN=1 run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"postgres container for acme is not running"* ]]
  [ "$(backups)" = "0" ]
}

@test "empty dump or failed integrity check fails and cleans up" {
  FAKE_EMPTY_DUMP=1 run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"database dump is empty"* ]]
  FAKE_RESTORE_LIST_RC=1 run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"integrity check"* ]]
  [ "$(backups)" = "0" ]
}

@test "missing owner public key fails (secrets are never stored unencrypted)" {
  rm "${ROOT}/agent/owner.age.pub"
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"owner age public key missing"* ]]
  [ "$(backups)" = "0" ]
}

@test "a running backup of the same client makes the second one skip" {
  mkdir -p "${ROOT}/backups/acme"
  run flock "${ROOT}/backups/acme/.lock" -c "'$AGENT' acme --root '$ROOT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"another backup of acme is running; skipped"* ]]
  [ "$(backups)" = "0" ]
}

@test "bad arguments are refused" {
  run "$AGENT" "Bad Id" --root "$ROOT"
  [ "$status" -eq 1 ]
  run "$AGENT" acme --root relative
  [ "$status" -eq 1 ]
}
