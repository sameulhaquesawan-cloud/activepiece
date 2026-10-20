#!/usr/bin/env bats

load helpers/common

CHECK="${OPSKIT_ROOT}/bin/check"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "${FIXTURE}/opskit/bin" "${FIXTURE}/opskit/tests" "${FIXTURE}/.claude/hooks"
  printf '#!/usr/bin/env bash\nset -euo pipefail\necho "ok"\n' > "${FIXTURE}/opskit/bin/good"
  printf '#!/usr/bin/env bats\n\n@test "passes" {\n  true\n}\n' > "${FIXTURE}/opskit/tests/pass.bats"
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "passes on a clean tree" {
  OPSKIT_CHECK_ROOT="$FIXTURE" run "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] shellcheck: 1 files clean"* ]]
  [[ "$output" == *"[ok] check passed"* ]]
}

@test "fails when a script has a shellcheck problem" {
  printf '#!/usr/bin/env bash\necho $undefined_and_unquoted\n' > "${FIXTURE}/opskit/bin/bad"
  OPSKIT_CHECK_ROOT="$FIXTURE" run "$CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] shellcheck found problems"* ]]
}

@test "fails when a bats test fails" {
  printf '#!/usr/bin/env bats\n\n@test "breaks" {\n  false\n}\n' > "${FIXTURE}/opskit/tests/fail.bats"
  OPSKIT_CHECK_ROOT="$FIXTURE" run "$CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] bats: tests failed"* ]]
}

@test "--quick skips tests tagged docker" {
  printf '#!/usr/bin/env bats\n\n# bats test_tags=docker\n@test "needs docker" {\n  false\n}\n' > "${FIXTURE}/opskit/tests/docker.bats"
  OPSKIT_CHECK_ROOT="$FIXTURE" run "$CHECK" --quick
  [ "$status" -eq 0 ]
  [[ "$output" == *"(docker tests skipped)"* ]]
  OPSKIT_CHECK_ROOT="$FIXTURE" run "$CHECK"
  [ "$status" -eq 1 ]
}

@test "unknown option prints usage and fails" {
  run "$CHECK" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: opskit/bin/check"* ]]
}
