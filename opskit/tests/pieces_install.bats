#!/usr/bin/env bats

load helpers/common
load helpers/mock_http
load helpers/registry

setup() {
  make_registry
  new_demo_client acme acme.example.com
  WORK="$(mktemp -d)"
  export OPSKIT_PIECES_DIR="${WORK}/pieces"
  export OPSKIT_FLOWS_DIR="${WORK}/flows"
  mkdir -p "${OPSKIT_PIECES_DIR}/files" "$OPSKIT_FLOWS_DIR" "${WORK}/pkg/package"
  local name file
  printf 'pieces:\n' > "${OPSKIT_PIECES_DIR}/pack.yaml"
  for name in webhook tables; do
    file="${OPSKIT_PIECES_DIR}/files/activepieces-piece-${name}-1.0.0.tgz"
    printf '{"name": "@activepieces/piece-%s", "version": "1.0.0"}\n' "$name" > "${WORK}/pkg/package/package.json"
    tar -czf "$file" -C "${WORK}/pkg" package
    printf -- '  - name: "@activepieces/piece-%s"\n    version: 1.0.0\n    sha256: %s\n' "$name" "$(sha256sum "$file" | cut -d' ' -f1)" >> "${OPSKIT_PIECES_DIR}/pack.yaml"
  done
  export MOCK_RESPONSES="${WORK}/responses.json"
  jq -n '{
    "POST /api/v1/authentication/sign-in": {body: {token: "tok-123", projectId: "proj1", platformRole: "ADMIN"}},
    "GET /api/v1/pieces/@activepieces/piece-webhook?*": {body: {name: "@activepieces/piece-webhook", version: "1.0.0"}},
    "GET /api/v1/pieces/@activepieces/piece-tables?*": {status: 404, body: {message: "piece_metadata_not_found"}},
    "POST /api/v1/pieces": {status: 201, body: {}}
  }' > "$MOCK_RESPONSES"
  start_mock_http
}

teardown() {
  stop_mock_http
  rm -rf "$WORK" "$REG"
}

@test "install adds only the pack pieces the stack does not have, as archives" {
  run bash -c 'printf "pw\n" | "$@"' _ "$OPSKIT" pieces install acme --url "$MOCK_URL" --email admin@example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] installed @activepieces/piece-tables 1.0.0 from our own copy"* ]]
  [[ "$output" == *"1 installed, the rest were already there"* ]]
  [ "$(mock_requests | jq -r 'select(.method == "POST" and .path == "/api/v1/pieces") | .body' | grep -c 'filename="activepieces-piece-tables-1.0.0.tgz"')" = "1" ]
  ! mock_requests | jq -r .body | grep -q 'piece-webhook-1.0.0.tgz'
}

@test "install refuses a client on a release before 0.92.3 before signing in" {
  yq -i '.image.tag = "0.92.2" | .ap_version = "0.92.2"' "${REG}/clients/acme/client.yaml"
  run bash -c 'printf "pw\n" | "$@"' _ "$OPSKIT" pieces install acme --email admin@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"acme runs 0.92.2: our piece pack needs Activepieces 0.92.3 or newer (upgrade first: opskit upgrade acme)"* ]]
  [ -z "$(mock_requests)" ]
}

@test "install refuses a damaged pack before signing in" {
  printf 'x' >> "${OPSKIT_PIECES_DIR}/files/activepieces-piece-tables-1.0.0.tgz"
  run bash -c 'printf "pw\n" | "$@"' _ "$OPSKIT" pieces install acme --url "$MOCK_URL" --email admin@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"file changed since it was added"* ]]
  [ -z "$(mock_requests)" ]
}

@test "install needs the platform admin" {
  jq '."POST /api/v1/authentication/sign-in".body.platformRole = "MEMBER"' "$MOCK_RESPONSES" > "${WORK}/r" && mv "${WORK}/r" "$MOCK_RESPONSES"
  run bash -c 'printf "pw\n" | "$@"' _ "$OPSKIT" pieces install acme --url "$MOCK_URL" --email admin@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs the platform admin account"* ]]
}
