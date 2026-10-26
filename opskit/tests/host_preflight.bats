#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  STUB="$(mktemp -d)"
  cat > "${REG}/hosts/vps-acme.yaml" <<'EOF'
host_id: vps-acme
ip: 203.0.113.10
ssh_user: ops
mode: dedicated
cpus: 2
ram_gb: 2
edge: { tls: acme, acme_email: ops@acme.example.com }
monitor: { domain: status.acme.example.com }
EOF
  "$OPSKIT" client new acme --domain auto.acme.example.com --host vps-acme --contact ops@example.com >/dev/null
  stub ssh 'eval "${@: -1}"'
  stub sudo '[ "$1" = "-n" ] && shift; "$@"'
  stub curl 'exit 0'
  stub docker 'echo "Docker version 29.8.0"'
  stub crontab 'exit 0'
  stub getent 'case "$2" in auto.acme.example.com|status.acme.example.com) echo "203.0.113.10 STREAM $2";; wrong.example.com) echo "198.51.100.7 STREAM $2";; esac'
  for lib in log validate schema registry render secrets stack ssh host deploy preflight; do
    source "${OPSKIT_ROOT}/lib/${lib}.sh"
  done
  export PATH="${STUB}:${PATH}"
}

teardown() {
  rm -rf "$REG" "$STUB"
}

stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "${STUB}/$1"
  chmod +x "${STUB}/$1"
}

@test "deploy's DNS gate: right A record passes, wrong or missing one stops before the host is touched" {
  run preflight_deploy_dns vps-acme acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] DNS: auto.acme.example.com → 203.0.113.10"* ]]
  yq -i '.domain = "wrong.example.com"' "${REG}/clients/acme/client.yaml"
  run preflight_deploy_dns vps-acme acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"A record of wrong.example.com points at 198.51.100.7, expected 203.0.113.10"* ]]
  yq -i '.domain = "nothing.example.com"' "${REG}/clients/acme/client.yaml"
  run preflight_deploy_dns vps-acme acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing.example.com has no A record yet (add one pointing at 203.0.113.10"* ]]
  OPSKIT_SKIP_DNS_CHECK=1 run preflight_deploy_dns vps-acme acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"DNS check skipped"* ]]
}

@test "practice hosts (local, internal TLS) need no DNS" {
  "$OPSKIT" client new demo --domain demo.localhost --host local-practice --contact ops@example.com >/dev/null
  run preflight_deploy_dns local-practice demo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "opskit deploy stops at a wrong A record before rendering or copying anything" {
  yq -i '.domain = "wrong.example.com"' "${REG}/clients/acme/client.yaml"
  PATH="${STUB}:${PATH}" run "$OPSKIT" deploy acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"A record of wrong.example.com points at 198.51.100.7"* ]]
  [ ! -d "${REG}/clients/acme/rendered" ]
}

@test "host preflight reports every check and the client and monitor DNS, changing nothing" {
  run host_preflight vps-acme
  [[ "$output" == *"[ok] ssh: commands run on vps-acme"* ]]
  [[ "$output" == *"[ok] sudo: works without a password"* ]]
  [[ "$output" == *"core(s)"* ]]
  [[ "$output" == *"[ok] memory: "* ]]
  [[ "$output" == *"disk: "* ]]
  [[ "$output" == *"IPv6"* ]]
  [[ "$output" == *"[ok] cron: installed"* ]]
  [[ "$output" == *"[ok] docker: Docker version 29.8.0 (kept by bootstrap)"* ]]
  [[ "$output" == *"[ok] outbound HTTPS: https://cloud.activepieces.com"* ]]
  [[ "$output" == *"[ok] DNS: status.acme.example.com → 203.0.113.10"* ]]
  [[ "$output" == *"[ok] DNS: auto.acme.example.com → 203.0.113.10"* ]]
}

@test "host preflight fails on no passwordless sudo, unreachable registries or wrong DNS" {
  stub sudo 'exit 1'
  stub curl 'exit 7'
  yq -i '.domain = "wrong.example.com"' "${REG}/clients/acme/client.yaml"
  run host_preflight vps-acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] sudo: needs a password"* ]]
  [[ "$output" == *"[fail] outbound HTTPS: https://ghcr.io not reachable from vps-acme"* ]]
  [[ "$output" == *"A record of wrong.example.com points at 198.51.100.7"* ]]
  [[ "$output" == *"[fail] preflight of vps-acme: fix the [fail] lines above"* ]]
}

@test "cloud-init: a non-root user with the public key and passwordless sudo, no root or password login" {
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTests me@laptop\n' > "${STUB}/id.pub"
  run "$OPSKIT" host cloud-init --user ops --key "${STUB}/id.pub"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "#cloud-config" ]
  [ "$(yq -r '.users[0].name' <<< "$output")" = "ops" ]
  [ "$(yq -r '.users[0].sudo' <<< "$output")" = "ALL=(ALL) NOPASSWD:ALL" ]
  [ "$(yq -r '.users[0].ssh_authorized_keys[0]' <<< "$output")" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTests me@laptop" ]
  [ "$(yq -r '.disable_root, .ssh_pwauth, .users[0].lock_passwd' <<< "$output" | paste -sd' ')" = "true false true" ]
}

@test "cloud-init refuses root, a private key or a missing file" {
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTests\n' > "${STUB}/id.pub"
  run "$OPSKIT" host cloud-init --user root --key "${STUB}/id.pub"
  [ "$status" -eq 1 ]
  printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n' > "${STUB}/id"
  run "$OPSKIT" host cloud-init --user ops --key "${STUB}/id"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not an SSH public key (use the .pub file, never the private key)"* ]]
  [[ "$output" != *"BEGIN"* ]]
  run "$OPSKIT" host cloud-init --user ops --key "${STUB}/missing.pub"
  [ "$status" -eq 1 ]
  run "$OPSKIT" host cloud-init --user ops
  [ "$status" -eq 1 ]
}
