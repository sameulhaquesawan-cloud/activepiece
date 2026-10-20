#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/validate.sh"
  source "${OPSKIT_ROOT}/lib/registry.sh"
  source "${OPSKIT_ROOT}/lib/ssh.sh"
  source "${OPSKIT_ROOT}/lib/host.sh"
  WORK="$(mktemp -d)"
  cat > "${REG}/hosts/vps-acme.yaml" <<'EOF'
host_id: vps-acme
ip: 203.0.113.10
ssh_user: ops
ssh_port: 2222
mode: dedicated
cpus: 2
ram_gb: 4
EOF
  STUB="${WORK}/stub"
  mkdir -p "$STUB"
  for tool in ssh scp; do
    printf '#!/usr/bin/env bash\nprintf "%%s " "%s" "$@" >> "%s/calls"\necho >> "%s/calls"\n' "$tool" "$WORK" "$WORK" > "${STUB}/${tool}"
    chmod +x "${STUB}/${tool}"
  done
}

teardown() {
  rm -rf "$REG" "$WORK"
}

@test "defaults: ssh transport and /opt/opskit root" {
  [ "$(host_transport vps-acme)" = "ssh" ]
  [ "$(host_root vps-acme)" = "/opt/opskit" ]
  [ "$(host_transport local-practice)" = "local" ]
}

@test "local transport runs commands and copies files here" {
  run host_run local-practice echo hello
  [ "$output" = "hello" ]
  echo data > "${WORK}/f"
  host_put local-practice "${WORK}/f" "${WORK}/dest/sub/f" 640
  [ "$(cat "${WORK}/dest/sub/f")" = "data" ]
  [ "$(stat -c %a "${WORK}/dest/sub/f")" = "640" ]
}

@test "ssh transport uses the host's user, ip and port" {
  PATH="${STUB}:${PATH}" run host_run vps-acme docker compose -p acme ps
  [ "$status" -eq 0 ]
  grep -q 'ssh .* -p 2222 ops@203.0.113.10 -- docker compose -p acme ps' "${WORK}/calls"
}

@test "ssh put creates the directory, copies, then sets the mode" {
  echo data > "${WORK}/f"
  PATH="${STUB}:${PATH}" run host_put vps-acme "${WORK}/f" /opt/opskit/clients/acme/.env 600
  [ "$status" -eq 0 ]
  sed -n 1p "${WORK}/calls" | grep -q -- '-- mkdir -p /opt/opskit/clients/acme'
  sed -n 2p "${WORK}/calls" | grep -q -- "-P 2222 -- ${WORK}/f ops@203.0.113.10:/opt/opskit/clients/acme/.env"
  sed -n 3p "${WORK}/calls" | grep -q -- '-- chmod 600 /opt/opskit/clients/acme/.env'
}

@test "missing source fails before touching the host" {
  PATH="${STUB}:${PATH}" run host_put vps-acme /nonexistent /tmp/x
  [ "$status" -eq 1 ]
  [ ! -e "${WORK}/calls" ]
}
