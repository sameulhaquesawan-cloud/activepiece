#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client demo
  OUT="${REG}/clients/demo/rendered"
}

teardown() {
  rm -rf "$REG"
}

render() {
  run "$OPSKIT" render demo
  [ "$status" -eq 0 ]
}

compose_get() {
  yq -r "$1" "${OUT}/compose.yml"
}

@test "image is pinned to the client's tag and AP_EDITION=ce, telemetry off" {
  render
  [ "$(compose_get .services.app.image)" = "ghcr.io/activepieces/activepieces:0.92.3" ]
  [ "$(compose_get .services.worker.image)" = "ghcr.io/activepieces/activepieces:0.92.3" ]
  grep -qx 'AP_EDITION=ce' "${OUT}/.env"
  grep -qx 'AP_TELEMETRY_ENABLED=false' "${OUT}/.env"
}

@test "worker talks to the app internally; app uses the public URL" {
  render
  [ "$(compose_get .services.worker.environment.AP_FRONTEND_URL)" = "http://app" ]
  grep -qx 'AP_FRONTEND_URL=https://demo.localhost:18443' "${OUT}/.env"
}

@test "public URL has no port on a standard 443 edge" {
  yq -i '.edge.https_port = 443' "${REG}/hosts/local-practice.yaml"
  render
  grep -qx 'AP_FRONTEND_URL=https://demo.localhost' "${OUT}/.env"
}

@test "worker replicas and memory limits come from client.yaml" {
  yq -i '.workers.replicas = 3 | .workers.memory_limit = "2g" | .app.memory_limit = "1536m"' "${REG}/clients/demo/client.yaml"
  render
  [ "$(compose_get .services.worker.deploy.replicas)" = "3" ]
  [ "$(compose_get .services.worker.deploy.resources.limits.memory)" = "2g" ]
  [ "$(compose_get .services.app.deploy.resources.limits.memory)" = "1536m" ]
  [ "$(compose_get .services.postgres.deploy.resources.limits.memory)" = "1g" ]
  [ "$(compose_get .services.redis.deploy.resources.limits.memory)" = "256m" ]
}

@test "no service publishes ports and none has a fixed container_name" {
  render
  [ "$(compose_get '[.services[] | select(has("ports"))] | length')" = "0" ]
  [ "$(compose_get '[.services[] | select(has("container_name"))] | length')" = "0" ]
}

@test "project name, named volumes and the shared edge network" {
  render
  [ "$(compose_get .name)" = "demo" ]
  [ "$(compose_get '.volumes | keys | join(",")')" = "postgres,redis,cache" ]
  [ "$(compose_get .networks.edge.name)" = "opskit_edge" ]
  [ "$(compose_get '.services.app.networks.edge.aliases[0]')" = "demo-app" ]
  [ "$(compose_get '.services.postgres | has("networks")')" = "false" ]
}

@test "healthchecks on postgres and redis; app waits for them" {
  render
  [ "$(compose_get '.services.postgres.healthcheck.test[0]')" = "CMD-SHELL" ]
  [ "$(compose_get '.services.redis.healthcheck.test[1]')" = "redis-cli" ]
  [ "$(compose_get .services.app.depends_on.postgres.condition)" = "service_healthy" ]
}

@test ".env is mode 600 and secrets never land in compose.yml or the Caddy file" {
  render
  [ "$(stat -c %a "${OUT}/.env")" = "600" ]
  local key
  key="$(sed -n 's/^AP_ENCRYPTION_KEY=//p' "${OUT}/.env")"
  [[ "$key" =~ ^[0-9a-f]{32}$ ]]
  ! grep -q "$key" "${OUT}/compose.yml" "${OUT}/demo.caddy" "${OUT}/cron"
  [[ "$output" != *"$key"* ]]
}

@test "app webhook secrets are empty by default" {
  render
  grep -qx "AP_APP_WEBHOOK_SECRETS='{}'" "${OUT}/.env"
}

@test "the Facebook Lead Ads app secret comes from channels.env, never from client.yaml" {
  yq -i '.app_webhooks.facebook_leads.secret = "META_APP_SECRET"' "${REG}/clients/demo/client.yaml"
  run "$OPSKIT" render demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"META_APP_SECRET is missing or not a Meta app secret"* ]]
  local secret
  secret="$(openssl rand -hex 16)"
  printf 'META_APP_SECRET=%s\n' "$secret" > "${REG}/clients/demo/channels.env"
  render
  grep -qxF "AP_APP_WEBHOOK_SECRETS='{\"@activepieces/piece-facebook-leads\":{\"webhookSecret\":\"${secret}\"}}'" "${OUT}/.env"
  ! grep -q "$secret" "${OUT}/compose.yml" "${REG}/clients/demo/client.yaml"
  [[ "$output" != *"$secret"* ]]
}

@test "re-render keeps the same secrets" {
  render
  local before
  before="$(sha256sum "${OUT}/.env")"
  render
  [ "$(sha256sum "${OUT}/.env")" = "$before" ]
}

@test "caddy site uses internal TLS on practice hosts and ACME otherwise" {
  render
  grep -q 'tls internal' "${OUT}/demo.caddy"
  grep -q 'reverse_proxy demo-app:80' "${OUT}/demo.caddy"
  yq -i '.edge.tls = "acme"' "${REG}/hosts/local-practice.yaml"
  render
  ! grep -q 'tls internal' "${OUT}/demo.caddy"
}

@test "IPv4 shim only when the host asks for it" {
  render
  [ ! -e "${OUT}/compose.practice.yml" ]
  yq -i '.practice_quirks.ipv4_listen_shim = true' "${REG}/hosts/local-practice.yaml"
  render
  [ -f "${OUT}/compose.practice.yml" ]
  [ -f "${OUT}/ipv4-shim.js" ]
  [[ "$output" == *"practice-only IPv4 shim"* ]]
}

@test "invalid client.yaml stops the render" {
  yq -i '.workers.replicas = 0' "${REG}/clients/demo/client.yaml"
  run "$OPSKIT" render demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"workers.replicas: must be >= 1"* ]]
  [ ! -e "${OUT}/compose.yml" ]
}

# bats test_tags=docker
@test "docker compose reads the app webhook secrets JSON intact" {
  yq -i '.app_webhooks.facebook_leads.secret = "META_APP_SECRET"' "${REG}/clients/demo/client.yaml"
  printf 'META_APP_SECRET=%s\n' "0123456789abcdef0123456789abcdef" > "${REG}/clients/demo/channels.env"
  render
  run docker compose -p demo --project-directory "$OUT" -f "${OUT}/compose.yml" config --format json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.services.app.environment.AP_APP_WEBHOOK_SECRETS | fromjson | .["@activepieces/piece-facebook-leads"].webhookSecret' <<< "$output")" = "0123456789abcdef0123456789abcdef" ]
}

@test "rendered compose is valid for docker compose" {
  command -v docker >/dev/null || skip "docker not installed"
  render
  run docker compose -f "${OUT}/compose.yml" config -q
  [ "$status" -eq 0 ]
}
