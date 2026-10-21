#!/usr/bin/env bash
# opskit backup agent — standalone (no repo on the host). One client per run; safe from cron.
# Layout: <root>/backups/<id>/<UTC ts>/{db.dump.age, env.age, compose.yml, status.json}
# The database dump and .env are both encrypted to the owner's age public key; no plain copy is kept.
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: backup.sh <client id> [--root <opskit root>]

Dumps the client's Postgres (pg_dump custom format, integrity-checked), encrypts the
client's .env with the owner's age public key (<root>/agent/owner.age.pub), snapshots
compose.yml and writes status.json. Then (if configured in <root>/clients/<id>/backup.conf)
copies off-server with rclone, prunes old backups, sends a heartbeat or an alert.

backup.conf keys: BACKUP_REMOTE (rclone remote:path), KEEP_LOCAL_DAYS (14), KEEP_REMOTE_DAYS (30),
HEARTBEAT_URL (Uptime Kuma push URL), HEARTBEAT_CACERT (practice hosts: Caddy's local root CA).
Alerts: alert.sh next to this script.
rclone credentials: <root>/agent/rclone.conf (600). Exit: 0 complete, 1 failed, 2 local only.
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

conf_get() {
  local key="$1" default="$2" file="${ROOT}/clients/${CLIENT}/backup.conf" value=""
  if [ -f "$file" ]; then
    value="$(sed -n "s/^${key}=//p" "$file" | tail -n 1)"
  fi
  printf '%s' "${value:-$default}"
}

rclone_cmd() {
  local conf="${ROOT}/agent/rclone.conf"
  if [ -f "$conf" ]; then
    rclone --config "$conf" "$@"
  else
    rclone "$@"
  fi
}

backup_epoch() {
  local name="$1"
  date -u -d "${name:0:4}-${name:4:2}-${name:6:2}T${name:9:2}:${name:11:2}:${name:13:2}Z" +%s
}

# expired_names <keep days> < names: prints names older than the window, never the newest
expired_names() {
  local days="$1" now cutoff newest name names
  now="${OPSKIT_NOW:-$(date +%s)}"
  cutoff=$((now - days * 86400))
  mapfile -t names < <(grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort)
  [ "${#names[@]}" -gt 0 ] || return 0
  newest="${names[-1]}"
  for name in "${names[@]}"; do
    [ "$name" = "$newest" ] && continue
    [ "$(backup_epoch "$name")" -lt "$cutoff" ] && printf '%s\n' "$name"
  done
  return 0
}

copy_offsite() {
  local dir="$1" remote name local_bytes remote_bytes
  remote="$(conf_get BACKUP_REMOTE "")"
  if [ -z "$remote" ]; then
    warn "no off-server remote configured (BACKUP_REMOTE): backup is local only and does not count as complete"
    return 2
  fi
  name="$(basename "$dir")"
  rclone_cmd copy "$dir" "${remote%/}/${CLIENT}/${name}" || { fail "rclone copy to ${remote} failed"; return 1; }
  local_bytes="$(find "$dir" -type f ! -name status.json -printf '%s\n' | awk '{s+=$1} END {print s+0}')"
  remote_bytes="$(rclone_cmd size --json --exclude status.json "${remote%/}/${CLIENT}/${name}" | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')"
  if [ "${remote_bytes:-0}" != "$local_bytes" ] || [ "$local_bytes" = "0" ]; then
    fail "off-server copy incomplete (${remote_bytes:-0} of ${local_bytes} bytes)"
    return 1
  fi
  ok "copied off-server: ${remote%/}/${CLIENT}/${name} (${local_bytes} bytes verified)"
}

prune_local() {
  local days name count=0
  days="$(conf_get KEEP_LOCAL_DAYS 14)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    rm -rf "${ROOT}/backups/${CLIENT}/${name}"
    count=$((count + 1))
  done < <(find "${ROOT}/backups/${CLIENT}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | expired_names "$days")
  ok "local retention ${days} days: pruned ${count}"
}

prune_remote() {
  local remote days name count=0
  remote="$(conf_get BACKUP_REMOTE "")"
  [ -n "$remote" ] || return 0
  days="$(conf_get KEEP_REMOTE_DAYS 30)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    rclone_cmd purge "${remote%/}/${CLIENT}/${name}" || { fail "could not prune remote ${name}"; return 1; }
    count=$((count + 1))
  done < <(rclone_cmd lsf --dirs-only "${remote%/}/${CLIENT}/" | sed 's#/$##' | expired_names "$days")
  ok "remote retention ${days} days: pruned ${count}"
}

mark_status() {
  local dir="$1" field="$2" value="$3" tmp
  tmp="$(mktemp "${dir}/status.XXXXXX")"
  jq --arg v "$value" ".${field} = \$v" "${dir}/status.json" > "$tmp" && mv "$tmp" "${dir}/status.json"
}

notify() {
  local severity="$1" what="$2" action="$3"
  "$(dirname "$0")/alert.sh" --root "$ROOT" --client "$CLIENT" --severity "$severity" --what "$what" --action "$action" \
    || warn "alert could not be delivered"
}

heartbeat() {
  local url cacert
  url="$(conf_get HEARTBEAT_URL "")"
  if [ -z "$url" ]; then
    warn "no heartbeat configured (HEARTBEAT_URL; Uptime Kuma push monitor in Phase 4)"
    return 0
  fi
  local tls=()
  cacert="$(conf_get HEARTBEAT_CACERT "")"
  [ -z "$cacert" ] || tls=(--cacert "$cacert")
  if curl -fsS -m 15 "${tls[@]}" -G --data-urlencode "status=up" --data-urlencode "msg=backup ok $(basename "$BACKUP_DIR")" "$url" > /dev/null; then
    ok "heartbeat sent"
  else
    fail "heartbeat failed"
    return 1
  fi
}

# finish <exit code> <reason>: heartbeat on success, alert otherwise, then exit
finish() {
  local code="$1" reason="$2"
  case "$code" in
    0)
      if ! heartbeat; then
        notify critical "Backup of ${CLIENT} finished but the heartbeat could not be sent" "Check network/Uptime Kuma; the backup itself is at ${BACKUP_DIR}"
        exit 1
      fi
      ;;
    2) notify warn "Backup of ${CLIENT} is local only: ${reason}" "Set BACKUP_REMOTE for ${CLIENT} (client.yaml backup.remote) and redeploy" ;;
    *) notify critical "Backup of ${CLIENT} failed: ${reason}" "On the host run: ${ROOT}/agent/backup.sh ${CLIENT} and read the [fail] line" ;;
  esac
  exit "$code"
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

# encrypt_database <dir>: db.dump (already checked) → db.dump.age, then the plain dump is removed
encrypt_database() {
  local dir="$1" key="${ROOT}/agent/owner.age.pub"
  [ -s "$key" ] || { fail "owner age public key missing: ${key}"; return 1; }
  age -R "$key" -o "${dir}/db.dump.age" "${dir}/db.dump" || { fail "database encryption failed"; return 1; }
  [ -s "${dir}/db.dump.age" ] || { fail "encrypted database dump is empty"; return 1; }
  rm -f "${dir}/db.dump"
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
  db_bytes="$(stat -c %s "${dir}/db.dump.age")"
  env_bytes="$(stat -c %s "${dir}/env.age")"
  printf '{"client":"%s","backup":"%s","db_bytes":%s,"env_bytes":%s,"duration_s":%s,"encrypted":true,"local":"ok"}\n' \
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
  encrypt_database "${dir}.partial" || { rm -rf "${dir}.partial"; return 1; }
  encrypt_env "${dir}.partial/env.age" || { rm -rf "${dir}.partial"; return 1; }
  cp "${ROOT}/clients/${CLIENT}/compose.yml" "${dir}.partial/compose.yml"
  write_status "${dir}.partial" "$started" "$ts"
  mv "${dir}.partial" "$dir"
  ok "backup ${CLIENT}/${ts}: db.dump.age $(stat -c %s "${dir}/db.dump.age") bytes, env.age $(stat -c %s "${dir}/env.age") bytes (both encrypted)"
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
    finish 1 "dump or encryption step failed"
  fi
  basename "$BACKUP_DIR" > "${ROOT}/backups/${CLIENT}/latest"
  local offsite=0
  copy_offsite "$BACKUP_DIR" || offsite=$?
  case "$offsite" in
    0)
      mark_status "$BACKUP_DIR" remote ok
      rclone_cmd copyto "${BACKUP_DIR}/status.json" "$(conf_get BACKUP_REMOTE "")/${CLIENT}/$(basename "$BACKUP_DIR")/status.json" || true
      ;;
    2) mark_status "$BACKUP_DIR" remote none ;;
    *) mark_status "$BACKUP_DIR" remote failed; fail "backup of ${CLIENT} is not off-server"; finish 1 "off-server copy failed" ;;
  esac
  prune_local
  prune_remote || finish 1 "remote pruning failed"
  if [ "$offsite" -eq 2 ]; then
    finish 2 "no off-server remote configured"
  fi
  ok "backup of ${CLIENT} complete (local + off-server)"
  finish 0 ""
}

main "$@"
