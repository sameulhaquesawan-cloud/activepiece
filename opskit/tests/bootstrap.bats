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
  stub_tool docker 'exit 1'
  stub_tool iptables 'exit 1'
  PATH="${WORK}/stub:${PATH}" run bash "$BOOTSTRAP" --ssh-user ops --dry-run
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
  grep -q -- "-- sudo -n bash /tmp/opskit-bootstrap.sh --ssh-user ops --root /opt/opskit --http-port 80 --https-port 443 --tls acme --edge-name opskit-caddy --email ops@acme.example.com --firewall ufw --dry-run" "${WORK}/calls"
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

stub_tool() {
  mkdir -p "${WORK}/stub"
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "${WORK}/stub/$1"
  chmod +x "${WORK}/stub/$1"
}

oracle_rules() {
  cat <<'RULES'
-P INPUT ACCEPT
-N InstanceServices
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
RULES
}

@test "existing Docker install is kept, not replaced by docker.io" {
  stub_tool docker 'exit 0'
  PATH="${WORK}/stub:${PATH}" run bash "$BOOTSTRAP" --ssh-user ops --dry-run
  [[ "$output" == *"[ok] docker: existing install kept"* ]]
  [[ "$output" != *"docker.io"* ]]
  [[ "$output" != *"docker-compose-v2"* ]]
  [[ "$output" == *"ufw unattended-upgrades curl age rclone"* ]]
}

@test "firewall keep: iptables with ssh, 80, 443 and a final reject is accepted, no ufw" {
  stub_tool docker 'exit 0'
  stub_tool iptables "cat <<'R'
$(oracle_rules)
R"
  stub_tool sshd "printf 'port 22\\npasswordauthentication no\\npermitrootlogin no\\n'"
  PATH="${WORK}/stub:${PATH}" run bash "$BOOTSTRAP" --ssh-user ops --firewall keep --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] firewall: existing iptables kept (22/tcp, 80/tcp, 443/tcp open, rest rejected)"* ]]
  [[ "$output" != *"ufw"* ]]
}

@test "firewall keep: iptables without 443 or without a final reject fails" {
  stub_tool docker 'exit 0'
  stub_tool iptables "cat <<'R'
$(oracle_rules | grep -v 'dport 443')
R"
  PATH="${WORK}/stub:${PATH}" run bash "$BOOTSTRAP" --ssh-user ops --firewall keep --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] firewall: iptables does not allow 443/tcp"* ]]
  stub_tool iptables "cat <<'R'
$(oracle_rules | grep -v REJECT)
R"
  PATH="${WORK}/stub:${PATH}" run bash "$BOOTSTRAP" --ssh-user ops --firewall keep --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] firewall: iptables INPUT does not reject other traffic"* ]]
}

@test "firewall ufw is refused on an Oracle image with its own iptables rules" {
  stub_tool docker 'exit 0'
  stub_tool iptables "cat <<'R'
$(oracle_rules)
R"
  PATH="${WORK}/stub:${PATH}" run bash "$BOOTSTRAP" --ssh-user ops --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] firewall: Oracle image iptables rules found; use firewall: keep"* ]]
  [[ "$output" != *"[plan] ufw --force enable"* ]]
}

@test "swap size forces a swapfile even with more than 4 GB RAM" {
  stub_tool docker 'exit 0'
  stub_tool swapon 'exit 0'
  PATH="${WORK}/stub:${PATH}" run bash "$BOOTSTRAP" --ssh-user ops --swap 2G --dry-run
  [[ "$output" == *"[plan] fallocate -l 2G /swapfile"* ]]
  [[ "$output" == *"[ok] swap: 2G /swapfile"* ]]
  run bash "$BOOTSTRAP" --edge-only --swap lots --dry-run
  [ "$status" -eq 1 ]
}

@test "edge joins extra Docker networks; bad network names are refused" {
  run bash "$BOOTSTRAP" --edge-only --edge-join anythingllm-oracle_anything-llm --edge-join other.net --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plan] docker network connect anythingllm-oracle_anything-llm opskit-caddy (if not joined)"* ]]
  [[ "$output" == *"[plan] docker network connect other.net opskit-caddy (if not joined)"* ]]
  run bash "$BOOTSTRAP" --edge-only --edge-join 'bad name;rm' --dry-run
  [ "$status" -eq 1 ]
}

@test "ssh host: firewall, swap and edge networks come from the host yaml" {
  yq -i '.firewall = "keep" | .swap = "2G" | .edge.join_networks = ["anythingllm-oracle_anything-llm"]' "${REG}/hosts/vps-acme.yaml"
  local stub="${WORK}/stub"
  mkdir -p "$stub"
  for tool in ssh scp; do
    printf '#!/usr/bin/env bash\nprintf "%%s " "%s" "$@" >> "%s/calls"\necho >> "%s/calls"\n' "$tool" "$WORK" "$WORK" > "${stub}/${tool}"
    chmod +x "${stub}/${tool}"
  done
  PATH="${stub}:${PATH}" run "$OPSKIT" host bootstrap vps-acme --dry-run
  [ "$status" -eq 0 ]
  grep -q -- "--edge-name opskit-caddy --email ops@acme.example.com --firewall keep --swap 2G --edge-join anythingllm-oracle_anything-llm --dry-run" "${WORK}/calls"
}

@test "host yaml with an unknown firewall mode or bad swap size is refused" {
  yq -i '.firewall = "none"' "${REG}/hosts/vps-acme.yaml"
  run "$OPSKIT" host bootstrap vps-acme --dry-run
  [ "$status" -ne 0 ]
  yq -i '.firewall = "keep" | .swap = "2 GB"' "${REG}/hosts/vps-acme.yaml"
  run "$OPSKIT" host bootstrap vps-acme --dry-run
  [ "$status" -ne 0 ]
}
