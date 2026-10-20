#!/usr/bin/env bats

load helpers/common

setup() {
  source "${OPSKIT_ROOT}/lib/log.sh"
  source "${OPSKIT_ROOT}/lib/render.sh"
  WORK="$(mktemp -d)"
  printf 'image: ${IMAGE}\nedition: ${AP_EDITION}\nliteral: $HOME stays\n' > "${WORK}/t.tmpl"
}

teardown() {
  rm -rf "$WORK"
}

@test "renders all variables and leaves non-braced dollars alone" {
  IMAGE="activepieces/activepieces:0.92.3" AP_EDITION=ce run render_template "${WORK}/t.tmpl" "${WORK}/out.yml"
  [ "$status" -eq 0 ]
  [ "$(cat "${WORK}/out.yml")" = "$(printf 'image: activepieces/activepieces:0.92.3\nedition: ce\nliteral: $HOME stays')" ]
}

@test "missing variable fails, names it, and writes no output" {
  IMAGE="secret-looking-value" run render_template "${WORK}/t.tmpl" "${WORK}/out.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolved variables: AP_EDITION"* ]]
  [[ "$output" != *"secret-looking-value"* ]]
  [ ! -e "${WORK}/out.yml" ]
}

@test "empty variable counts as unresolved" {
  IMAGE="" AP_EDITION=ce run render_template "${WORK}/t.tmpl" "${WORK}/out.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolved variables: IMAGE"* ]]
}

@test "missing template fails" {
  run render_template "${WORK}/nope.tmpl" "${WORK}/out.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"template not found"* ]]
}
