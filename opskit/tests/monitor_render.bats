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
  source "${OPSKIT_ROOT}/lib/stack.sh"
  source "${OPSKIT_ROOT}/lib/monitor_sync.sh"
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

@test "the monitoring host is the single host with a monitor section" {
  [ "$(monitor_host_for)" = "local-practice" ]
  yq '.host_id = "second"' "${REG}/hosts/local-practice.yaml" > "${REG}/hosts/second.yaml"
  run monitor_host_for
  [ "$status" -eq 1 ]
  [[ "$output" == *"several monitoring hosts"* ]]
  [ "$(OPSKIT_MONITOR_HOST=second monitor_host_for)" = "second" ]
  rm "${REG}/hosts/second.yaml"
  yq -i 'del(.monitor)' "${REG}/hosts/local-practice.yaml"
  run monitor_host_for
  [ "$status" -eq 1 ]
  [[ "$output" == *"no monitoring host"* ]]
}

@test "clients are checked over public HTTPS; practice clients over the edge network" {
  new_demo_client demo auto.acme.com
  [ "$(monitor_client_url demo)" = "http://demo-app/api/v1/health" ]
  yq -i '.edge.tls = "acme" | .edge.https_port = 443' "${REG}/hosts/local-practice.yaml"
  [ "$(monitor_client_url demo)" = "https://auto.acme.com/api/v1/health" ]
}

@test "Uptime Kuma notifies the owner's Telegram, else the owner webhook, else refuses" {
  mkdir -p "${REG}/owner"
  printf 'WEBHOOK_URL=https://hooks.example.com/x\n' > "${REG}/owner/alerts.conf"
  [ "$(monitor_owner_notification | jq -r .type)" = "webhook" ]
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' >> "${REG}/owner/alerts.conf"
  local n
  n="$(monitor_owner_notification)"
  [ "$(jq -r .type <<< "$n")" = "telegram" ]
  [ "$(jq -r .telegramChatID <<< "$n")" = "111" ]
  [ "$(jq -r .telegramServerUrl <<< "$n")" = "https://api.telegram.org" ]
  rm "${REG}/owner/alerts.conf"
  run monitor_owner_notification
  [ "$status" -eq 1 ]
}

@test "sync input asks for a 60 s uptime check and a 26 h backup window by default" {
  new_demo_client demo auto.acme.com
  mkdir -p "${REG}/owner" "${OUT}"
  printf 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=111\n' > "${REG}/owner/alerts.conf"
  monitor_admin_secrets local-practice
  local input
  input="$(monitor_sync_input demo local-practice)"
  [ "$(jq -r '.monitors[] | select(.type == "http") | "\(.name) \(.interval) \(.url)"' <<< "$input")" = "demo uptime 60 http://demo-app/api/v1/health" ]
  [ "$(jq -r '.monitors[] | select(.type == "push") | "\(.name) \(.interval)"' <<< "$input")" = "demo backup 93600" ]
  [ "$(jq -r .admin.username <<< "$input")" = "opskit" ]
}

@test "practice clients get Caddy's local CA for the backup heartbeat" {
  new_demo_client demo
  "$OPSKIT" render demo >/dev/null
  grep -qx "HEARTBEAT_CACERT=$(yq -r '.opskit_root // "/opt/opskit"' "${REG}/hosts/local-practice.yaml")/caddy/data/caddy/pki/authorities/local/root.crt" \
    "${REG}/clients/demo/rendered/backup.conf"
  yq -i '.edge.tls = "acme"' "${REG}/hosts/local-practice.yaml"
  "$OPSKIT" render demo >/dev/null
  ! grep -q HEARTBEAT_CACERT "${REG}/clients/demo/rendered/backup.conf"
}
