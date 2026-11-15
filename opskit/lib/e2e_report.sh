#!/usr/bin/env bash
# Selftest for Phase 7 (SPEC 17 acceptance) on the throwaway client: two demo flows with a known number of runs
# ("Report demo" always succeeds, "Report demo failing" always fails) → the month's care report shows exactly
# those numbers, the handover pack lists both with pause steps, and the report email reaches a mock inbox with
# the client's recipients and the owner's copy. Needs pieces (webhook): skipped offline unless
# OPSKIT_REQUIRE_PIECES=1. Needs RT_EMAIL/RT_PASSWORD of the client (rt_seed) and the selftest registry.

E2E_REPORT_OK=3
E2E_REPORT_FAIL=2

# e2e_report_flow <domain> <port> <token> <project> <name> <IMPORT_FLOW json>: prints the flow id; on failure
# names the step and the API's answer (≤ 300 chars)
e2e_report_flow() {
  local domain="$1" port="$2" token="$3" project="$4" name="$5" body="$6" flow answer
  answer="$(rt_api "$domain" "$port" POST /v1/flows "$token" "$(jq -nc --arg n "$name" --arg p "$project" '{displayName: $n, projectId: $p}')" || true)"
  flow="$(jq -r '.id // empty' <<< "$answer" 2>/dev/null || true)"
  [ -n "$flow" ] || { e2e_report_refused "$name" create "$answer"; return 1; }
  answer="$(rt_api "$domain" "$port" POST "/v1/flows/${flow}" "$token" "$(jq -c --arg n "$name" '.request.displayName = $n' <<< "$body")" || true)"
  jq -e '.id' >/dev/null 2>&1 <<< "$answer" || { e2e_report_refused "$name" import "$answer"; return 1; }
  answer="$(RT_API_TIMEOUT="$SMOKE_PUBLISH_TIMEOUT" rt_api "$domain" "$port" POST "/v1/flows/${flow}" "$token" '{"type":"LOCK_AND_PUBLISH","request":{"status":"ENABLED"}}' || true)"
  jq -e '.id' >/dev/null 2>&1 <<< "$answer" || { e2e_report_refused "$name" publish "$answer"; return 1; }
  printf '%s' "$flow"
}

e2e_report_refused() {
  local why="no answer (timeout or connection refused)"
  [ -z "$3" ] || why="$( (jq -r '.message // .code // .' <<< "$3" 2>/dev/null || printf '%s' "$3") | tr '\n' ' ' | head -c 300)"
  log_fail "report e2e: ${1}: ${2} refused: ${why}"
}

# e2e_report_wait <domain> <port> <token> <project> <flow id> <count>: all runs of the flow finished
e2e_report_wait() {
  local domain="$1" port="$2" token="$3" project="$4" flow="$5" count="$6" _ done_runs
  for _ in $(seq 1 60); do
    done_runs="$(rt_api "$domain" "$port" GET "/v1/flow-runs?projectId=${project}&flowId=${flow}&limit=50" "$token" \
      | jq '[.data[]? | select(.status != "RUNNING" and .status != "QUEUED")] | length' 2>/dev/null || echo 0)"
    [ "$done_runs" -ge "$count" ] && return 0
    sleep 3
  done
  return 1
}

# e2e_report <id> <domain> <https port> <selftest dir>
e2e_report() {
  local id="$1" domain="$2" port="$3" dir="$4" auth token project version ok_flow fail_flow i month runs html smtp_dir smtp_pid mails
  auth="$(rt_sign_in "$domain" "$port")"
  token="$(jq -r '.token // empty' <<< "$auth")"
  project="$(jq -r '.projectId // empty' <<< "$auth")"
  [ -n "$token" ] || { log_fail "report e2e: cannot sign in"; return 1; }
  version="$(smoke_piece_version "$domain" "$port" "$token" "$project" @activepieces/piece-webhook)"
  [ -n "$version" ] || { e2e_skip "piece metadata is not available (no internet for the app)" "report e2e"; return; }
  month="$(TZ="$(yaml_get "$(client_file "$id")" .timezone UTC)" date +%Y-%m)"
  ok_flow="$(e2e_report_flow "$domain" "$port" "$token" "$project" "Report demo" "$(smoke_flow_json "Report demo" \
    "$(jq -nc --arg v "$version" '{pieceName: "@activepieces/piece-webhook", pieceVersion: $v, triggerName: "catch_webhook", propertySettings: {}, input: {authType: "none", authFields: {}}}')")")" \
    || { log_fail "report e2e: could not create the demo flow"; return 1; }
  fail_flow="$(e2e_report_flow "$domain" "$port" "$token" "$project" "Report demo failing" "$(e2e_flow_json "$version")")" \
    || { log_fail "report e2e: could not create the failing demo flow"; return 1; }
  for i in $(seq 1 "$E2E_REPORT_OK"); do rt_api "$domain" "$port" POST "/v1/webhooks/${ok_flow}" "" "{\"n\":${i}}" >/dev/null || true; done
  for i in $(seq 1 "$E2E_REPORT_FAIL"); do rt_api "$domain" "$port" POST "/v1/webhooks/${fail_flow}" "" "{\"n\":${i}}" >/dev/null || true; done
  if ! e2e_report_wait "$domain" "$port" "$token" "$project" "$ok_flow" "$E2E_REPORT_OK" \
    || ! e2e_report_wait "$domain" "$port" "$token" "$project" "$fail_flow" "$E2E_REPORT_FAIL"; then
    log_fail "report e2e: the demo runs did not finish in 3 min"
    return 1
  fi
  report_build "$id" "$month" >/dev/null || { log_fail "report e2e: the report could not be built"; return 1; }
  runs="$(jq -c '[.runs.flows[] | select(.name | startswith("Report demo"))]' "$(client_dir "$id")/reports/${month}.json")"
  if [ "$runs" != "[{\"name\":\"Report demo\",\"total\":${E2E_REPORT_OK},\"succeeded\":${E2E_REPORT_OK},\"failed\":0,\"other\":0},{\"name\":\"Report demo failing\",\"total\":${E2E_REPORT_FAIL},\"succeeded\":0,\"failed\":${E2E_REPORT_FAIL},\"other\":0}]" ]; then
    log_fail "report e2e: report numbers do not match the runs: ${runs}"
    return 1
  fi
  log_ok "report e2e: ${month} report counts the demo runs exactly (${E2E_REPORT_OK} succeeded, ${E2E_REPORT_FAIL} failed)"
  docs_build "$id" >/dev/null || { log_fail "report e2e: handover pack failed"; return 1; }
  html="$(cat "$(client_dir "$id")/docs/handover.html")"
  # shellcheck disable=SC1111 # the pack's own curly quotes
  if [[ "$html" != *"find “Report demo” and click its switch"* || "$html" != *"find “Report demo failing” and click its switch"* \
    || "$html" != *"<h2>6. Data and privacy</h2>"* || "$html" != *"<h2>7. Moving from Zapier or Make</h2>"* ]]; then
    log_fail "report e2e: the handover pack misses a flow, its pause steps, the privacy note or the Zapier checklist"
    return 1
  fi
  log_ok "report e2e: handover pack lists every active flow with pause steps, the privacy note and the Zapier checklist"
  smtp_dir="$(mktemp -d)"
  python3 -I "${OPSKIT_ROOT}/tests/helpers/mock_smtp.py" "${smtp_dir}/mails.jsonl" "${smtp_dir}/port" &
  smtp_pid=$!
  for i in $(seq 1 50); do [ -s "${smtp_dir}/port" ] && break; sleep 0.1; done
  printf 'SMTP_URL=smtp://127.0.0.1:%s\nSMTP_FROM=reports@selftest.example\nSMTP_TLS=none\nOWNER_EMAIL=owner@selftest.example\n' "$(cat "${smtp_dir}/port")" \
    > "${dir}/owner/alerts.conf"
  yq -i '.report.recipients = ["client@selftest.example"]' "$(client_file "$id")"
  report_send "$id" "$month" >/dev/null || true
  mails="$(jq -sc '[.[] | {rcpt, multipart: (.data | contains("multipart/alternative"))}]' "${smtp_dir}/mails.jsonl" 2>/dev/null || echo '[]')"
  kill "$smtp_pid" 2>/dev/null || true
  rm -rf "$smtp_dir" "${dir}/owner/alerts.conf"
  if [ "$mails" != '[{"rcpt":["<client@selftest.example>","<owner@selftest.example>"],"multipart":true}]' ]; then
    log_fail "report e2e: report email not delivered as expected: ${mails:0:200}"
    return 1
  fi
  log_ok "report e2e: report email delivered to the test inbox (client + owner copy, text + HTML)"
}
