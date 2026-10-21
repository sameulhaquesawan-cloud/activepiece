#!/usr/bin/env bash
# opskit flows import: fill placeholders, sign in once (password read at the prompt, never stored),
# install our custom pieces, create each flow and IMPORT_FLOW it. Imported flows stay unpublished (off).
# FLOWS_BASE_URL and FLOWS_CURL_ARGS are set by the command; secrets go to curl through files in a
# private temp dir (FLOWS_TMP), never on the command line.

FLOWS_CURL_ARGS=()

# flows_fill <template dir> <values json>: filled flow.json on stdout
flows_fill() {
  local dir="$1" values="$2"
  jq --argjson vals "$values" '
    walk(if type == "string" and test("^\\{\\{OPSKIT:[A-Z][A-Z0-9_]*\\}\\}$") and ($vals[.[9:-2]] | type) == "number" then $vals[.[9:-2]]
    elif type == "string" then
      reduce ($vals | to_entries[]) as $e (.; gsub("\\{\\{OPSKIT:" + $e.key + "\\}\\}"; $e.value | tostring))
    else . end)' "${dir}/flow.json"
}

# flows_values <template dir> <K=V>...: JSON object of every declared placeholder, or problems on stderr
flows_values() {
  local dir="$1" values='{}' pair key value declared added failed=0
  shift
  declared="$(yq -r '.placeholders[]?.key' "${dir}/template.yaml")"
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    if [ "$key" = "$pair" ] || ! grep -qxF "$key" <<< "$declared"; then
      log_fail "unknown placeholder in --set ${key} (this template has: $(paste -sd ' ' <<< "${declared:-none}"))"
      failed=1
      continue
    fi
    if flows_looks_secret "$value"; then
      log_fail "--set ${key}: looks like a key or token; placeholders never hold secrets (the client adds them as a connection)"
      failed=1
      continue
    fi
    if added="$(flows_value_add "$dir" "$values" "$key" "$value")"; then values="$added"; else failed=1; fi
  done
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    [ "$(jq -r --arg k "$key" 'has($k)' <<< "$values")" = "true" ] && continue
    value="$(KEY="$key" yq -r '.placeholders[] | select(.key == strenv(KEY)) | .default // ""' "${dir}/template.yaml")"
    if [ -z "$value" ]; then
      log_fail "missing --set ${key}=… ($(KEY="$key" yq -r '.placeholders[] | select(.key == strenv(KEY)) | .description + ", e.g. " + .example' "${dir}/template.yaml"))"
      failed=1
      continue
    fi
    if added="$(flows_value_add "$dir" "$values" "$key" "$value")"; then values="$added"; else failed=1; fi
  done <<< "$declared"
  [ "$failed" -eq 0 ] || return 1
  printf '%s' "$values"
}

# flows_value_add <template dir> <values json> <key> <value>: values json with key added (typed, checked)
flows_value_add() {
  local dir="$1" values="$2" key="$3" value="$4" kind choices
  kind="$(KEY="$key" yq -r '.placeholders[] | select(.key == strenv(KEY)) | .type // "string"' "${dir}/template.yaml")"
  choices="$(KEY="$key" yq -r '.placeholders[] | select(.key == strenv(KEY)) | .choices // [] | .[]' "${dir}/template.yaml")"
  if [ -n "$choices" ] && ! grep -qxF -- "$value" <<< "$choices"; then
    log_fail "${key}=${value}: must be one of: $(paste -sd ' ' <<< "$choices")"
    return 1
  fi
  if [ "$kind" = "number" ]; then
    [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { log_fail "${key}=${value}: must be a number"; return 1; }
    jq -c --arg k "$key" --argjson v "$value" '. + {($k): $v}' <<< "$values"
  else
    jq -c --arg k "$key" --arg v "$value" '. + {($k): $v}' <<< "$values"
  fi
}

flows_looks_secret() {
  local pattern
  for pattern in "${FLOWS_SECRET_PATTERNS[@]}"; do
    grep -qE -- "$pattern" <<< "$1" && return 0
  done
  return 1
}

# flows_api <method> <path> [body file]: response body on stdout, HTTP status in FLOWS_TMP/status
flows_api() {
  local method="$1" path="$2" body="${3:-}" args
  args=(-sS -m 60 -X "$method" -o "${FLOWS_TMP}/response" -w '%{http_code}' "${FLOWS_CURL_ARGS[@]}")
  [ ! -f "${FLOWS_TMP}/auth-header" ] || args+=(-H "@${FLOWS_TMP}/auth-header")
  [ -z "$body" ] || args+=(-H 'content-type: application/json' --data-binary "@${body}")
  curl "${args[@]}" "${FLOWS_BASE_URL}/api${path}" > "${FLOWS_TMP}/status" 2>"${FLOWS_TMP}/curl-error" || printf '000' > "${FLOWS_TMP}/status"
  cat "${FLOWS_TMP}/response" 2>/dev/null || true
}

flows_status() {
  cat "${FLOWS_TMP}/status"
}

flows_api_error() {
  local message
  message="$(jq -r '.message // .params.message // .code // empty' "${FLOWS_TMP}/response" 2>/dev/null || true)"
  [ -n "$message" ] || message="$(head -c 200 "${FLOWS_TMP}/curl-error" 2>/dev/null || true)"
  printf 'HTTP %s %s' "$(flows_status)" "${message:0:200}"
}

# flows_sign_in <email>: reads the password from the prompt (stdin), keeps only the session token
flows_sign_in() {
  local email="$1" password="" response
  IFS= read -rs -p "Admin password for ${email} (not stored): " password || true
  [ ! -t 0 ] || printf '\n' >&2
  [ -n "$password" ] || { log_fail "no password given"; return 1; }
  ( umask 077 && jq -nc --arg e "$email" --arg p "$password" '{email: $e, password: $p}' > "${FLOWS_TMP}/sign-in.json" )
  password=""
  response="$(flows_api POST /v1/authentication/sign-in "${FLOWS_TMP}/sign-in.json")"
  rm -f "${FLOWS_TMP}/sign-in.json"
  if [ "$(flows_status)" != "200" ]; then
    log_fail "sign-in to ${FLOWS_BASE_URL} failed: $(flows_api_error)"
    return 1
  fi
  ( umask 077 && printf 'authorization: Bearer %s\n' "$(jq -r '.token' <<< "$response")" > "${FLOWS_TMP}/auth-header" )
  FLOWS_PROJECT="$(jq -r '.projectId // empty' <<< "$response")"
  FLOWS_PLATFORM_ROLE="$(jq -r '.platformRole // empty' <<< "$response")"
  [ -n "$FLOWS_PROJECT" ] || { log_fail "sign-in worked but the user has no project"; return 1; }
  log_ok "signed in to ${FLOWS_BASE_URL} as ${email}"
}

# flows_custom_archive <custom dir> <name> <version>: the committed release/ archive, else a local dist/ build
flows_custom_archive() {
  local custom="$1" name="$2" version="$3" base file
  base="${OPSKIT_REPO_ROOT:-$(cd "${OPSKIT_ROOT}/.." && pwd)}/${custom}"
  file="$(sed -E 's#^@##; s#/#-#' <<< "$name")-${version}.tgz"
  if [ -f "${base}/release/${file}" ] || [ ! -f "${base}/dist/${file}" ]; then
    printf '%s/release/%s' "$base" "$file"
  else
    printf '%s/dist/%s' "$base" "$file"
  fi
}

# flows_ensure_pieces <template dir>: install our custom pieces, check every pinned version is known
flows_ensure_pieces() {
  local dir="$1" name version custom archive
  while IFS=$'\t' read -r name version custom; do
    [ -n "$name" ] || continue
    flows_api GET "/v1/pieces/${name}?version=${version}&projectId=${FLOWS_PROJECT}" >/dev/null
    if [ "$(flows_status)" = "200" ] && [ "$(jq -r '.version // empty' "${FLOWS_TMP}/response")" = "$version" ]; then
      continue
    fi
    if [ -z "$custom" ]; then
      log_fail "piece ${name} ${version} is not available on this stack ($(flows_api_error)); pieces may still be syncing — retry in a minute, or the template needs re-pinning for this Activepieces version"
      return 1
    fi
    [ "$FLOWS_PLATFORM_ROLE" = "ADMIN" ] || { log_fail "installing ${name} needs the platform admin account"; return 1; }
    archive="$(flows_custom_archive "$custom" "$name" "$version")"
    [ -f "$archive" ] || { log_fail "piece archive not built: ${archive} (see ${custom}/README.md, 'Build the archive')"; return 1; }
    curl -sS -m 120 -o "${FLOWS_TMP}/response" -w '%{http_code}' "${FLOWS_CURL_ARGS[@]}" -H "@${FLOWS_TMP}/auth-header" \
      -F packageType=ARCHIVE -F scope=PLATFORM --form-string "pieceName=${name}" -F "pieceVersion=${version}" \
      -F "pieceArchive=@${archive};type=application/gzip" "${FLOWS_BASE_URL}/api/v1/pieces" > "${FLOWS_TMP}/status" 2>"${FLOWS_TMP}/curl-error" \
      || printf '000' > "${FLOWS_TMP}/status"
    case "$(flows_status)" in
      200|201) log_ok "installed custom piece ${name} ${version}" ;;
      *) log_fail "could not install ${name} ${version}: $(flows_api_error)"; return 1 ;;
    esac
  done < <(yq -r '.pieces[] | [.name, .version, .custom // ""] | @tsv' "${dir}/template.yaml")
  log_ok "pieces available: $(yq -r '[.pieces[].name | sub("^@[a-z]+/piece-"; "")] | join(", ")' "${dir}/template.yaml")"
}

# flows_existing_id <display name>: id of a flow with that name in the project, if any
flows_existing_id() {
  flows_api GET "/v1/flows?projectId=${FLOWS_PROJECT}&limit=100" \
    | jq -r --arg n "$1" '[.data[]? | select(.version.displayName == $n)][0].id // empty' 2>/dev/null || true
}

# flows_import_one <filled flow file> <index> <again>: creates and imports flows[index]
flows_import_one() {
  local filled="$1" index="$2" again="$3" name existing id body invalid
  name="$(jq -r --argjson i "$index" '.flows[$i].displayName' "$filled")"
  existing="$(flows_existing_id "$name")"
  if [ -n "$existing" ] && [ "$again" != "1" ]; then
    log_warn "\"${name}\" is already imported (${FLOWS_BASE_URL}/flows/${existing}); nothing changed (--again imports another copy)"
    return 0
  fi
  body="${FLOWS_TMP}/create.json"
  jq -nc --arg n "$name" --arg p "$FLOWS_PROJECT" '{displayName: $n, projectId: $p}' > "$body"
  id="$(flows_api POST /v1/flows "$body" | jq -r '.id // empty' 2>/dev/null || true)"
  if [ -z "$id" ]; then
    log_fail "could not create flow \"${name}\": $(flows_api_error)"
    return 1
  fi
  body="${FLOWS_TMP}/import.json"
  jq -c --argjson i "$index" '.flows[$i] | {type: "IMPORT_FLOW", request: {displayName, trigger, schemaVersion, notes: (.notes // [])}}' "$filled" > "$body"
  flows_api POST "/v1/flows/${id}" "$body" > "${FLOWS_TMP}/imported.json"
  if [ "$(flows_status)" != "200" ]; then
    log_fail "import of \"${name}\" failed: $(flows_api_error)"
    flows_api DELETE "/v1/flows/${id}" >/dev/null
    log_info "removed the half-created flow ${id}"
    return 1
  fi
  invalid="$(jq -r --argjson i "$index" --argjson pieces "$FLOWS_CONNECTION_PIECES" \
    '[.flows[$i].trigger | .. | objects | select(has("settings") and (.settings.pieceName as $p | $pieces | index($p)))
      | .displayName] | join(", ")' "$filled")"
  log_ok "imported \"${name}\" (switched off): ${FLOWS_BASE_URL}/flows/${id}"
  [ -z "$invalid" ] || log_info "     steps to finish in the builder (pick the client's connection and its dropdowns): ${invalid}"
}

flows_next_steps() {
  local dir="$1" connections
  connections="$(yq -r '.connections[]? | "  - " + (.piece | sub("^@[a-z]+/piece-"; "")) + ": " + .purpose + "\n      ways to connect: " + (.options | join(" | "))' "${dir}/template.yaml")"
  printf '\nNext steps (the client, or you with the client on a call):\n'
  if [ -n "$connections" ]; then
    printf '1. In the builder, Connections → New connection, for each:\n%s\n' "$connections"
    printf '2. Open the flow, pick the connection in every step marked above.\n'
  else
    printf '1. No connections needed.\n2. Open the flow.\n'
  fi
  printf '3. Test it (README.md "Sample run" / test/ payloads), then Publish to switch it on.\n'
  printf '4. Watch the first real run; failures alert you within 5 minutes.\n'
}

flows_print_steps() {
  local dir="$1" filled="$2" out="$3"
  ( umask 077 && cp "$filled" "$out" )
  log_ok "filled template written to ${out} (contains client settings; do not commit it)"
  printf '\nImport in the builder (%s):\n' "$FLOWS_BASE_URL"
  printf '1. Sign in as the admin, open the flows list (Automations).\n'
  printf '2. Click "Create New" → "Import Flow", choose %s, click "Import".\n' "$(basename "$out")"
  printf '3. The flow opens unpublished (off).\n'
  flows_next_steps "$dir"
}
