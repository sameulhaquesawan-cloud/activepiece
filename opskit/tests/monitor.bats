#!/usr/bin/env bats

load helpers/common
load helpers/mock_http

setup_file() {
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/practice.sh"
  export MON_DIR MON_ROOT MON_EDGE OPSKIT_REGISTRY
  MON_DIR="$(mktemp -d)"
  MON_ROOT="${MON_DIR}/host-root"
  MON_EDGE="opskit-caddy-montest-$$"
  OPSKIT_REGISTRY="$MON_DIR"
  practice_host_write "$MON_DIR" monhost "$MON_ROOT" "$MON_EDGE" >/dev/null
  yq -i '.monitor = {"domain": "status.localhost", "image": "mirror.gcr.io/louislam/uptime-kuma"}' "${MON_DIR}/hosts/monhost.yaml"
  "$OPSKIT" host bootstrap monhost >/dev/null
  "$OPSKIT" monitor deploy monhost > "${MON_DIR}/deploy.log" 2>&1 || true
  export MOCK_BIND=0.0.0.0 MOCK_DIR MOCK_PID MOCK_URL OPSKIT_TELEGRAM_API MON_APP="mon-acme-app-$$"
  start_mock_http
  OPSKIT_TELEGRAM_API="http://$(docker network inspect opskit_edge -f '{{(index .IPAM.Config 0).Gateway}}'):${MOCK_URL##*:}"
  mkdir -p "${MON_DIR}/owner"
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' > "${MON_DIR}/owner/alerts.conf"
  "$OPSKIT" client new acme --domain acme.localhost --host monhost --contact ops@example.com >/dev/null
  docker run -d --name "$MON_APP" --network opskit_edge --network-alias acme-app caddy:2.10.0 \
    caddy respond --listen :80 --body ok >/dev/null
}

teardown_file() {
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/practice.sh"
  docker rm -f "$MON_APP" >/dev/null 2>&1 || true
  stop_mock_http
  docker compose -p opskit-monitor --project-directory "${MON_ROOT}/monitor" -f "${MON_ROOT}/monitor/compose.yml" down -v >/dev/null 2>&1 || true
  practice_teardown "$MON_ROOT" "$MON_EDGE"
  practice_remove_tree "$MON_DIR"
}

# bats test_tags=docker
@test "monitor deploy runs Uptime Kuma behind the edge with an admin account" {
  run cat "${MON_DIR}/deploy.log"
  [[ "$output" == *"[ok] Uptime Kuma admin account ready"* ]]
  [[ "$output" == *"[ok] Uptime Kuma answers on https://status.localhost:"* ]]
  [ -z "$(docker port "$(docker ps -qf label=com.docker.compose.project=opskit-monitor)")" ]
}

# bats test_tags=docker
@test "monitor deploy is idempotent (same container, same admin)" {
  local before after
  before="$(docker ps -qf label=com.docker.compose.project=opskit-monitor)"
  run "$OPSKIT" monitor deploy monhost
  [ "$status" -eq 0 ]
  [[ "$output" == *"admin account ready"* ]]
  after="$(docker ps -qf label=com.docker.compose.project=opskit-monitor)"
  [ "$before" = "$after" ]
}

wait_for_message() {
  local pattern="$1" _
  for _ in $(seq 1 36); do
    mock_requests | jq -r '.body | fromjson? | .text // empty' | grep -qF "$pattern" && return 0
    sleep 5
  done
  mock_requests | jq -r '.body' >&2
  return 1
}

# bats test_tags=docker
@test "monitor sync creates the uptime and 26 h backup monitors and saves the push URL; re-sync keeps it" {
  run "$OPSKIT" monitor sync acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"uptime every 60 s (http://acme-app/api/v1/health), backup watchdog window 26 h"* ]]
  local url
  url="$(yq -r .backup.heartbeat_url "${MON_DIR}/clients/acme/client.yaml")"
  [[ "$url" =~ ^https://status\.localhost:[0-9]+/api/push/[A-Za-z0-9_-]{32}$ ]]
  grep -qx "HEARTBEAT_URL=${url}" "${MON_DIR}/clients/acme/rendered/backup.conf"
  run "$OPSKIT" monitor sync acme
  [ "$status" -eq 0 ]
  [ "$(yq -r .backup.heartbeat_url "${MON_DIR}/clients/acme/client.yaml")" = "$url" ]
}

# bats test_tags=docker
@test "stopping the client app sends the owner an uptime alert from Uptime Kuma" {
  OPSKIT_MONITOR_INTERVAL=20 "$OPSKIT" monitor sync acme >/dev/null
  docker stop "$MON_APP" >/dev/null
  wait_for_message "[acme uptime] [🔴 Down]"
  [ "$(mock_requests | jq -r .path | sort -u)" = "/bot123:abc/sendMessage" ]
  docker start "$MON_APP" >/dev/null
}

# bats test_tags=docker
@test "a missed backup heartbeat triggers the watchdog (time-shifted: 20 s window)" {
  OPSKIT_MONITOR_INTERVAL=20 OPSKIT_MONITOR_PUSH_INTERVAL=20 "$OPSKIT" monitor sync acme >/dev/null
  curl -fsS --cacert "${MON_ROOT}/caddy/data/caddy/pki/authorities/local/root.crt" \
    "$(yq -r .backup.heartbeat_url "${MON_DIR}/clients/acme/client.yaml")?status=up&msg=test" | grep -q '"ok":true'
  wait_for_message "[acme backup] [🔴 Down] No heartbeat in the time window"
  OPSKIT_MONITOR_INTERVAL=60 "$OPSKIT" monitor sync acme | grep -q "backup watchdog window 26 h"
}

# bats test_tags=docker
@test "monitor remove deletes the client's monitors and is safe to repeat" {
  "$OPSKIT" monitor sync acme >/dev/null
  run "$OPSKIT" monitor remove acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"monitors removed for acme: acme uptime, acme backup"* ]]
  run "$OPSKIT" monitor remove acme
  [[ "$output" == *"monitors removed for acme: none"* ]]
}
