#!/usr/bin/env bats

load helpers/common

# bats test_tags=docker
@test "selftest deploys, backs up and restores a throwaway client, then cleans up" {
  run "$OPSKIT" selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] worker registered"* ]]
  [[ "$output" == *"[ok] HTTPS health OK"* ]]
  [[ "$output" == *"[ok] re-deploy idempotent"* ]]
  [[ "$output" == *"read-only role of "*": reads runs, cannot write"* ]]
  [[ "$output" == *"[ok] round trip: seeded 3 flows"* ]]
  [[ "$output" == *"[ok] all 1 stored connections decrypt with the restored key"* ]]
  [[ "$output" == *"has the 3 flows, sign-in works and the connection decrypts"* ]]
  if [ "${OPSKIT_REQUIRE_PIECES:-0}" = "1" ]; then
    [[ "$output" == *"[ok] monitoring e2e: failing flow → exactly 1 Telegram alert with flow name and run link"* ]]
    [[ "$output" == *"[ok] templates e2e: example imported"* ]]
    [[ "$output" == *"[ok] templates e2e: example: run 1 test/good.json → SUCCEEDED"* ]]
    [[ "$output" == *"[ok] templates e2e: example: run 2 test/missing-name.json → FAILED"* ]]
    [[ "$output" == *"[ok] templates e2e: lead-capture: run 2 test/bad-email.json → FAILED"* ]]
    [[ "$output" == *"[ok] templates e2e: invoice-reminder: run 2 test/tick.json → FAILED"* ]]
    [[ "$output" == *"[ok] templates e2e: review-request: run 2 test/shopify-paid.json → SUCCEEDED"* ]]
    [[ "$output" == *"[ok] templates e2e: ai-email-sorter: run 1 test/urgent-email.json → SUCCEEDED"* ]]
  else
    [[ "$output" == *"[ok] monitoring e2e: failing flow"* || "$output" == *"monitoring e2e SKIPPED"* ]]
    [[ "$output" == *"[ok] templates e2e: example imported"* || "$output" == *"templates e2e SKIPPED"* ]]
  fi
  [[ "$output" == *"[ok] selftest passed"* ]]
  local id
  id="$(printf '%s\n' "$output" | sed -n 's/^selftest: \(selftest-[0-9a-f]*\) in .*/\1/p')"
  [ -n "$id" ]
  [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=${id}")" ]
  [ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${id}")" ]
  [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=${id}-rt")" ]
  [ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${id}-rt")" ]
}
