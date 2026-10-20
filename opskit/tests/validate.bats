#!/usr/bin/env bats

load helpers/common

FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

setup() {
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK"
}

broken_client() {
  yq "$1" "${FIXTURES}/clients/valid.yaml" > "${WORK}/client.yaml"
}

expect_client_error() {
  broken_client "$1"
  run "$OPSKIT" validate "${WORK}/client.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] $2"* ]]
  [[ "$output" == *"[fail] client.yaml: invalid"* ]]
}

@test "valid client and host fixtures pass" {
  run "$OPSKIT" validate "${FIXTURES}/clients/valid.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] valid.yaml: valid"* ]]
  run "$OPSKIT" validate "${FIXTURES}/hosts/valid.yaml"
  [ "$status" -eq 0 ]
}

@test "missing required field" {
  expect_client_error 'del(.domain)' "domain: is required"
}

@test "bad client id slug" {
  expect_client_error '.client_id = "Acme Dental"' "client_id: has an invalid format"
}

@test "bad domain" {
  expect_client_error '.domain = "https://acme.com"' "domain: has an invalid format"
}

@test "unknown alert channel (WhatsApp is a later add-on)" {
  expect_client_error '.alerts.channels = ["whatsapp"]' "alerts.channels.0: must be one of: telegram, email, slack"
}

@test "worker replicas below 1" {
  expect_client_error '.workers.replicas = 0' "workers.replicas: must be >= 1"
}

@test "bad host mode" {
  expect_client_error '.host.mode = "cloud"' "host.mode: must be one of: dedicated, shared"
}

@test "root ssh user is rejected" {
  expect_client_error '.host.ssh_user = "root"' "host.ssh_user: this value is not allowed"
}

@test "unknown top-level field" {
  expect_client_error '.colour = "red"' "colour: unknown field"
}

@test "image must be an official Activepieces repo" {
  expect_client_error '.image.repo = "evil/activepieces"' "image.repo: must be one of"
}

@test "slack takes a secret name, never the webhook URL" {
  expect_client_error '.alerts.slack.webhook_secret = "https://hooks.slack.com/services/x"' "alerts.slack.webhook_secret: has an invalid format"
}

@test "host file errors are reported too" {
  yq '.ram_gb = 1 | del(.cpus)' "${FIXTURES}/hosts/valid.yaml" > "${WORK}/host.yaml"
  run "$OPSKIT" validate "${WORK}/host.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] cpus: is required"* ]]
  [[ "$output" == *"[fail] ram_gb: must be >= 2"* ]]
}

@test "file that is not a mapping is rejected" {
  printf -- '- just\n- a list\n' > "${WORK}/list.yaml"
  run "$OPSKIT" validate "${WORK}/list.yaml" --type client
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a valid YAML/JSON mapping"* ]]
}

@test "type cannot be detected without client_id or host_id" {
  printf 'name: x\n' > "${WORK}/x.yaml"
  run "$OPSKIT" validate "${WORK}/x.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot tell client from host"* ]]
}
