#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  yq -i '.monitor = {"domain": "status.example.com"}' "${REG}/hosts/local-practice.yaml"
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/validate.sh"
  source "${OPSKIT_ROOT}/lib/schema.sh"
  source "${OPSKIT_ROOT}/lib/registry.sh"
  source "${OPSKIT_ROOT}/lib/render.sh"
  source "${OPSKIT_ROOT}/lib/ssh.sh"
  source "${OPSKIT_ROOT}/lib/host.sh"
  source "${OPSKIT_ROOT}/lib/monitor.sh"
  OUT="${REG}/hosts/local-practice.monitor"
}

teardown() {
  rm -rf "$REG"
}

@test "monitor compose pins the image, uses SQLite, joins the edge network and limits memory" {
  run monitor_render local-practice
  [ "$status" -eq 0 ]
  local compose="${OUT}/compose.yml"
  [ "$(yq -r '.services.uptime-kuma.image' "$compose")" = "louislam/uptime-kuma:2.5.5" ]
  [ "$(yq -r '.services.uptime-kuma.environment.UPTIME_KUMA_DB_TYPE' "$compose")" = "sqlite" ]
  [ "$(yq -r '.services.uptime-kuma.networks.edge.aliases[0]' "$compose")" = "opskit-monitor" ]
  [ "$(yq -r '.networks.edge.name' "$compose")" = "opskit_edge" ]
  [ "$(yq -r '.services.uptime-kuma.deploy.resources.limits.memory' "$compose")" = "512m" ]
  [ "$(yq -r '.services.uptime-kuma.ports // "none"' "$compose")" = "none" ]
}

@test "image mirror, tag and memory come from the host file" {
  yq -i '.monitor.image = "mirror.gcr.io/louislam/uptime-kuma" | .monitor.tag = "2.5.4" | .monitor.memory = "768m"' "${REG}/hosts/local-practice.yaml"
  monitor_render local-practice >/dev/null
  [ "$(yq -r '.services.uptime-kuma.image' "${OUT}/compose.yml")" = "mirror.gcr.io/louislam/uptime-kuma:2.5.4" ]
  [ "$(yq -r '.services.uptime-kuma.deploy.resources.limits.memory' "${OUT}/compose.yml")" = "768m" ]
}

@test "caddy site proxies the monitor domain; internal TLS only on practice hosts" {
  monitor_render local-practice >/dev/null
  grep -qx 'status.example.com {' "${OUT}/opskit-monitor.caddy"
  grep -q 'reverse_proxy opskit-monitor:3001' "${OUT}/opskit-monitor.caddy"
  grep -q 'tls internal' "${OUT}/opskit-monitor.caddy"
  yq -i '.edge.tls = "acme"' "${REG}/hosts/local-practice.yaml"
  monitor_render local-practice >/dev/null
  ! grep -q 'tls internal' "${OUT}/opskit-monitor.caddy"
}

@test "admin password is generated once, strong, mode 600 and kept on re-render" {
  monitor_render local-practice >/dev/null
  local file="${OUT}/admin.env" first
  [ "$(stat -c %a "$file")" = "600" ]
  first="$(cat "$file")"
  grep -qE '^UK_ADMIN_PASSWORD=Uk-[0-9a-f]{32}$' "$file"
  monitor_render local-practice >/dev/null
  [ "$(cat "$file")" = "$first" ]
}

@test "a host without a monitor section is refused" {
  yq -i 'del(.monitor)' "${REG}/hosts/local-practice.yaml"
  run monitor_render local-practice
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no monitor section"* ]]
}

@test "schema rejects an unknown monitor image and a floating tag" {
  yq -i '.monitor.image = "evil/uptime-kuma"' "${REG}/hosts/local-practice.yaml"
  run "$OPSKIT" validate "${REG}/hosts/local-practice.yaml"
  [ "$status" -eq 1 ]
  yq -i '.monitor.image = "louislam/uptime-kuma" | .monitor.tag = "latest"' "${REG}/hosts/local-practice.yaml"
  run "$OPSKIT" validate "${REG}/hosts/local-practice.yaml"
  [ "$status" -eq 1 ]
}

@test "monitor command needs a host" {
  run "$OPSKIT" monitor deploy
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: opskit monitor"* ]]
}
