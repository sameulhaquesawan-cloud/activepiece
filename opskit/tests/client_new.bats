#!/usr/bin/env bats

load helpers/common
load helpers/registry

setup() {
  make_registry
}

teardown() {
  rm -rf "$REG"
}

@test "client new writes a valid draft client with host details and pinned tag" {
  run "$OPSKIT" client new acme --domain auto.acme.example.com --host local-practice --contact ops@acme.example.com --name "Acme Dental"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] client acme created"* ]]
  local file="${REG}/clients/acme/client.yaml"
  [ "$(yq -r .status "$file")" = "draft" ]
  [ "$(yq -r .host.ip "$file")" = "127.0.0.1" ]
  [ "$(yq -r .image.tag "$file")" = "$(yq -r .ap_version "$file")" ]
  [ "$(yq -r '.history[0].event' "$file")" = "created" ]
  [ "$(stat -c %a "${REG}/clients/acme")" = "700" ]
}

@test "client new refuses an existing id" {
  new_demo_client
  run "$OPSKIT" client new demo --domain demo.localhost --host local-practice --contact ops@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "client new rejects bad id, domain, email, name and unknown host" {
  run "$OPSKIT" client new Acme --domain a.example.com --host local-practice --contact o@example.com
  [[ "$output" == *"lowercase slug"* ]]
  run "$OPSKIT" client new acme --domain "https://a.com" --host local-practice --contact o@example.com
  [[ "$output" == *"--domain must be"* ]]
  run "$OPSKIT" client new acme --domain a.example.com --host local-practice --contact nope
  [[ "$output" == *"--contact must be"* ]]
  run "$OPSKIT" client new acme --domain a.example.com --host local-practice --contact o@example.com --name 'bad "name"'
  [[ "$output" == *"--name must be"* ]]
  run "$OPSKIT" client new acme --domain a.example.com --host nowhere --contact o@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown host: nowhere"* ]]
  [ ! -e "${REG}/clients/acme" ]
}
