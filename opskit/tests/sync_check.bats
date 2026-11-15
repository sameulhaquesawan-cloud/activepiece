#!/usr/bin/env bats

load helpers/common

FACT_FILES=(
  packages/core/execution/src/lib/flow-run/execution/flow-execution.ts
  packages/server/api/src/app/health/health.module.ts
  packages/server/api/src/app/workers/rpc/worker-rpc-service.ts
  tools/deploy.sh
  packages/server/api/src/main.ts
  packages/server/api/src/app/pieces/piece-sync-service.ts
  packages/server/api/src/app/pieces/piece-install-service.ts
  packages/server/api/src/app/pieces/metadata/piece-metadata-entity.ts
  packages/server/api/src/app/tables/tables.module.ts
  packages/server/api/src/app/authentication/user-identity/user-identity-entity.ts
  packages/server/api/src/app/helper/encryption.ts
  packages/server/api/src/rollback.ts
  Dockerfile
  docs/install/reference/breaking-changes.mdx
  .claude/settings.json
  .github/workflows/opskit-ci.yml
)

setup() {
  TREE="$(mktemp -d)"
  local repo file
  repo="$(cd "${OPSKIT_ROOT}/.." && pwd)"
  for file in "${FACT_FILES[@]}"; do
    mkdir -p "${TREE}/$(dirname "$file")"
    cp "${repo}/${file}" "${TREE}/${file}"
  done
  mkdir -p "${TREE}/packages/server/api/src/app/database"
}

teardown() {
  rm -rf "$TREE"
}

@test "the pinned source passes every fact" {
  run "$OPSKIT" sync-check --tree "$TREE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] sync-check passed"* ]]
  [ "$(grep -c '^\[ok\]' <<< "$output")" = "18" ]
}

@test "a renamed status, a moved file, a new migrations table and an upstream workflow are each reported" {
  sed -i "s/TIMEOUT = 'TIMEOUT'/TIMED_OUT = 'TIMED_OUT'/" "${TREE}/packages/core/execution/src/lib/flow-run/execution/flow-execution.ts"
  rm "${TREE}/packages/server/api/src/app/health/health.module.ts"
  echo "migrationsTableName: 'typeorm_migrations'," > "${TREE}/packages/server/api/src/app/database/postgres-connection.ts"
  touch "${TREE}/.github/workflows/release.yml"
  run "$OPSKIT" sync-check --tree "$TREE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] flow run statuses (detector, smoke, templates e2e): packages/core/execution/src/lib/flow-run/execution/flow-execution.ts no longer has: TIMEOUT = 'TIMEOUT'"* ]]
  [[ "$output" == *"[fail] health route /api/v1/health: packages/server/api/src/app/health/health.module.ts is gone"* ]]
  [[ "$output" == *"[fail] migrations table: upstream now sets migrationsTableName"* ]]
  [[ "$output" == *"[fail] ledger #4: upstream workflows are back: .github/workflows/release.yml"* ]]
  [[ "$output" == *"[fail] sync-check: some facts changed"* ]]
}

@test "ledger rows #1-#2 must be re-applied to .claude/settings.json" {
  jq '.enabledPlugins["ponytail@ponytail"] = true' "${TREE}/.claude/settings.json" > "${TREE}/s" && mv "${TREE}/s" "${TREE}/.claude/settings.json"
  run "$OPSKIT" sync-check --tree "$TREE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] ledger #1–#2: re-apply the SessionStart hook"* ]]
}

@test "usage" {
  run "$OPSKIT" sync-check --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: opskit sync-check"* ]]
}
