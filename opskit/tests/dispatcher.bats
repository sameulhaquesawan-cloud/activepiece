#!/usr/bin/env bats

load helpers/common

@test "help lists commands with summaries" {
  run "$OPSKIT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: opskit <command>"* ]]
  [[ "$output" == *"version"*"pinned Activepieces release"* ]]
}

@test "no arguments prints help" {
  run "$OPSKIT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Commands:"* ]]
}

@test "unknown command fails with [fail]" {
  run "$OPSKIT" does-not-exist
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] unknown command: does-not-exist"* ]]
}

@test "command names cannot escape the commands directory" {
  run "$OPSKIT" "../log"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] unknown command"* ]]
}

@test "version shows opskit and pinned upstream versions" {
  run "$OPSKIT" version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^opskit\ [0-9]+\.[0-9]+\.[0-9]+\ \(Activepieces\ [0-9]+\.[0-9]+\.[0-9]+\)$ ]]
}
