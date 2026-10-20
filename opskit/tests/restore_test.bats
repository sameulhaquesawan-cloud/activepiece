#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
  new_demo_client demo
  STUB="$(mktemp -d)"
  printf '#!/usr/bin/env bash\necho "docker stub: $*" >&2\nexit 1\n' > "${STUB}/docker"
  chmod +x "${STUB}/docker"
  export PATH="${STUB}:${PATH}"
}

teardown() {
  rm -rf "$REG" "$STUB"
}

@test "restore-test needs a client id or --all" {
  run "$OPSKIT" restore-test
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: opskit restore-test"* ]]
  run "$OPSKIT" restore-test --all extra
  [ "$status" -eq 1 ]
}

@test "restore-test fails for an unknown client" {
  run "$OPSKIT" restore-test nobody
  [ "$status" -eq 1 ]
  [ ! -e "${REG}/clients/nobody" ]
}

@test "restore-test records a failure and leaves the registry untouched" {
  local before
  before="$(cat "${REG}/clients/demo/client.yaml")"
  run "$OPSKIT" restore-test demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"restore test of demo FAILED"* ]]
  [ "$(cat "${REG}/clients/demo/client.yaml")" = "$before" ]
  [ "$(find "${REG}/clients" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]
  [ "$(ls "${REG}/hosts")" = "local-practice.yaml" ]
  local line
  line="$(tail -n 1 "${REG}/clients/demo/restore-tests.jsonl")"
  [ "$(jq -r .result <<< "$line")" = "fail" ]
  [ -n "$(jq -r .reason <<< "$line")" ]
  [ "$(jq -r .at <<< "$line")" != "null" ]
}

@test "restore-test --all only tests deployed clients" {
  new_demo_client other other.localhost
  yq -i '.status = "deployed"' "${REG}/clients/other/client.yaml"
  run "$OPSKIT" restore-test --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"restore test of other"* ]]
  [[ "$output" != *"restore test of demo"* ]]
  [ ! -e "${REG}/clients/demo/restore-tests.jsonl" ]
  [ -s "${REG}/clients/other/restore-tests.jsonl" ]
}
