#!/usr/bin/env bash
# Round-trip fixtures for selftest: seed a stack with a user, 3 flows (API) and a stored connection,
# then prove a restored copy has the same flows and the connection still decrypts.
# The connection row is written with SQL, encrypted by node inside the app container with the stack's
# own AP_ENCRYPTION_KEY: creating it through the API needs piece metadata from the internet.

RT_FLOWS=("Roundtrip lead capture" "Roundtrip invoice reminder" "Roundtrip failure alert")
RT_CONNECTION="roundtrip-connection"

# shellcheck disable=SC2016
RT_ENCRYPT_JS='
const c = require("crypto");
const iv = c.randomBytes(16);
const x = c.createCipheriv("aes-256-cbc", Buffer.from(process.env.AP_ENCRYPTION_KEY, "binary"), iv);
const data = x.update(JSON.stringify({ type: "SECRET_TEXT", secret_text: process.env.RT_MARKER }), "utf8", "hex") + x.final("hex");
console.log(JSON.stringify({ iv: iv.toString("hex"), data }));
'

# shellcheck disable=SC2016
RT_MATCH_JS='
const c = require("crypto");
const [iv, data] = require("fs").readFileSync(0, "utf8").trim().split(" ");
const d = c.createDecipheriv("aes-256-cbc", Buffer.from(process.env.AP_ENCRYPTION_KEY, "binary"), Buffer.from(iv, "hex"));
const value = JSON.parse(d.update(data, "hex", "utf8") + d.final("utf8"));
console.log(value.secret_text === process.env.RT_MARKER ? "match" : "mismatch");
'

# rt_api <domain> <https port> <method> <path> [token] [json body]
rt_api() {
  local domain="$1" port="$2" method="$3" path="$4" token="${5:-}" body="${6:-}" args
  args=(-sk -m 30 --resolve "${domain}:${port}:127.0.0.1" -X "$method" -H 'content-type: application/json')
  [ -z "$token" ] || args+=(-H "authorization: Bearer ${token}")
  [ -z "$body" ] || args+=(--data "$body")
  curl "${args[@]}" "https://${domain}:${port}/api${path}"
}

rt_sign_in() {
  local domain="$1" port="$2"
  rt_api "$domain" "$port" POST /v1/authentication/sign-in "" \
    "$(jq -nc --arg e "$RT_EMAIL" --arg p "$RT_PASSWORD" '{email: $e, password: $p}')"
}

# rt_seed <host> <id> <domain> <https port>
rt_seed() {
  local host="$1" id="$2" domain="$3" port="$4" auth token project platform user name app value
  RT_EMAIL="roundtrip@example.com"
  RT_PASSWORD="Rt-$(openssl rand -hex 12)"
  RT_MARKER="rt-$(openssl rand -hex 16)"
  auth="$(rt_api "$domain" "$port" POST /v1/authentication/sign-up "" \
    "$(jq -nc --arg e "$RT_EMAIL" --arg p "$RT_PASSWORD" '{email: $e, password: $p, firstName: "Round", lastName: "Trip", newsLetter: false, trackEvents: false}')")"
  token="$(jq -r '.token // empty' <<< "$auth")"
  project="$(jq -r '.projectId // empty' <<< "$auth")"
  platform="$(jq -r '.platformId // empty' <<< "$auth")"
  user="$(jq -r '.id // empty' <<< "$auth")"
  if [ -z "$token" ] || [ -z "$project" ]; then
    log_fail "round trip: sign-up failed"
    return 1
  fi
  for name in "${RT_FLOWS[@]}"; do
    rt_api "$domain" "$port" POST /v1/flows "$token" "$(jq -nc --arg n "$name" --arg p "$project" '{displayName: $n, projectId: $p}')" \
      | jq -e '.id' >/dev/null || { log_fail "round trip: could not create flow ${name}"; return 1; }
  done
  app="$(stack_service_container "$host" "$id" app)"
  value="$(host_run "$host" docker exec -e "RT_MARKER=${RT_MARKER}" "$app" node -e "$RT_ENCRYPT_JS")" \
    || { log_fail "round trip: could not encrypt the test connection"; return 1; }
  stack_psql "$host" "$id" "insert into app_connection (id, \"externalId\", \"pieceName\", value, type, status, \"ownerId\", \"projectIds\", \"displayName\", \"platformId\", scope, \"pieceVersion\") values ('$(openssl rand -hex 10)x', '${RT_CONNECTION}', '@activepieces/piece-http', '${value}'::jsonb, 'SECRET_TEXT', 'ACTIVE', '${user}', ARRAY['${project}'], 'Roundtrip connection', '${platform}', 'PROJECT', '0.0.1')" >/dev/null \
    || { log_fail "round trip: could not store the test connection"; return 1; }
  log_ok "round trip: seeded ${#RT_FLOWS[@]} flows (API) and 1 stored connection"
}

# rt_verify <host> <id> <domain> <https port>: the restored stack has the seeded data
rt_verify() {
  local host="$1" id="$2" domain="$3" port="$4" auth token project flows name app result
  auth="$(rt_sign_in "$domain" "$port")"
  token="$(jq -r '.token // empty' <<< "$auth")"
  project="$(jq -r '.projectId // empty' <<< "$auth")"
  [ -n "$token" ] || { log_fail "round trip: cannot sign in to ${id} with the seeded user"; return 1; }
  flows="$(rt_api "$domain" "$port" GET "/v1/flows?projectId=${project}&limit=50" "$token" | jq -r '.data[].version.displayName')"
  for name in "${RT_FLOWS[@]}"; do
    grep -qxF "$name" <<< "$flows" || { log_fail "round trip: flow '${name}' missing in ${id}"; return 1; }
  done
  rt_api "$domain" "$port" GET "/v1/app-connections?projectId=${project}&limit=50" "$token" \
    | jq -e --arg x "$RT_CONNECTION" '[.data[] | select(.externalId == $x)] | length == 1' >/dev/null \
    || { log_fail "round trip: connection missing in ${id} (API)"; return 1; }
  app="$(stack_service_container "$host" "$id" app)"
  result="$(stack_psql "$host" "$id" "select value->>'iv', value->>'data' from app_connection where \"externalId\" = '${RT_CONNECTION}'" \
    | host_run "$host" docker exec -i -e "RT_MARKER=${RT_MARKER}" "$app" node -e "$RT_MATCH_JS" 2>/dev/null || true)"
  [ "$result" = "match" ] || { log_fail "round trip: stored connection does not decrypt in ${id}"; return 1; }
  log_ok "round trip: ${id} has the ${#RT_FLOWS[@]} flows, sign-in works and the connection decrypts"
}
