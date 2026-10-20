#!/usr/bin/env bats

load helpers/common
load helpers/mock_http

setup() {
  ROOT="$(mktemp -d)"
  STUB="$(mktemp -d)"
  mkdir -p "${ROOT}/agent" "${ROOT}/clients/acme" "${STUB}/proc"
  cp "${OPSKIT_ROOT}/agent/alert.sh" "${OPSKIT_ROOT}/agent/health.sh" "${ROOT}/agent/"
  cp -r "${OPSKIT_ROOT}/templates/alerts" "${ROOT}/agent/alerts"
  HEALTH="${ROOT}/agent/health.sh"
  start_mock_http
  export OPSKIT_TELEGRAM_API="$MOCK_URL" OPSKIT_PROC="${STUB}/proc"
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' > "${ROOT}/agent/alerts.conf"
  printf 'APP_URL=https://auto.acme.com\nTLS_MODE=acme\n' > "${ROOT}/clients/acme/alerts.conf"
  set_disk 40
  set_memory 8000000 4000000
  set_containers "acme-app-1 0 running" "acme-worker-1 0 running" "acme-postgres-1 0 running"
  set_cert_days 60
  cat > "${STUB}/df" <<'SH'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 100 50 50 %s%% /\n' "$(cat "$(dirname "$0")/disk")"
SH
  cat > "${STUB}/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  ps) awk '{ print $1 }' "$(dirname "$0")/containers" ;;
  inspect) shift 3; for n in "$@"; do awk -v n="$n" '$1 == n { print "/" $1, $2, $3 }' "$(dirname "$0")/containers"; done ;;
esac
SH
  cat > "${STUB}/openssl" <<'SH'
#!/usr/bin/env bash
dir="$(dirname "$0")"
case "$1" in
  s_client) cat >/dev/null; [ -s "${dir}/cert" ] && echo "-----BEGIN CERTIFICATE-----" ;;
  x509) cat >/dev/null; [ -s "${dir}/cert" ] && echo "notAfter=$(cat "${dir}/cert")" ;;
esac
SH
  chmod +x "${STUB}/df" "${STUB}/docker" "${STUB}/openssl"
  export PATH="${STUB}:${PATH}"
}

teardown() {
  stop_mock_http
  rm -rf "$ROOT" "$STUB"
}

set_disk() { echo "$1" > "${STUB}/disk"; }
set_memory() { printf 'MemTotal: %s kB\nMemAvailable: %s kB\n' "$1" "$2" > "${STUB}/proc/meminfo"; }
set_containers() { printf '%s\n' "$@" > "${STUB}/containers"; }
set_cert_days() { date -u -d "+$1 days" '+%b %e %H:%M:%S %Y GMT' > "${STUB}/cert"; }

texts() {
  mock_requests | jq -r .body | jq -r .text
}

@test "a healthy host sends nothing" {
  run "$HEALTH" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"host healthy"* ]]
  [ "$(mock_requests | jq -s length)" = "0" ]
}

@test "disk over 85% warns once per 24 h, over 95% is critical, then one recovered message" {
  set_disk 90
  "$HEALTH" acme --root "$ROOT" >/dev/null
  "$HEALTH" acme --root "$ROOT" >/dev/null
  [ "$(texts | grep -c '^\[WARN\] acme on .*: Disk 90% full')" -eq 1 ]
  set_disk 97
  "$HEALTH" acme --root "$ROOT" >/dev/null
  texts | grep -q '^\[CRITICAL\] acme on .*: Disk almost full: 97% used'
  set_disk 50
  "$HEALTH" acme --root "$ROOT" >/dev/null
  "$HEALTH" acme --root "$ROOT" >/dev/null
  [ "$(texts | grep -c 'Recovered: disk usage is below 85%')" -eq 1 ]
}

@test "the disk warning repeats after 24 h if still true" {
  set_disk 90
  OPSKIT_NOW="$(date +%s)" "$HEALTH" acme --root "$ROOT" >/dev/null
  OPSKIT_NOW="$(( $(date +%s) + 86400 + 60 ))" "$HEALTH" acme --root "$ROOT" >/dev/null
  [ "$(texts | grep -c 'Disk 90% full')" -eq 2 ]
}

@test "low memory warns" {
  set_memory 8000000 400000
  "$HEALTH" acme --root "$ROOT" >/dev/null
  texts | grep -q 'Low memory: 5% available'
}

@test "a restarted container warns; the first run only sets the baseline" {
  set_containers "acme-app-1 3 running" "acme-worker-1 0 running"
  "$HEALTH" acme --root "$ROOT" >/dev/null
  [ "$(mock_requests | jq -s length)" = "0" ]
  set_containers "acme-app-1 5 running" "acme-worker-1 0 running"
  "$HEALTH" acme --root "$ROOT" >/dev/null
  texts | grep -q 'Container acme-app-1 restarted 2 time(s) in the last hour'
  [ "$(mock_requests | jq -s length)" = "1" ]
}

@test "a stopped container is critical" {
  set_containers "acme-app-1 0 running" "acme-worker-1 0 exited"
  "$HEALTH" acme --root "$ROOT" >/dev/null
  texts | grep -q '^\[CRITICAL\] .*Containers not running: acme-worker-1 (exited)'
}

@test "certificate expiry: < 14 days warns, < 3 days is critical, unreadable is critical" {
  set_cert_days 10
  "$HEALTH" acme --root "$ROOT" >/dev/null
  texts | grep -q '^\[WARN\] .*certificate of auto.acme.com expires in 9 days\|^\[WARN\] .*certificate of auto.acme.com expires in 10 days'
  set_cert_days 1
  "$HEALTH" acme --root "$ROOT" >/dev/null
  texts | grep -q '^\[CRITICAL\] .*certificate of auto.acme.com expires in'
  : > "${STUB}/cert"
  "$HEALTH" acme --root "$ROOT" >/dev/null
  texts | grep -q 'could not be read'
}

@test "practice hosts with internal TLS skip the certificate check" {
  printf 'APP_URL=https://acme.localhost:18443\nTLS_MODE=internal\n' > "${ROOT}/clients/acme/alerts.conf"
  : > "${STUB}/cert"
  run "$HEALTH" acme --root "$ROOT"
  [[ "$output" == *"host healthy"* ]]
}

@test "health needs a client id" {
  run "${OPSKIT_ROOT}/agent/health.sh" --root "$ROOT"
  [ "$status" -eq 1 ]
}
