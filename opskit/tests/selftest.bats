#!/usr/bin/env bats

load helpers/common

# bats test_tags=docker
@test "selftest deploys a throwaway client end to end and cleans up" {
  run "$OPSKIT" selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] worker registered"* ]]
  [[ "$output" == *"[ok] HTTPS health OK"* ]]
  [[ "$output" == *"[ok] re-deploy idempotent"* ]]
  [[ "$output" == *"[ok] selftest passed"* ]]
  local id
  id="$(printf '%s\n' "$output" | sed -n 's/^selftest: \(selftest-[0-9a-f]*\) in .*/\1/p')"
  [ -n "$id" ]
  [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=${id}")" ]
  [ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${id}")" ]
}
