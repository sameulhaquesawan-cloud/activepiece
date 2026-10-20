#!/usr/bin/env bash
# Monitoring end-to-end check for selftest (Phase 4 acceptance): a deliberately failing flow →
# detect-failed-runs.sh on the host → exactly one Telegram message (mock API) with flow name and
# run link; a second detector run sends nothing. Needs piece metadata (internet): skipped with a
# warning when pieces are offline, unless OPSKIT_REQUIRE_PIECES=1 (CI). Uses rt_api from roundtrip.sh.

E2E_FLOW="E2E deliberately failing flow"

# e2e_flow_json <webhook piece version>: IMPORT_FLOW with a webhook trigger and a throwing code step
e2e_flow_json() {
  jq -nc --arg v "$1" --arg name "$E2E_FLOW" '
    {type: "IMPORT_FLOW", request: {displayName: $name, schemaVersion: null, notes: null, trigger: {
      name: "trigger", displayName: "Webhook", type: "PIECE_TRIGGER", valid: true,
      settings: {pieceName: "@activepieces/piece-webhook", pieceVersion: $v, triggerName: "catch_webhook",
        propertySettings: {}, input: {authType: "none", authFields: {}}},
      nextAction: {name: "step_1", displayName: "Fail on purpose", type: "CODE", valid: true,
        settings: {sourceCode: {packageJson: "{}",
          code: "export const code = async () => { throw new Error(\"opskit e2e: deliberate failure\"); };"},
          input: {}, errorHandlingOptions: {continueOnFailure: {value: false}, retryOnFailure: {value: false}}}}}}}'
}

e2e_mock_start() {
  E2E_MOCK_DIR="$(mktemp -d)"
  python3 -I "${OPSKIT_ROOT}/tests/helpers/mock_http.py" "${E2E_MOCK_DIR}/requests.jsonl" "${E2E_MOCK_DIR}/port" &
  E2E_MOCK_PID=$!
  local _
  for _ in $(seq 1 50); do
    [ -s "${E2E_MOCK_DIR}/port" ] && break
    sleep 0.1
  done
  touch "${E2E_MOCK_DIR}/requests.jsonl"
}

e2e_mock_stop() {
  [ -z "${E2E_MOCK_PID:-}" ] || kill "$E2E_MOCK_PID" 2>/dev/null || true
  [ -z "${E2E_MOCK_DIR:-}" ] || rm -rf "$E2E_MOCK_DIR"
}

e2e_skip() {
  if [ "${OPSKIT_REQUIRE_PIECES:-0}" = "1" ]; then
    log_fail "monitoring e2e: $1 (OPSKIT_REQUIRE_PIECES=1)"
    return 1
  fi
  log_warn "monitoring e2e SKIPPED: $1 — runs where pieces load (CI, Codespaces)"
  return 0
}

e2e_detector() {
  local root="$1" id="$2"
  OPSKIT_TELEGRAM_API="http://127.0.0.1:$(cat "${E2E_MOCK_DIR}/port")" "${root}/agent/detect-failed-runs.sh" "$id" --root "$root"
}

# the app syncs piece metadata from the internet after start; wait longer when pieces are required
e2e_webhook_piece_version() {
  local domain="$1" port="$2" token="$3" project="$4" tries=10 _ version
  [ "${OPSKIT_REQUIRE_PIECES:-0}" != "1" ] || tries=60
  for _ in $(seq 1 "$tries"); do
    version="$(rt_api "$domain" "$port" GET "/v1/pieces/@activepieces/piece-webhook?projectId=${project}" "$token" \
      | jq -r '.version // empty' 2>/dev/null || true)"
    [ -z "$version" ] || { printf '%s' "$version"; return 0; }
    sleep 3
  done
}

# e2e_wait_failed_run <domain> <port> <token> <project> <flow id>: prints the failed run id
e2e_wait_failed_run() {
  local domain="$1" port="$2" token="$3" project="$4" flow="$5" _ run
  for _ in $(seq 1 60); do
    run="$(rt_api "$domain" "$port" GET "/v1/flow-runs?projectId=${project}&flowId=${flow}&limit=5" "$token" \
      | jq -r '[.data[]? | select(.status == "FAILED")][0].id // empty')"
    [ -z "$run" ] || { printf '%s' "$run"; return 0; }
    sleep 3
  done
  return 1
}

# e2e_monitoring <host> <id> <domain> <https port>: needs RT_EMAIL/RT_PASSWORD from rt_seed
e2e_monitoring() {
  local host="$1" id="$2" domain="$3" port="$4" root auth token project version flow run start messages text
  command -v python3 >/dev/null || { e2e_skip "python3 missing for the mock Telegram API"; return; }
  root="$(host_root "$host")"
  auth="$(rt_sign_in "$domain" "$port")"
  token="$(jq -r '.token // empty' <<< "$auth")"
  project="$(jq -r '.projectId // empty' <<< "$auth")"
  [ -n "$token" ] || { log_fail "monitoring e2e: cannot sign in"; return 1; }
  version="$(e2e_webhook_piece_version "$domain" "$port" "$token" "$project")"
  [ -n "$version" ] || { e2e_skip "piece metadata is not available (no internet for the app)"; return; }
  flow="$(rt_api "$domain" "$port" POST /v1/flows "$token" "$(jq -nc --arg n "$E2E_FLOW" --arg p "$project" '{displayName: $n, projectId: $p}')" | jq -r '.id // empty')"
  [ -n "$flow" ] || { log_fail "monitoring e2e: could not create the flow"; return 1; }
  rt_api "$domain" "$port" POST "/v1/flows/${flow}" "$token" "$(e2e_flow_json "$version")" | jq -e '.id' >/dev/null \
    || { log_fail "monitoring e2e: could not import the failing flow"; return 1; }
  rt_api "$domain" "$port" POST "/v1/flows/${flow}" "$token" '{"type":"LOCK_AND_PUBLISH","request":{"status":"ENABLED"}}' | jq -e '.id' >/dev/null \
    || { log_fail "monitoring e2e: could not publish the flow"; return 1; }
  printf 'TELEGRAM_BOT_TOKEN=123:e2e\nTELEGRAM_CHAT_ID=111\n' > "${root}/agent/alerts.conf"
  e2e_mock_start
  e2e_detector "$root" "$id" >/dev/null || { e2e_mock_stop; log_fail "monitoring e2e: detector could not start"; return 1; }
  rt_api "$domain" "$port" POST "/v1/webhooks/${flow}" "" '{"lead":"e2e"}' >/dev/null || true
  start="$(date +%s)"
  run="$(e2e_wait_failed_run "$domain" "$port" "$token" "$project" "$flow")" \
    || { e2e_mock_stop; log_fail "monitoring e2e: the flow did not produce a FAILED run in 3 min"; return 1; }
  e2e_detector "$root" "$id" >/dev/null
  e2e_detector "$root" "$id" >/dev/null
  messages="$(jq -s '[.[] | select(.path | endswith("/sendMessage"))] | length' "${E2E_MOCK_DIR}/requests.jsonl")"
  text="$(jq -r '.body | fromjson | .text' "${E2E_MOCK_DIR}/requests.jsonl" | head -n 5)"
  e2e_mock_stop
  rm -f "${root}/agent/alerts.conf"
  if [ "$messages" != "1" ]; then
    log_fail "monitoring e2e: expected exactly 1 Telegram message, got ${messages}"
    return 1
  fi
  if [[ "$text" != *"Flow \"${E2E_FLOW}\" failed"* || "$text" != *"/projects/${project}/runs/${run}"* ]]; then
    log_fail "monitoring e2e: alert lacks flow name or run link: ${text:0:200}"
    return 1
  fi
  log_ok "monitoring e2e: failing flow → exactly 1 Telegram alert with flow name and run link ($(( $(date +%s) - start ))s after the failure), no repeat"
}
