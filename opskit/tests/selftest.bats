#!/usr/bin/env bats

load helpers/common

# bats test_tags=docker
@test "selftest deploys, backs up and restores a throwaway client, then cleans up" {
  run "$OPSKIT" selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] worker registered"* ]]
  [[ "$output" == *"[ok] HTTPS health OK"* ]]
  [[ "$output" == *"[ok] re-deploy idempotent"* ]]
  [[ "$output" == *"[ok] round trip: seeded 3 flows"* ]]
  [[ "$output" == *"[ok] all 1 stored connections decrypt with the restored key"* ]]
  [[ "$output" == *"has the 3 flows, sign-in works and the connection decrypts"* ]]
  [[ "$output" == *"[ok] selftest passed"* ]]
  local id
  id="$(printf '%s\n' "$output" | sed -n 's/^selftest: \(selftest-[0-9a-f]*\) in .*/\1/p')"
  [ -n "$id" ]
  [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=${id}")" ]
  [ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${id}")" ]
  [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=${id}-rt")" ]
  [ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${id}-rt")" ]
}
