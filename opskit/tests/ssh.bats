#!/usr/bin/env bats

load helpers/common

setup() {
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/validate.sh"
  source "${OPSKIT_ROOT}/lib/ssh.sh"
  STUB_DIR="$(mktemp -d)"
  CALLS="${STUB_DIR}/calls"
  for tool in ssh scp; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" "$@" > "%s"\n' "$tool" "$CALLS" > "${STUB_DIR}/${tool}"
    chmod +x "${STUB_DIR}/${tool}"
  done
  PATH="${STUB_DIR}:${PATH}"
}

teardown() {
  rm -rf "$STUB_DIR"
}

assert_safe_options() {
  grep -qx 'BatchMode=yes' "$CALLS"
  grep -qx 'StrictHostKeyChecking=accept-new' "$CALLS"
  grep -qx 'PasswordAuthentication=no' "$CALLS"
  grep -qx 'KbdInteractiveAuthentication=no' "$CALLS"
  grep -qx 'ConnectTimeout=10' "$CALLS"
  grep -qx 'ServerAliveInterval=15' "$CALLS"
}

@test "ssh_run uses key-only, non-interactive options and the given port" {
  run ssh_run ops 203.0.113.10 2222 docker compose -p acme ps
  [ "$status" -eq 0 ]
  assert_safe_options
  grep -qx -- '-p' "$CALLS"
  grep -qx '2222' "$CALLS"
  grep -qx 'ops@203.0.113.10' "$CALLS"
  [ "$(tail -n 1 "$CALLS")" = "docker compose -p acme ps" ]
}

@test "ssh_run quotes remote arguments" {
  run ssh_run ops host.example.com 22 echo 'a b; rm -rf /'
  [ "$status" -eq 0 ]
  [ "$(tail -n 1 "$CALLS")" = 'echo a\ b\;\ rm\ -rf\ /' ]
}

@test "known hosts file can be pinned" {
  OPSKIT_KNOWN_HOSTS=/tmp/kh run ssh_run ops host.example.com 22 true
  grep -qx 'UserKnownHostsFile=/tmp/kh' "$CALLS"
}

@test "scp_put uses the same options and -P port" {
  local file="${STUB_DIR}/payload"
  echo data > "$file"
  run scp_put ops 203.0.113.10 22 "$file" /opt/opskit/payload
  [ "$status" -eq 0 ]
  assert_safe_options
  grep -qx -- '-P' "$CALLS"
  grep -qx 'ops@203.0.113.10:/opt/opskit/payload' "$CALLS"
}

@test "bad targets are rejected before ssh runs" {
  run ssh_run 'root;x' host 22 true
  [ "$status" -eq 1 ]
  run ssh_run ops 'host;rm' 22 true
  [ "$status" -eq 1 ]
  run ssh_run ops host 70000 true
  [ "$status" -eq 1 ]
  [ ! -e "$CALLS" ]
}

@test "scp_put fails on a missing source" {
  run scp_put ops host 22 /nonexistent /tmp/x
  [ "$status" -eq 1 ]
  [[ "$output" == *"scp source not found"* ]]
}
