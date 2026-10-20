#!/usr/bin/env bats

load helpers/common

setup() {
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/fork.sh"
  REPO="$(mktemp -d)"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name t
  mkdir -p "${REPO}/packages/server" "${REPO}/docs"
  echo upstream > "${REPO}/packages/server/app.ts"
  echo upstream > "${REPO}/docker-compose.yml"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm upstream
  git -C "$REPO" tag 1.2.3
  cat > "${REPO}/docs/UPSTREAM_CHANGES.md" <<'MD'
| Pinned release tag | 1.2.3 |

## Patch ledger
| # | Date | Upstream file(s) | Why |
|---|---|---|---|
MD
  mkdir -p "${REPO}/opskit/bin"
  echo ours > "${REPO}/opskit/bin/tool"
}

teardown() {
  rm -rf "$REPO"
}

@test "only our new files: passes" {
  run fork_check "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] fork: only our paths"* ]]
}

@test "unledgered upstream edit fails" {
  echo patched >> "${REPO}/packages/server/app.ts"
  run fork_check "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream file changed without a ledger row: packages/server/app.ts"* ]]
}

@test "ledgered upstream edit passes" {
  echo patched >> "${REPO}/packages/server/app.ts"
  echo '| 1 | 2026-10-20 | `packages/server/app.ts` | reason |' >> "${REPO}/docs/UPSTREAM_CHANGES.md"
  run fork_check "$REPO"
  [ "$status" -eq 0 ]
}

@test "deleting an upstream file needs a ledger row too" {
  rm "${REPO}/docker-compose.yml"
  run fork_check "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"without a ledger row: docker-compose.yml"* ]]
}

@test "new file outside our paths fails" {
  echo x > "${REPO}/packages/server/new.ts"
  run fork_check "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"new file outside our paths: packages/server/new.ts"* ]]
}

@test "missing pinned tag only warns" {
  git -C "$REPO" tag -d 1.2.3 >/dev/null
  run fork_check "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] fork: pinned tag"* ]]
}
