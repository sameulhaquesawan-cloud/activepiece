#!/usr/bin/env bash
# summary: after an upstream sync: re-verify the Activepieces facts opskit depends on (source, optional image)

sync_check_usage() {
  cat <<'USAGE'
Usage: opskit sync-check [--tree <dir>] [--image <x.y.z>]

Step 7 of docs/UPSTREAM_SYNC.md as a script. Checks a source tree (default: this repo) for every
upstream fact opskit relies on: flow run statuses, health route, worker poll log line, the secrets
upstream's deploy script generates, IPv6 listen address, piece sync source and archive install,
piece release bounds, Tables API, user identity table, connection encryption scheme, migrations
table, rollback tool, breaking-changes page, Dockerfile migration manifest, and the fork ledger
(only opskit-* workflows, .claude/settings.json rows #1–#2). --image also checks inside that
ghcr.io/activepieces/activepieces image (manifest, rollback tool, compiled migrations).
Prints one [ok]/[fail] per fact; exit 1 if any fails. Changes nothing.
USAGE
}

# sync_fact <label> <file (relative)> <fixed string>...: every string occurs in the file
sync_fact() {
  local label="$1" file="${SYNC_TREE}/$2" missing=() want
  shift 2
  if [ ! -f "$file" ]; then
    log_fail "${label}: ${file#"${SYNC_TREE}"/} is gone"
    return 1
  fi
  for want in "$@"; do
    grep -qF -- "$want" "$file" || missing+=("$want")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log_fail "${label}: ${file#"${SYNC_TREE}"/} no longer has: ${missing[*]}"
    return 1
  fi
  log_ok "${label}"
}

sync_check_tree() {
  local failed=0 api="packages/server/api/src" workflows
  sync_fact "flow run statuses (detector, smoke, templates e2e)" packages/core/execution/src/lib/flow-run/execution/flow-execution.ts \
    "FAILED = 'FAILED'" "INTERNAL_ERROR = 'INTERNAL_ERROR'" "TIMEOUT = 'TIMEOUT'" "MEMORY_LIMIT_EXCEEDED = 'MEMORY_LIMIT_EXCEEDED'" \
    "QUOTA_EXCEEDED = 'QUOTA_EXCEEDED'" "LOG_SIZE_EXCEEDED = 'LOG_SIZE_EXCEEDED'" "SUCCEEDED = 'SUCCEEDED'" "RUNNING = 'RUNNING'" "QUEUED = 'QUEUED'" || failed=1
  sync_fact "health route /api/v1/health" "${api}/app/health/health.module.ts" "prefix: '/v1/health'" || failed=1
  sync_fact "worker registration log line" "${api}/app/workers/rpc/worker-rpc-service.ts" "Poll request received" || failed=1
  sync_fact "secrets of upstream's deploy script" tools/deploy.sh "AP_API_KEY=" "AP_POSTGRES_PASSWORD=" "AP_JWT_SECRET=" "ENCRYPTION_KEY=" || failed=1
  sync_fact "app listens on IPv6 (practice IPv4 shim)" "${api}/main.ts" "host: '::'" || failed=1
  sync_fact "piece sync source" "${api}/app/pieces/piece-sync-service.ts" "https://cloud.activepieces.com/api/v1/pieces" || failed=1
  sync_fact "piece archive install (openai-compatible)" "${api}/app/pieces/piece-install-service.ts" "pieceArchive" || failed=1
  sync_fact "piece release bounds (upgrade follow-ups)" "${api}/app/pieces/metadata/piece-metadata-entity.ts" \
    "minimumSupportedRelease" "maximumSupportedRelease" || failed=1
  sync_fact "Tables API (tables templates)" "${api}/app/tables/tables.module.ts" \
    "prefix: '/v1/tables'" "prefix: '/v1/fields'" "prefix: '/v1/records'" || failed=1
  sync_fact "user identity table (staging password)" "${api}/app/authentication/user-identity/user-identity-entity.ts" \
    "name: 'user_identity'" "password:" || failed=1
  sync_fact "connection encryption scheme (decrypt checks)" "${api}/app/helper/encryption.ts" "aes-256-cbc" || failed=1
  sync_fact "rollback tool" "${api}/rollback.ts" "--manifest" || failed=1
  sync_fact "migration manifest built into the image" Dockerfile "migration-manifest" || failed=1
  sync_fact "breaking-changes page (upgrade plan)" docs/install/reference/breaking-changes.mdx "## " || failed=1
  if grep -rqF "migrationsTableName" "${SYNC_TREE}/${api}/app/database"/*.ts 2>/dev/null; then
    log_fail "migrations table: upstream now sets migrationsTableName (smoke_schema reads table migrations)"
    failed=1
  else
    log_ok "migrations table name is TypeORM's default (migrations)"
  fi
  workflows="$(find "${SYNC_TREE}/.github/workflows" -type f ! -name 'opskit-*' 2>/dev/null | sed "s|^${SYNC_TREE}/||")"
  if [ -n "$workflows" ]; then
    log_fail "ledger #4: upstream workflows are back: $(paste -sd' ' <<< "$workflows")"
    failed=1
  else
    log_ok "ledger #4: only opskit-* workflows"
  fi
  if jq -e '.hooks.SessionStart and .enabledPlugins["ponytail@ponytail"] == false and .enabledPlugins["craftspace@craftspace"] == false and (has("mcpServers") | not)' \
    "${SYNC_TREE}/.claude/settings.json" >/dev/null 2>&1; then
    log_ok "ledger #1–#2: .claude/settings.json hook and plugin settings"
  else
    log_fail "ledger #1–#2: re-apply the SessionStart hook / plugins false / no mcpServers in .claude/settings.json"
    failed=1
  fi
  return "$failed"
}

# sync_check_image <tag>: facts inside the published image (pulled if missing)
sync_check_image() {
  local image="ghcr.io/activepieces/activepieces:$1" out
  docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >/dev/null || { log_fail "cannot pull ${image}"; return 1; }
  # shellcheck disable=SC2016
  out="$(docker run --rm --entrypoint sh "$image" -c '
    d=/usr/src/app/packages/server/api/dist/src
    jq_ok=$(node -e "const m=require(\"$d/migration-manifest.json\"); console.log(Array.isArray(m) && m.length > 0 ? m.length : 0)" 2>/dev/null)
    echo "manifest ${jq_ok:-0}"
    [ -f "$d/rollback.js" ] && echo "rollback yes"
    echo "migrations $(ls "$d/app/database/migration/postgres"/*.js 2>/dev/null | wc -l)"' 2>/dev/null)"
  local failed=0 count
  count="$(sed -n 's/^manifest //p' <<< "$out")"
  if [ "${count:-0}" -gt 0 ]; then log_ok "image $1: migration manifest (${count} entries)"; else log_fail "image $1: no migration manifest at dist/src/migration-manifest.json"; failed=1; fi
  if grep -q '^rollback yes' <<< "$out"; then log_ok "image $1: dist/src/rollback.js"; else log_fail "image $1: rollback tool missing"; failed=1; fi
  count="$(sed -n 's/^migrations //p' <<< "$out")"
  if [ "${count:-0}" -gt 0 ]; then log_ok "image $1: ${count} compiled migrations (breaking flag source)"; else log_fail "image $1: compiled migrations not found"; failed=1; fi
  return "$failed"
}

cmd_main() {
  local image="" failed=0
  SYNC_TREE="$(cd "${OPSKIT_ROOT}/.." && pwd)"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) sync_check_usage; return 0 ;;
      --tree) SYNC_TREE="$(cd "${2:-.}" && pwd)"; shift 2 ;;
      --image) image="${2:-}"; shift 2 ;;
      *) sync_check_usage >&2; return 1 ;;
    esac
  done
  sync_check_tree || failed=1
  if [ -n "$image" ]; then
    sync_check_image "$image" || failed=1
  fi
  if [ "$failed" -ne 0 ]; then
    log_fail "sync-check: some facts changed; update opskit and docs/ASSUMPTIONS.md before using this release"
    return 1
  fi
  log_ok "sync-check passed"
}
