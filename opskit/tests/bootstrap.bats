#!/usr/bin/env bats

load helpers/common
load helpers/registry

BOOTSTRAP="${BATS_TEST_DIRNAME}/../agent/bootstrap.sh"

setup() {
  make_registry
  WORK="$(mktemp -d)"
  cat > "${REG}/hosts/vps-acme.yaml" <<'EOF'
host_id: vps-acme
ip: 203.0.113.10
ssh_user: ops
mode: dedicated
cpus: 2
ram_gb: 4
edge: { tls: acme, acme_email: ops@acme.example.com }
EOF
}

teardown() {
  if [ -n "${EDGE:-}" ]; then
    docker rm -f "$EDGE" >/dev/null 2>&1 || true
    docker run --rm -v "${WORK}:/work" --entrypoint sh caddy:2.10.0 -c 'rm -rf /work/root/caddy' >/dev/null 2>&1 || true
  fi
  rm -rf "$REG" "$WORK"
}

@test "full plan opens only ssh, 80 and 443 and installs the basics" {
  run bash "$BOOTSTRAP" --ssh-user ops --dry-run
  [[ "$output" == *"[plan] ufw default deny incoming"* ]]
  [[ "$output" == *"[plan] ufw allow 80/tcp"* ]]
  [[ "$output" == *"[plan] ufw allow 443/tcp"* ]]
  [[ "$output" == *"docker.io docker-compose-v2 ufw unattended-upgrades"* ]]
  [[ "$output" == *"[plan] usermod -aG docker ops"* ]]
  [[ "$output" == *"caddy:2.10.0"* ]]
}

@test "root or missing ssh user is refused" {
  run bash "$BOOTSTRAP" --ssh-user root --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"--ssh-user (non-root) is required"* ]]
  run bash "$BOOTSTRAP" --dry-run
  [ "$status" -eq 1 ]
}

@test "bad options are refused" {
  run bash "$BOOTSTRAP" --edge-only --tls selfsigned --dry-run
  [ "$status" -eq 1 ]
  run bash "$BOOTSTRAP" --edge-only --root relative/path --dry-run
  [ "$status" -eq 1 ]
}

@test "ssh host: script is copied and run with sudo -n and the host's edge settings" {
  local stub="${WORK}/stub"
  mkdir -p "$stub"
  for tool in ssh scp; do
    printf '#!/usr/bin/env bash\nprintf "%%s " "%s" "$@" >> "%s/calls"\necho >> "%s/calls"\n' "$tool" "$WORK" "$WORK" > "${stub}/${tool}"
    chmod +x "${stub}/${tool}"
  done
  PATH="${stub}:${PATH}" run "$OPSKIT" host bootstrap vps-acme --dry-run
  [ "$status" -eq 0 ]
  grep -q "scp .*bootstrap.sh ops@203.0.113.10:/tmp/opskit-bootstrap.sh" "${WORK}/calls"
  grep -q -- "-- sudo -n bash /tmp/opskit-bootstrap.sh --ssh-user ops --root /opt/opskit --http-port 80 --https-port 443 --tls acme --edge-name opskit-caddy --email ops@acme.example.com --dry-run" "${WORK}/calls"
}

# bats test_tags=docker
@test "local edge: Caddy starts, serves an internal-TLS site, and re-running is idempotent" {
  EDGE="opskit-caddy-bats"
  yq -i ".opskit_root = \"${WORK}/root\" | .edge.http_port = 28080 | .edge.https_port = 28443 | .edge.container = \"${EDGE}\"" "${REG}/hosts/local-practice.yaml"
  run "$OPSKIT" host bootstrap local-practice
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] edge: ${EDGE}"* ]]
  printf 'edge.localhost {\n\ttls internal\n\trespond "edge-ok"\n}\n' > "${WORK}/root/caddy/etc/sites/test.caddy"
  docker exec "$EDGE" caddy reload --config /etc/caddy/Caddyfile
  local id
  id="$(docker inspect -f '{{.Id}}' "$EDGE")"
  run "$OPSKIT" host bootstrap local-practice
  [ "$status" -eq 0 ]
  [ "$(docker inspect -f '{{.Id}}' "$EDGE")" = "$id" ]
  run curl -sk --noproxy '*' --retry 5 --retry-connrefused --resolve edge.localhost:28443:127.0.0.1 https://edge.localhost:28443/
  [ "$output" = "edge-ok" ]
}
