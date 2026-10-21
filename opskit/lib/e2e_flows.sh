#!/usr/bin/env bash
# Flow template end-to-end check for selftest (Phase 5 acceptance). Every template is imported with
# `opskit flows import` (placeholders from test.set, else their made-up examples; password piped to
# the prompt) and must arrive switched off. Templates with test.runs are then imported once more as
# "<name> (opskit stub test)": steps of pieces that need the client's accounts become code steps that
# return their input (or the run's stub file), a non-webhook trigger becomes a webhook. Each run's
# payload is posted to it and the run must end as template.yaml says (status, steps that ran or not).
# Needs piece metadata (internet): skipped like e2e_monitoring unless OPSKIT_REQUIRE_PIECES=1.

E2E_STUB_JQ="${OPSKIT_ROOT}/templates/flows-stub.jq"

e2e_flow_sets() {
  yq -o=json '.' "$1" | jq -r '(.test.set // {}) as $set
    | (.placeholders // [])[] | . as $p | select(($set | has($p.key)) or ($p | has("default") | not))
    | "--set", $p.key + "=" + ($set[$p.key] // $p.example)'
}

# e2e_flow_id <domain> <port> <token> <project> <display name>
e2e_flow_id() {
  rt_api "$1" "$2" GET "/v1/flows?projectId=${4}&limit=100" "$3" \
    | jq -r --arg n "$5" '[.data[]? | select(.version.displayName == $n)][0].id // empty'
}

# e2e_flow_wait_run <domain> <port> <token> <project> <flow> <count>: id of the count-th finished run
e2e_flow_wait_run() {
  local _ ids
  for _ in $(seq 1 80); do
    ids="$(rt_api "$1" "$2" GET "/v1/flow-runs?projectId=${4}&flowId=${5}&limit=50" "$3" \
      | jq -r '[.data[]? | select(.status as $s | ["RUNNING", "QUEUED", "PAUSED"] | index($s) | not)] | sort_by(.created) | .[].id')"
    if [ "$(grep -c . <<< "$ids")" -ge "$6" ]; then
      sed -n "${6}p" <<< "$ids"
      return 0
    fi
    sleep 3
  done
  return 1
}

# e2e_flow_stubbed <template dir> <filled flow> <run index> <webhook version>: IMPORT_FLOW request
e2e_flow_stubbed() {
  local dir="$1" filled="$2" index="$3" version="$4" pieces stubs step file
  pieces="$(yq -o=json '[.connections[]?.piece]' "${dir}/template.yaml")"
  stubs='{}'
  while IFS=$'\t' read -r step file; do
    [ -n "$step" ] || continue
    stubs="$(jq -c --arg s "$step" --slurpfile v "${dir}/${file}" '. + {($s): $v[0]}' <<< "$stubs")"
  done < <(I="$index" yq -r '.test.runs[env(I)].stubs // {} | to_entries[] | [.key, .value] | @tsv' "${dir}/template.yaml")
  jq -c --argjson pieces "$pieces" --argjson stubs "$stubs" --arg webhookVersion "$version" -f "$E2E_STUB_JQ" "$filled" \
    | jq -c '{type: "IMPORT_FLOW", request: .}'
}

# e2e_flow_check_steps <template dir> <run index> <run json>: ran / not_ran expectations
e2e_flow_check_steps() {
  local dir="$1" index="$2" run="$3" missing
  missing="$(I="$index" yq -o=json '.test.runs[env(I)] | {ran: (.ran // []), not_ran: (.not_ran // [])}' "${dir}/template.yaml" \
    | jq -r --argjson run "$run" '($run.steps // {} | keys) as $done
      | (.ran[] | select(. as $s | $done | index($s) | not) | "\(.) did not run"),
        (.not_ran[] | select(. as $s | $done | index($s)) | "\(.) ran but should not")')"
  [ -z "$missing" ] || { printf '%s' "$(paste -sd ';' <<< "$missing")"; return 1; }
}

# e2e_flow_runs <template dir> <id> <domain> <port> <token> <project> <webhook version>
e2e_flow_runs() {
  local dir="$1" id="$2" domain="$3" port="$4" token="$5" project="$6" version="$7" template filled name flow
  local count index payload expect request last="" run_id run got problem
  template="$(basename "$dir")"
  filled="$(client_dir "$id")/flows/${template}.json"
  name="$(jq -r '.flows[0].displayName' "${dir}/flow.json") (opskit stub test)"
  flow="$(rt_api "$domain" "$port" POST /v1/flows "$token" "$(jq -nc --arg n "$name" --arg p "$project" '{displayName: $n, projectId: $p}')" | jq -r '.id // empty')"
  [ -n "$flow" ] || { log_fail "templates e2e: ${template}: could not create the stub test flow"; return 1; }
  count="$(yq -r '.test.runs | length' "${dir}/template.yaml")"
  for index in $(seq 0 $((count - 1))); do
    payload="$(I="$index" yq -r '.test.runs[env(I)].payload' "${dir}/template.yaml")"
    expect="$(I="$index" yq -r '.test.runs[env(I)].expect' "${dir}/template.yaml")"
    request="$(e2e_flow_stubbed "$dir" "$filled" "$index" "$version")"
    if [ "$request" != "$last" ]; then
      rt_api "$domain" "$port" POST "/v1/flows/${flow}" "$token" "$request" | jq -e '.id' >/dev/null \
        || { log_fail "templates e2e: ${template}: stub flow import failed"; return 1; }
      rt_api "$domain" "$port" POST "/v1/flows/${flow}" "$token" '{"type":"LOCK_AND_PUBLISH","request":{"status":"ENABLED"}}' \
        | jq -e '.id' >/dev/null || { log_fail "templates e2e: ${template}: could not publish the stub flow"; return 1; }
      last="$request"
    fi
    rt_api "$domain" "$port" POST "/v1/webhooks/${flow}" "" "$(jq -c . "${dir}/${payload}")" >/dev/null || true
    run_id="$(e2e_flow_wait_run "$domain" "$port" "$token" "$project" "$flow" $((index + 1)))" \
      || { log_fail "templates e2e: ${template}: ${payload} produced no finished run in 4 min"; return 1; }
    run="$(rt_api "$domain" "$port" GET "/v1/flow-runs/${run_id}" "$token")"
    got="$(jq -r '.status // "?"' <<< "$run")"
    if [ "$got" != "$expect" ]; then
      log_fail "templates e2e: ${template}: run $((index + 1)) (${payload}) ended ${got}, expected ${expect}"
      return 1
    fi
    if ! problem="$(e2e_flow_check_steps "$dir" "$index" "$run")"; then
      log_fail "templates e2e: ${template}: run $((index + 1)) (${payload}): ${problem}"
      return 1
    fi
    log_ok "templates e2e: ${template}: run $((index + 1)) ${payload} → ${got}"
  done
  rt_api "$domain" "$port" POST "/v1/flows/${flow}" "$token" '{"type":"CHANGE_STATUS","request":{"status":"DISABLED"}}' >/dev/null || true
}

# e2e_flow_templates <id> <domain> <https port>: needs RT_EMAIL/RT_PASSWORD from rt_seed
e2e_flow_templates() {
  local id="$1" domain="$2" port="$3" auth token project version template dir sets name flow
  auth="$(rt_sign_in "$domain" "$port")"
  token="$(jq -r '.token // empty' <<< "$auth")"
  project="$(jq -r '.projectId // empty' <<< "$auth")"
  [ -n "$token" ] || { log_fail "templates e2e: cannot sign in"; return 1; }
  version="$(e2e_webhook_piece_version "$domain" "$port" "$token" "$project")"
  [ -n "$version" ] || { e2e_skip "piece metadata is not available (no internet for the app)" "templates e2e"; return; }
  while IFS= read -r template; do
    dir="$(flows_dir)/${template}"
    mapfile -t sets < <(e2e_flow_sets "${dir}/template.yaml")
    if ! printf '%s\n' "$RT_PASSWORD" | "${OPSKIT_ROOT}/bin/opskit" flows import "$template" "$id" --email "$RT_EMAIL" "${sets[@]}" >/dev/null; then
      log_fail "templates e2e: ${template}: import failed (run: opskit flows import ${template} ${id})"
      return 1
    fi
    name="$(jq -r '.flows[0].displayName' "${dir}/flow.json")"
    flow="$(e2e_flow_id "$domain" "$port" "$token" "$project" "$name")"
    [ -n "$flow" ] || { log_fail "templates e2e: ${template}: imported flow not found"; return 1; }
    log_ok "templates e2e: ${template} imported (flow ${flow}, switched off)"
    [ "$(yq -r '.test.runs // [] | length' "${dir}/template.yaml")" != "0" ] || continue
    "${OPSKIT_ROOT}/bin/opskit" flows import "$template" "$id" --print-steps "${sets[@]}" >/dev/null \
      || { log_fail "templates e2e: ${template}: could not fill the template"; return 1; }
    e2e_flow_runs "$dir" "$id" "$domain" "$port" "$token" "$project" "$version" || return 1
  done < <(flows_ids)
}
