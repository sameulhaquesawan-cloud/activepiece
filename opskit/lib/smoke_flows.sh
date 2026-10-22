#!/usr/bin/env bash
# Staging-only smoke checks that need a signed-in user and piece metadata: a webhook flow and an
# every-minute schedule flow each produce a SUCCEEDED run; both flows are deleted afterwards.
# Needs roundtrip.sh (rt_api) and e2e.sh (e2e_webhook_piece_version) and smoke.sh.

SMOKE_FLOW_TIMEOUT="${OPSKIT_SMOKE_FLOW_TIMEOUT:-180}"
SMOKE_PUBLISH_TIMEOUT=120

# smoke_flow_json <name> <trigger settings json>: IMPORT_FLOW with the trigger and one code step
smoke_flow_json() {
  jq -nc --arg name "$1" --argjson trigger "$2" '
    {type: "IMPORT_FLOW", request: {displayName: $name, schemaVersion: null, notes: null, trigger: {
      name: "trigger", displayName: "Trigger", type: "PIECE_TRIGGER", valid: true, settings: $trigger,
      nextAction: {name: "step_1", displayName: "Answer", type: "CODE", valid: true,
        settings: {sourceCode: {packageJson: "{}", code: "export const code = async () => ({ smoke: true });"},
          input: {}, errorHandlingOptions: {continueOnFailure: {value: false}, retryOnFailure: {value: false}}}}}}}'
}

# smoke_piece_version <domain> <port> <token> <project> <piece name>
smoke_piece_version() {
  rt_api "$1" "$2" GET "/v1/pieces/${5}?projectId=${4}" "$3" | jq -r '.version // empty' 2>/dev/null || true
}

# smoke_flow <domain> <port> <token> <project> <label> <trigger settings json> <fire: webhook|wait>
# Publishing runs the trigger's enable step on the worker; a cold worker (fresh stack, restart) can take
# well over the usual 30 s API timeout, so the publish call waits up to SMOKE_PUBLISH_TIMEOUT.
smoke_flow() {
  local domain="$1" port="$2" token="$3" project="$4" label="$5" trigger="$6" fire="$7" flow waited=0 status="" answer
  flow="$(rt_api "$domain" "$port" POST /v1/flows "$token" \
    "$(jq -nc --arg n "opskit smoke ${label}" --arg p "$project" '{displayName: $n, projectId: $p}')" | jq -r '.id // empty')"
  [ -n "$flow" ] || { log_fail "smoke ${label} flow: could not create it"; return 1; }
  answer="$(rt_api "$domain" "$port" POST "/v1/flows/${flow}" "$token" "$(smoke_flow_json "opskit smoke ${label}" "$trigger")")"
  if ! jq -e '.id' >/dev/null 2>&1 <<< "$answer"; then
    smoke_flow_delete "$domain" "$port" "$token" "$flow"
    log_fail "smoke ${label} flow: import refused: $(jq -r '.message // .code // .' <<< "$answer" 2>/dev/null | head -c 300)"
    return 1
  fi
  answer="$(RT_API_TIMEOUT="$SMOKE_PUBLISH_TIMEOUT" rt_api "$domain" "$port" POST "/v1/flows/${flow}" "$token" '{"type":"LOCK_AND_PUBLISH","request":{"status":"ENABLED"}}')"
  if ! jq -e '.id' >/dev/null 2>&1 <<< "$answer"; then
    smoke_flow_delete "$domain" "$port" "$token" "$flow"
    [ -n "$answer" ] || answer="no answer in ${SMOKE_PUBLISH_TIMEOUT} s (the worker runs the trigger's enable step)"
    log_fail "smoke ${label} flow: publish refused: $(jq -r '.message // .code // .' <<< "$answer" 2>/dev/null || printf '%s' "$answer" | head -c 300)"
    return 1
  fi
  [ "$fire" != "webhook" ] || rt_api "$domain" "$port" POST "/v1/webhooks/${flow}" "" '{"smoke":true}' >/dev/null || true
  while [ "$waited" -lt "$SMOKE_FLOW_TIMEOUT" ]; do
    status="$(rt_api "$domain" "$port" GET "/v1/flow-runs?projectId=${project}&flowId=${flow}&limit=5" "$token" \
      | jq -r '[.data[]? | .status | select(. != "RUNNING" and . != "QUEUED" and . != "SCHEDULED")][0] // empty' 2>/dev/null || true)"
    [ -z "$status" ] || break
    sleep 5
    waited=$((waited + 5))
  done
  smoke_flow_delete "$domain" "$port" "$token" "$flow"
  if [ "$status" != "SUCCEEDED" ]; then
    log_fail "smoke ${label} flow: ${status:-no run} after ${waited}s (expected SUCCEEDED)"
    return 1
  fi
  log_ok "smoke ${label} flow: run SUCCEEDED (${waited}s)"
}

smoke_flow_delete() {
  rt_api "$1" "$2" DELETE "/v1/flows/${4}" "$3" >/dev/null 2>&1 || true
}

# smoke_webhook_flow <domain> <port> <token> <project>
smoke_webhook_flow() {
  local version
  smoke_injected webhook_flow && return 1
  version="$(smoke_piece_version "$1" "$2" "$3" "$4" @activepieces/piece-webhook)"
  [ -n "$version" ] || { log_fail "smoke webhook flow: webhook piece not available"; return 1; }
  smoke_flow "$1" "$2" "$3" "$4" webhook "$(jq -nc --arg v "$version" '{pieceName: "@activepieces/piece-webhook",
    pieceVersion: $v, triggerName: "catch_webhook", propertySettings: {}, input: {authType: "none", authFields: {}}}')" webhook
}

# smoke_schedule_dry_run <domain> <port> <token> <project>: an every-minute schedule fires once
smoke_schedule_dry_run() {
  local version
  smoke_injected schedule && return 1
  version="$(smoke_piece_version "$1" "$2" "$3" "$4" @activepieces/piece-schedule)"
  [ -n "$version" ] || { log_fail "smoke schedule flow: schedule piece not available"; return 1; }
  smoke_flow "$1" "$2" "$3" "$4" schedule "$(jq -nc --arg v "$version" '{pieceName: "@activepieces/piece-schedule",
    pieceVersion: $v, triggerName: "every_x_minutes", propertySettings: {}, input: {minutes: 1}}')" wait
}
