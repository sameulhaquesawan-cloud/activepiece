#!/usr/bin/env bats

load helpers/common

setup() {
  STUB="$(mktemp -d)"
  local util
  for util in bash env uname grep head sed cat dirname basename; do
    ln -s "$(command -v "$util")" "${STUB}/${util}"
  done
  for tool in git curl openssl jq envsubst shellcheck bats age rclone ssh scp node npx; do
    fake "$tool" 'exit 0'
  done
  fake yq 'echo "yq (https://github.com/mikefarah/yq/) version v4.44.3"'
  fake docker 'if [ "$1" = compose ]; then echo "Docker Compose version v2.29.1"; fi; exit 0'
}

teardown() {
  rm -rf "$STUB"
}

fake() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "${STUB}/$1"
  chmod +x "${STUB}/$1"
}

doctor() {
  PATH="$STUB" run "${STUB}/bash" "$OPSKIT" doctor --offline
}

@test "all present: ready" {
  doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] docker: daemon running, compose v2.29.1"* ]]
  [[ "$output" == *"[ok] tools: all present"* ]]
  [[ "$output" == *"[ok] doctor: ready"* ]]
}

@test "missing tool is a failure" {
  rm "${STUB}/age"
  doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] tool missing: age"* ]]
  [[ "$output" == *"[fail] doctor: problems found"* ]]
}

@test "python yq (wrong flavor) is a failure" {
  fake yq 'echo "yq 3.4.3"'
  doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"yq: wrong flavor/version"* ]]
}

@test "docker daemon down is a failure" {
  fake docker 'exit 1'
  doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] docker: daemon not reachable"* ]]
}

@test "compose v1 is a failure" {
  fake docker 'if [ "$1" = compose ]; then echo "docker-compose version 1.29.2"; fi; exit 0'
  doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"v2 or newer required (found: 1.29.2)"* ]]
}

@test "unreachable network is only a warning" {
  fake curl 'printf 000; exit 6'
  PATH="$STUB" run "${STUB}/bash" "$OPSKIT" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] network: cannot reach Activepieces piece catalog"* ]]
}
