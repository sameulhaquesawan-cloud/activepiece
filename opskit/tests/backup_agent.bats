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
if [ -n "${FAKE_AGE_FAIL_ON:-}" ] && [ "$(basename "$in")" = "$FAKE_AGE_FAIL_ON" ]; then exit 1; fi
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

@test "successful backup writes encrypted db and env, compose and status, all private" {
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 2 ]
  local dir="${ROOT}/backups/acme/$(cat "${ROOT}/backups/acme/latest")"
  [ ! -e "${dir}/db.dump" ]
  ! grep -q PGDMP "${dir}/db.dump.age"
  [ "$(jq -r .encrypted "${dir}/status.json")" = "true" ]
  [ "$(jq -r .db_bytes "${dir}/status.json")" = "$(stat -c %s "${dir}/db.dump.age")" ]
  for f in db.dump.age env.age compose.yml status.json; do
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

@test "a failed database encryption fails and leaves no backup (no plain dump kept)" {
  FAKE_AGE_FAIL_ON=db.dump run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"database encryption failed"* ]]
  [ "$(backups)" = "0" ]
  [ -z "$(find "${ROOT}/backups" -name 'db.dump*')" ]
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

@test "a running upgrade makes the nightly backup skip; the upgrade's own backup and a stale lock do not" {
  mkdir -p "${ROOT}/state/acme/upgrade.lock"
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"an upgrade of acme is running; backup skipped"* ]]
  [ "$(backups)" = "0" ]
  run "$AGENT" acme --root "$ROOT" --during-upgrade
  [ "$status" -eq 2 ]
  [ "$(backups)" = "1" ]
  touch -d '13 hours ago' "${ROOT}/state/acme/upgrade.lock"
  sleep 1
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 2 ]
  [ "$(backups)" = "2" ]
}

@test "bad arguments are refused" {
  run "$AGENT" "Bad Id" --root "$ROOT"
  [ "$status" -eq 1 ]
  run "$AGENT" acme --root relative
  [ "$status" -eq 1 ]
}

ago_name() {
  date -u -d "@$(( $(date +%s) - $1 ))" +%Y%m%dT%H%M%SZ
}

setup_remote() {
  REMOTE_DIR="$(mktemp -d)"
  printf '[offsite]\ntype = local\n' > "${ROOT}/agent/rclone.conf"
  printf 'BACKUP_REMOTE=offsite:%s\nKEEP_LOCAL_DAYS=%s\nKEEP_REMOTE_DAYS=%s\n' "$REMOTE_DIR" "${1:-14}" "${2:-30}" > "${ROOT}/clients/acme/backup.conf"
}

@test "off-server copy is verified and recorded" {
  setup_remote
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  local name
  name="$(cat "${ROOT}/backups/acme/latest")"
  [ -s "${REMOTE_DIR}/acme/${name}/db.dump.age" ]
  [ ! -e "${REMOTE_DIR}/acme/${name}/db.dump" ]
  [ -s "${REMOTE_DIR}/acme/${name}/env.age" ]
  [ "$(jq -r .remote "${ROOT}/backups/acme/${name}/status.json")" = "ok" ]
  [ "$(jq -r .remote "${REMOTE_DIR}/acme/${name}/status.json")" = "ok" ]
  rm -rf "$REMOTE_DIR"
}

@test "no remote configured: local only, exit 2, not counted as complete" {
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not count as complete"* ]]
  [ "$(jq -r .remote "${ROOT}/backups/acme/$(cat "${ROOT}/backups/acme/latest")/status.json")" = "none" ]
}

@test "failed off-server copy fails the backup" {
  printf '[offsite]\ntype = local\n' > "${ROOT}/agent/rclone.conf"
  printf 'BACKUP_REMOTE=missing-remote:/x\n' > "${ROOT}/clients/acme/backup.conf"
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rclone copy to missing-remote:/x failed"* ]]
}

@test "local retention keeps exactly the configured days of nightly backups" {
  setup_remote 14 30
  local k
  for k in $(seq 1 29); do
    mkdir -p "${ROOT}/backups/acme/$(ago_name $((k * 86400 + 60)))"
  done
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"local retention 14 days: pruned 16"* ]]
  [ "$(find "${ROOT}/backups/acme" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "14" ]
  [ "$(find "${ROOT}/backups/acme" -mindepth 1 -maxdepth 1 -type d -name "$(date -u -d "@$(( $(date +%s) - 14 * 86400 ))" +%Y%m%d)*" | wc -l)" = "0" ]
  rm -rf "$REMOTE_DIR"
}

@test "remote retention keeps the configured days; zero days still keeps the newest" {
  setup_remote 0 30
  local k
  local name
  for k in $(seq 1 40); do
    name="$(ago_name $((k * 86400 + 60)))"
    mkdir -p "${REMOTE_DIR}/acme/${name}"
    echo x > "${REMOTE_DIR}/acme/${name}/f"
  done
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remote retention 30 days: pruned 11"* ]]
  [ "$(find "${REMOTE_DIR}/acme" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "30" ]
  [ "$(find "${ROOT}/backups/acme" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "1" ]
  rm -rf "$REMOTE_DIR"
}

@test "every run leaves one history line: complete, local only, failed, skipped during an upgrade" {
  local history="${ROOT}/backups/acme/history.jsonl"
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 2 ]
  sleep 1
  FAKE_PG_DOWN=1 run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 1 ]
  mkdir -p "${ROOT}/state/acme/upgrade.lock"
  run "$AGENT" acme --root "$ROOT"
  rm -rf "${ROOT}/state/acme/upgrade.lock"
  setup_remote
  sleep 1
  run "$AGENT" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.result' "$history" | paste -sd' ')" = "local_only failed skipped complete" ]
  [ "$(jq -r 'select(.result == "failed") | .reason' "$history")" = "dump or encryption step failed" ]
  [ "$(jq -r 'select(.result == "complete") | .backup' "$history")" = "$(cat "${ROOT}/backups/acme/latest")" ]
  [ "$(jq -r 'select(.result == "skipped") | .reason' "$history")" = "upgrade running" ]
  [ "$(jq -r '.at' "$history" | grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || true)" = "0" ]
  rm -rf "$REMOTE_DIR"
}
