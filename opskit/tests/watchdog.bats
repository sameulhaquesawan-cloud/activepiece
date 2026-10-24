#!/usr/bin/env bats

load helpers/common
load helpers/mock_http

setup() {
  ROOT="$(mktemp -d)"
  STUB="$(mktemp -d)"
  mkdir -p "${ROOT}/agent" "${ROOT}/clients/acme"
  cp "${OPSKIT_ROOT}/agent/alert.sh" "${OPSKIT_ROOT}/agent/watchdog.sh" "${ROOT}/agent/"
  cp -r "${OPSKIT_ROOT}/templates/alerts" "${ROOT}/agent/alerts"
  WATCHDOG="${ROOT}/agent/watchdog.sh"
  start_mock_http
  export OPSKIT_TELEGRAM_API="$MOCK_URL"
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' > "${ROOT}/agent/alerts.conf"
  set_containers "acme-app-1 healthy 60" "acme-worker-1 healthy 60" "acme-postgres-1 healthy 60" "acme-redis-1 none 60"
  cat > "${STUB}/docker" <<'SH'
#!/usr/bin/env bash
dir="$(dirname "$0")"
case "$1" in
  ps) awk '{ print $1 }' "${dir}/containers" ;;
  inspect) shift 3; for n in "$@"; do awk -v n="$n" '$1 == n { print "/" $1, $2, $3 }' "${dir}/containers"; done ;;
  restart) echo "$2" >> "${dir}/restarted" ;;
esac
SH
  chmod +x "${STUB}/docker"
  export PATH="${STUB}:${PATH}"
}

teardown() {
  stop_mock_http
  rm -rf "$ROOT" "$STUB"
}

# set_containers "<name> <health> <minutes since start>" ...
set_containers() {
  local spec name health minutes
  : > "${STUB}/containers"
  for spec in "$@"; do
    read -r name health minutes <<< "$spec"
    printf '%s %s %s\n' "$name" "$health" "$(date -u -d "-${minutes} minutes" +%Y-%m-%dT%H:%M:%S.000000000Z)" >> "${STUB}/containers"
  done
}

texts() {
  mock_requests | jq -r .body | jq -r .text
}

@test "healthy containers are left alone and nothing is sent" {
  run "$WATCHDOG" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] acme: no unhealthy containers"* ]]
  [ ! -e "${STUB}/restarted" ]
  [ "$(mock_requests | jq -s length)" = "0" ]
}

@test "an unhealthy app running for more than 10 minutes is restarted with a critical alert" {
  set_containers "acme-app-1 unhealthy 25" "acme-worker-1 healthy 25"
  run "$WATCHDOG" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(cat "${STUB}/restarted")" = "acme-app-1" ]
  [[ "$output" == *"[warn] acme: restarted unhealthy container acme-app-1"* ]]
  texts | grep -q '^\[CRITICAL\] acme on .*: Container acme-app-1 stopped answering its health check and was restarted'
  texts | grep -q 'docker logs --tail 200 acme-app-1'
}

@test "a container unhealthy within 10 minutes of its start is not restarted (migrations, first start)" {
  set_containers "acme-app-1 unhealthy 4"
  run "$WATCHDOG" acme --root "$ROOT"
  [ "$status" -eq 0 ]
  [ ! -e "${STUB}/restarted" ]
  [[ "$output" == *"acme-app-1 unhealthy but started less than 10 min ago; not restarting yet"* ]]
}

@test "after 3 restarts in 6 hours it stops restarting and says the container keeps hanging" {
  set_containers "acme-app-1 unhealthy 25"
  local i
  for i in 1 2 3; do
    "$WATCHDOG" acme --root "$ROOT" >/dev/null
  done
  [ "$(wc -l < "${STUB}/restarted")" -eq 3 ]
  run "$WATCHDOG" acme --root "$ROOT"
  [ "$(wc -l < "${STUB}/restarted")" -eq 3 ]
  [[ "$output" == *"[fail] acme: acme-app-1 restarted 3 times in 6 h; not restarting again"* ]]
  texts | grep -q '^\[CRITICAL\] acme on .*: Container acme-app-1 keeps hanging: restarted 3 times in 6 hours'
}

@test "restarts older than 6 hours no longer count" {
  set_containers "acme-app-1 unhealthy 25"
  mkdir -p "${ROOT}/state/acme/watchdog"
  local old
  old="$(( $(date +%s) - 7 * 3600 ))"
  printf '%s\n%s\n%s\n' "$old" "$old" "$old" > "${ROOT}/state/acme/watchdog/acme-app-1.restarts"
  run "$WATCHDOG" acme --root "$ROOT"
  [ "$(cat "${STUB}/restarted")" = "acme-app-1" ]
}

@test "bad client id is refused" {
  run "$WATCHDOG" 'Bad;id' --root "$ROOT"
  [ "$status" -eq 1 ]
}
