#!/usr/bin/env bash
# opskit backup agent — standalone (no repo on the host). One client per run; safe from cron.
# Layout: <root>/backups/<id>/<UTC ts>/{db.dump, env.age, compose.yml, status.json}
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: backup.sh <client id> [--root <opskit root>]

Dumps the client's Postgres (pg_dump custom format, integrity-checked), encrypts the
client's .env with the owner's age public key (<root>/agent/owner.age.pub), snapshots
compose.yml and writes status.json. Then (if configured in <root>/clients/<id>/backup.conf)
copies off-server with rclone, prunes old backups, sends a heartbeat or an alert.
EOF
}

ok() { printf '[ok] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*"; }
fail() { printf '[fail] %s\n' "$*" >&2; }

ROOT="/opt/opskit"
CLIENT=""

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) ROOT="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      -*) usage >&2; exit 1 ;;
      *) CLIENT="$1"; shift ;;
    esac
  done
  [[ "$CLIENT" =~ ^[a-z][a-z0-9-]{0,30}[a-z0-9]$ ]] || { fail "client id required (slug)"; exit 1; }
  [[ "$ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || { fail "--root must be an absolute path"; exit 1; }
}

postgres_container() {
  docker ps -q --filter "label=com.docker.compose.project=${CLIENT}" --filter "label=com.docker.compose.service=postgres" | head -n 1
}

dump_database() {
  local container="$1" target="$2"
  docker exec "$container" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner -Fc' > "$target"
  [ -s "$target" ] || { fail "database dump is empty"; return 1; }
  docker exec -i "$container" pg_restore --list < "$target" > /dev/null \
    || { fail "database dump failed the pg_restore --list integrity check"; return 1; }
}

encrypt_env() {
  local target="$1" key="${ROOT}/agent/owner.age.pub"
  [ -s "$key" ] || { fail "owner age public key missing: ${key}"; return 1; }
  age -R "$key" -o "$target" "${ROOT}/clients/${CLIENT}/.env"
  [ -s "$target" ] || { fail "encrypted .env is empty"; return 1; }
}

write_status() {
  local dir="$1" started="$2" name="$3"
  local now db_bytes env_bytes
  now="$(date +%s)"
  db_bytes="$(stat -c %s "${dir}/db.dump")"
  env_bytes="$(stat -c %s "${dir}/env.age")"
  printf '{"client":"%s","backup":"%s","db_bytes":%s,"env_bytes":%s,"duration_s":%s,"local":"ok"}\n' \
    "$CLIENT" "$name" "$db_bytes" "$env_bytes" "$((now - started))" > "${dir}/status.json"
}

run_backup() {
  local base="${ROOT}/backups/${CLIENT}" ts dir started container
  started="$(date +%s)"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  while [ -e "${base}/${ts}" ]; do
    sleep 1
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
  done
  dir="${base}/${ts}"
  container="$(postgres_container)"
  [ -n "$container" ] || { fail "postgres container for ${CLIENT} is not running"; return 1; }
  mkdir -p "${dir}.partial"
  chmod 700 "$base" "${dir}.partial"
  dump_database "$container" "${dir}.partial/db.dump" || { rm -rf "${dir}.partial"; return 1; }
  encrypt_env "${dir}.partial/env.age" || { rm -rf "${dir}.partial"; return 1; }
  cp "${ROOT}/clients/${CLIENT}/compose.yml" "${dir}.partial/compose.yml"
  write_status "${dir}.partial" "$started" "$ts"
  mv "${dir}.partial" "$dir"
  ok "backup ${CLIENT}/${ts}: db $(stat -c %s "${dir}/db.dump") bytes, env.age $(stat -c %s "${dir}/env.age") bytes"
  BACKUP_DIR="$dir"
}

main() {
  umask 077
  parse_args "$@"
  mkdir -p "${ROOT}/backups/${CLIENT}"
  exec 9> "${ROOT}/backups/${CLIENT}/.lock"
  flock -n 9 || { warn "another backup of ${CLIENT} is running; skipped"; exit 0; }
  find "${ROOT}/backups/${CLIENT}" -maxdepth 1 -name '*.partial' -type d -exec rm -rf {} +
  if ! run_backup; then
    fail "backup of ${CLIENT} failed"
    exit 1
  fi
  basename "$BACKUP_DIR" > "${ROOT}/backups/${CLIENT}/latest"
}

main "$@"
