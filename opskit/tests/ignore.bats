#!/usr/bin/env bats

load helpers/common

@test "client and host registries are git-ignored" {
  cd "$OPSKIT_ROOT"
  run git check-ignore -q clients/acme/.env
  [ "$status" -eq 0 ]
  run git check-ignore -q hosts/h1.yaml
  [ "$status" -eq 0 ]
}

@test "test fixtures named hosts/ are not ignored" {
  cd "$OPSKIT_ROOT"
  run git check-ignore -q tests/fixtures/hosts/h1.yaml
  [ "$status" -eq 1 ]
}
