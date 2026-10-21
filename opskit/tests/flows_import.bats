#!/usr/bin/env bats

load helpers/common
load helpers/mock_http
load helpers/registry

PASSWORD="Pw-$(printf 'correct horse %s' battery | tr ' ' '-')"

setup() {
  make_registry
  new_demo_client acme acme.example.com
  WORK="$(mktemp -d)"
  export OPSKIT_FLOWS_DIR="${WORK}/flows"
  mkdir -p "$OPSKIT_FLOWS_DIR"
  cp -r "${OPSKIT_ROOT}/flows/example" "${OPSKIT_FLOWS_DIR}/example"
  export MOCK_RESPONSES="${WORK}/responses.json"
  responses '.'
  start_mock_http
  export TMPDIR="${WORK}/tmp"
  mkdir -p "$TMPDIR"
}

teardown() {
  stop_mock_http
  rm -rf "$WORK" "$REG"
}

# responses <jq edits applied to the default mock API>
responses() {
  jq -n --arg step "Check name" '{
    "POST /api/v1/authentication/sign-in": {body: {token: "tok-123", projectId: "proj1", platformRole: "ADMIN"}},
    "GET /api/v1/pieces/@activepieces/piece-webhook?*": {body: {name: "@activepieces/piece-webhook", version: "0.1.42"}},
    "GET /api/v1/flows?*": {body: {data: []}},
    "POST /api/v1/flows": {body: {id: "flow1"}},
    "POST /api/v1/flows/flow1": {body: {id: "flow1", version: {trigger: {name: "trigger", displayName: "Catch webhook", valid: true, settings: {},
      nextAction: {name: "step_1", displayName: $step, valid: true, settings: {}}}}}},
    "DELETE /api/v1/flows/flow1": {body: {}}
  } | '"$1" > "$MOCK_RESPONSES"
}

import() {
  run bash -c 'printf "%s\n" "$PW" | "$@"' _ "$OPSKIT" flows import "$@" --url "$MOCK_URL" --email admin@example.com
}

requests_to() {
  mock_requests | jq -c --arg m "$1" --arg p "$2" 'select(.method == $m and (.path | startswith($p)))'
}

@test "imports a template: sign-in, piece check, create, IMPORT_FLOW with filled placeholders, next steps" {
  PW="$PASSWORD" import example acme --set GREETING=Hi
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] example: valid"* ]]
  [[ "$output" == *"[ok] signed in to ${MOCK_URL} as admin@example.com"* ]]
  [[ "$output" == *"[ok] pieces available: webhook"* ]]
  [[ "$output" == *"[ok] imported \"opskit example — webhook greeting\" (switched off): ${MOCK_URL}/flows/flow1"* ]]
  [[ "$output" == *"No connections needed."* ]]
  [ "$(requests_to POST /api/v1/authentication/sign-in | jq -r '.body | fromjson | .email')" = "admin@example.com" ]
  [ "$(requests_to POST /api/v1/flows | head -n 1 | jq -r '.body | fromjson | .projectId')" = "proj1" ]
  local imported
  imported="$(requests_to POST /api/v1/flows/flow1 | jq -r '.body')"
  [ "$(jq -r .type <<< "$imported")" = "IMPORT_FLOW" ]
  [ "$(jq -r '.request.trigger.nextAction.settings.input.greeting' <<< "$imported")" = "Hi" ]
  [ "$(jq -r '.request.schemaVersion' <<< "$imported")" = "27" ]
  [ "$(requests_to POST /api/v1/flows/flow1 | jq -r .authorization)" = "Bearer tok-123" ]
  ! mock_requests | jq -r .path | grep -q LOCK_AND_PUBLISH
}

@test "the password is used once: never printed, never left on disk, not sent after sign-in" {
  PW="$PASSWORD" import example acme
  [ "$status" -eq 0 ]
  [[ "$output" != *"$PASSWORD"* ]]
  [ "$(requests_to POST /api/v1/authentication/sign-in | jq -r '.body | fromjson | .password')" = "$PASSWORD" ]
  [ "$(mock_requests | grep -c -- "$PASSWORD")" = "1" ]
  [ -z "$(find "$TMPDIR" -maxdepth 1 -name 'tmp.*')" ]
  ! grep -rqF -- "$PASSWORD" "$TMPDIR"
  ! grep -rqF -- "tok-123" "$TMPDIR"
  ! grep -rqF -- "$PASSWORD" "$REG"
  ! grep -rqF -- "tok-123" "$REG"
}

@test "defaults fill placeholders that are not set" {
  PW="$PASSWORD" import example acme
  [ "$(requests_to POST /api/v1/flows/flow1 | jq -r '.body | fromjson | .request.trigger.nextAction.settings.input.greeting')" = "Hello" ]
}

@test "an unknown --set key stops before any request" {
  PW="$PASSWORD" import example acme --set GRETING=Hi
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown placeholder in --set GRETING (this template has: GREETING)"* ]]
  [ "$(mock_requests | wc -l)" = "0" ]
}

@test "a placeholder without default must be set" {
  yq -i 'del(.placeholders[0].default)' "${OPSKIT_FLOWS_DIR}/example/template.yaml"
  PW="$PASSWORD" import example acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing --set GREETING=… (Word the greeting starts with, e.g. Hello)"* ]]
  [ "$(mock_requests | wc -l)" = "0" ]
}

@test "secrets are refused as placeholder values" {
  PW="$PASSWORD" import example acme --set "GREETING=sk-proj-$(printf 'a%.0s' {1..30})"
  [ "$status" -eq 1 ]
  [[ "$output" == *"looks like a key or token; placeholders never hold secrets"* ]]
}

@test "values with quotes and slashes are filled as plain text" {
  PW="$PASSWORD" import example acme --set 'GREETING=Hi "there" \ & /x/'
  [ "$status" -eq 0 ]
  [ "$(requests_to POST /api/v1/flows/flow1 | jq -r '.body | fromjson | .request.trigger.nextAction.settings.input.greeting')" = 'Hi "there" \ & /x/' ]
}

@test "number placeholders are filled as numbers; choices are enforced" {
  yq -i '.placeholders[0].type = "number" | .placeholders[0].example = "1" | .placeholders[0].default = "1"' "${OPSKIT_FLOWS_DIR}/example/template.yaml"
  PW="$PASSWORD" import example acme --set GREETING=hello
  [ "$status" -eq 1 ]
  [[ "$output" == *"GREETING=hello: must be a number"* ]]
  PW="$PASSWORD" import example acme --set GREETING=5
  [ "$status" -eq 0 ]
  [ "$(requests_to POST /api/v1/flows/flow1 | jq -c '.body | fromjson | .request.trigger.nextAction.settings.input.greeting')" = "5" ]
  yq -i '.placeholders[0] = {"key": "GREETING", "description": "Greeting word", "example": "Hello", "choices": ["Hello", "Hi"]}' "${OPSKIT_FLOWS_DIR}/example/template.yaml"
  PW="$PASSWORD" import example acme --set GREETING=Yo
  [ "$status" -eq 1 ]
  [[ "$output" == *"GREETING=Yo: must be one of: Hello Hi"* ]]
}

@test "a wrong password stops before anything is created" {
  responses '."POST /api/v1/authentication/sign-in" = {status: 401, body: {code: "INVALID_CREDENTIALS"}}'
  PW="nope" import example acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"sign-in to ${MOCK_URL} failed: HTTP 401 INVALID_CREDENTIALS"* ]]
  [ -z "$(requests_to POST /api/v1/flows)" ]
}

@test "no password at the prompt" {
  PW="" import example acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"no password given"* ]]
}

@test "an already imported flow is left alone; --again imports a copy" {
  responses '."GET /api/v1/flows?*" = {body: {data: [{id: "old1", version: {displayName: "opskit example — webhook greeting"}}]}}'
  PW="$PASSWORD" import example acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"is already imported (${MOCK_URL}/flows/old1); nothing changed"* ]]
  [ -z "$(requests_to POST /api/v1/flows)" ]
  PW="$PASSWORD" import example acme --again
  [ "$status" -eq 0 ]
  [[ "$output" == *"imported \"opskit example — webhook greeting\""* ]]
}

@test "a failed import removes the half-created flow" {
  responses '."POST /api/v1/flows/flow1" = {status: 404, body: {code: "ENTITY_NOT_FOUND", params: {message: "piece_metadata_not_found pieceName=x"}}}'
  PW="$PASSWORD" import example acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"import of \"opskit example — webhook greeting\" failed: HTTP 404 piece_metadata_not_found"* ]]
  [ -n "$(requests_to DELETE /api/v1/flows/flow1)" ]
}

@test "a pinned piece the stack does not know stops the import" {
  responses '."GET /api/v1/pieces/@activepieces/piece-webhook?*" = {status: 404, body: {message: "piece_metadata_not_found"}}'
  PW="$PASSWORD" import example acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"piece @activepieces/piece-webhook 0.1.42 is not available on this stack"*"may still be syncing"* ]]
  [ -z "$(requests_to POST /api/v1/flows)" ]
}

@test "steps of pieces that need the client's account are listed by name" {
  yq -i '.connections = [{"piece": "@activepieces/piece-webhook", "purpose": "pretend it needs an account", "options": ["Connect"]}]' \
    "${OPSKIT_FLOWS_DIR}/example/template.yaml"
  jq '.flows[0].trigger.valid = false' "${OPSKIT_FLOWS_DIR}/example/flow.json" > "${WORK}/f.json" && mv "${WORK}/f.json" "${OPSKIT_FLOWS_DIR}/example/flow.json"
  PW="$PASSWORD" import example acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"steps to finish in the builder (pick the client's connection and its dropdowns): Catch webhook"* ]]
  [[ "$output" != *"Check name"* ]]
}

custom_template() {
  yq -i '.pieces += [{"name": "@opskit/piece-openai-compatible", "version": "0.1.0", "custom": "packages/pieces/custom/openai-compatible"}]' \
    "${OPSKIT_FLOWS_DIR}/example/template.yaml"
  jq '.flows[0].trigger.nextAction.nextAction = {name: "step_2", displayName: "Ask AI", type: "PIECE", valid: true, lastUpdatedDate: "2026-10-21T00:00:00.000Z",
    settings: {pieceName: "@opskit/piece-openai-compatible", pieceVersion: "0.1.0", actionName: "ask_model", input: {}, propertySettings: {}}}' \
    "${OPSKIT_FLOWS_DIR}/example/flow.json" > "${WORK}/f.json" && mv "${WORK}/f.json" "${OPSKIT_FLOWS_DIR}/example/flow.json"
}

# fake_release: a small but well-formed custom piece archive committed in release/ with its checksum
fake_release() {
  local release="${OPSKIT_REPO_ROOT}/packages/pieces/custom/openai-compatible/release"
  mkdir -p "${WORK}/pkg/package" "$release"
  printf '{"name": "@opskit/piece-openai-compatible", "version": "0.1.0"}\n' > "${WORK}/pkg/package/package.json"
  printf 'fake piece code\n' > "${WORK}/pkg/package/index.js"
  tar -czf "${release}/opskit-piece-openai-compatible-0.1.0.tgz" -C "${WORK}/pkg" package
  (cd "$release" && sha256sum opskit-piece-openai-compatible-0.1.0.tgz > SHA256SUMS)
}

@test "our custom piece is installed from its committed archive when the stack lacks it" {
  custom_template
  export OPSKIT_REPO_ROOT="${WORK}/repo"
  fake_release
  responses '."POST /api/v1/pieces" = {status: 201, body: {}}'
  PW="$PASSWORD" import example acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] installed custom piece @opskit/piece-openai-compatible 0.1.0"* ]]
  local body
  body="$(requests_to POST /api/v1/pieces | jq -r .body)"
  [[ "$body" == *'name="packageType"'*ARCHIVE* ]]
  [[ "$body" == *'name="pieceName"'*'@opskit/piece-openai-compatible'* ]]
  [[ "$body" == *'filename="opskit-piece-openai-compatible-0.1.0.tgz"'* ]]
}

@test "a custom piece already on the stack is not installed again" {
  custom_template
  export OPSKIT_REPO_ROOT="${WORK}/repo"
  fake_release
  responses '."GET /api/v1/pieces/@opskit/piece-openai-compatible?*" = {body: {version: "0.1.0"}}'
  PW="$PASSWORD" import example acme
  [ "$status" -eq 0 ]
  [ -z "$(requests_to POST /api/v1/pieces)" ]
}

@test "a missing custom piece archive stops the import before sign-in" {
  custom_template
  export OPSKIT_REPO_ROOT="${WORK}/repo"
  PW="$PASSWORD" import example acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"custom piece archive missing: packages/pieces/custom/openai-compatible/release/opskit-piece-openai-compatible-0.1.0.tgz"* ]]
  [ "$(mock_requests | wc -l)" = "0" ]
}

@test "only the platform admin can install a custom piece" {
  custom_template
  export OPSKIT_REPO_ROOT="${WORK}/repo"
  fake_release
  responses '."POST /api/v1/authentication/sign-in".body.platformRole = "MEMBER"'
  PW="$PASSWORD" import example acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs the platform admin account"* ]]
}

@test "--print-steps writes the filled flow privately and makes no request" {
  run "$OPSKIT" flows import example acme --set GREETING=Hey --print-steps
  [ "$status" -eq 0 ]
  local out="${REG}/clients/acme/flows/example.json"
  [ -f "$out" ]
  [ "$(stat -c %a "$out")" = "600" ]
  [ "$(jq -r '.flows[0].trigger.nextAction.settings.input.greeting' "$out")" = "Hey" ]
  [[ "$output" == *'Click "Create New" → "Import Flow", choose example.json'* ]]
  [[ "$output" == *"https://acme.example.com"* ]]
  [ "$(mock_requests | wc -l)" = "0" ]
}

@test "an invalid template is never imported" {
  printf 'oops' > "${OPSKIT_FLOWS_DIR}/example/flow.json"
  PW="$PASSWORD" import example acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] example: invalid"* ]]
  [ "$(mock_requests | wc -l)" = "0" ]
}

@test "without a client id --url imports into any builder (practice Codespace)" {
  PW="$PASSWORD" run bash -c 'printf "%s\n" "$PW" | "$@"' _ "$OPSKIT" flows import example --url "$MOCK_URL" --email admin@example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] imported \"opskit example — webhook greeting\" (switched off): ${MOCK_URL}/flows/flow1"* ]]
  run "$OPSKIT" flows import example
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
  run "$OPSKIT" flows import example --url "$MOCK_URL" --print-steps
  [ "$status" -eq 1 ]
}

@test "unknown client" {
  PW="$PASSWORD" import example nobody
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown client: nobody"* ]]
}
