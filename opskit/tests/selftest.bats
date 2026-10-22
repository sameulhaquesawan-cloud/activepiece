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
  [[ "$output" == *"[ok] smoke e2e: all production checks pass on "* ]]
  [[ "$output" == *"[ok] smoke e2e: a lowered flow count detected: counts of "*" dropped: flows "* ]]
  [[ "$output" == *"[ok] smoke e2e: a stopped worker detected: containers of "*": worker exited"* ]]
  [[ "$output" == *"[ok] smoke e2e: a connection stored with another key detected"*"(wrong AP_ENCRYPTION_KEY?)"* ]]
  [[ "$output" == *"[ok] smoke e2e: a database newer than the image detected"* ]]
  [[ "$output" == *"healthy again after the broken-condition checks"* ]]
  [[ "$output" == *"[ok] upgrade e2e: promote 0.92.2 → "*" passed staging and production checks, data intact, history 'upgraded'"* ]]
  [[ "$output" == *"[ok] upgrade e2e: injected production failure on 0.91.4 → "*" rolled back to 0.91.4, schema and data intact, 1 owner alert"* ]]
  if [ "${OPSKIT_REQUIRE_PIECES:-0}" = "1" ]; then
    [[ "$output" == *"[ok] smoke webhook flow: run SUCCEEDED"* ]]
    [[ "$output" == *"[ok] smoke schedule flow: run SUCCEEDED"* ]]
    [[ "$output" == *"[ok] monitoring e2e: failing flow → exactly 1 Telegram alert with flow name and run link"* ]]
    [[ "$output" == *"[ok] templates e2e: example imported"* ]]
    [[ "$output" == *"[ok] templates e2e: example: run 1 test/good.json → SUCCEEDED"* ]]
    [[ "$output" == *"[ok] templates e2e: example: run 2 test/missing-name.json → FAILED"* ]]
    [[ "$output" == *"[ok] templates e2e: lead-capture: run 2 test/bad-email.json → FAILED"* ]]
    [[ "$output" == *"[ok] templates e2e: invoice-reminder: run 2 test/tick.json → FAILED"* ]]
    [[ "$output" == *"[ok] templates e2e: review-request: run 2 test/shopify-paid.json → SUCCEEDED"* ]]
    [[ "$output" == *"[ok] templates e2e: ai-email-sorter: run 1 test/urgent-email.json → SUCCEEDED"* ]]
    [[ "$output" == *"[ok] templates e2e: lead-capture-tables imported"* ]]
    [[ "$output" == *"[ok] templates e2e: lead-capture-tables: run 2 test/bad-email.json → FAILED"* ]]
    [[ "$output" == *"[ok] templates e2e: invoice-reminder-tables: run 3 test/tick.json → FAILED"* ]]
    [[ "$output" == *"[ok] report e2e: "*" report counts the demo runs exactly (3 succeeded, 2 failed)"* ]]
    [[ "$output" == *"[ok] report e2e: handover pack lists every active flow with pause steps, the privacy note and the Zapier checklist"* ]]
    [[ "$output" == *"[ok] report e2e: report email delivered to the test inbox (client + owner copy, text + HTML)"* ]]
  else
    [[ "$output" == *"[ok] monitoring e2e: failing flow"* || "$output" == *"monitoring e2e SKIPPED"* ]]
    [[ "$output" == *"[ok] templates e2e: example imported"* || "$output" == *"templates e2e SKIPPED"* ]]
    [[ "$output" == *"[ok] report e2e: handover pack"* || "$output" == *"report e2e SKIPPED"* ]]
    [[ "$output" == *"[ok] smoke webhook flow: run SUCCEEDED"* || "$output" == *"smoke flow checks SKIPPED"* ]]
  fi
  [[ "$output" == *"[ok] selftest passed"* ]]
  local id
  id="$(printf '%s\n' "$output" | sed -n 's/^selftest: \(selftest-[0-9a-f]*\) in .*/\1/p')"
  [ -n "$id" ]
  [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=${id}")" ]
  [ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${id}")" ]
  [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=${id}-rt")" ]
  [ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${id}-rt")" ]
  local p
  for p in "${id}-up" "${id}-rb"; do
    [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=${p}")" ]
    [ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${p}")" ]
  done
  [ -z "$(docker ps -aq --filter "name=upgradestage-")" ]
}
