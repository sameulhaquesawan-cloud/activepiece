#!/usr/bin/env bats

load helpers/common

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
}

teardown_file() {
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/practice.sh"
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
