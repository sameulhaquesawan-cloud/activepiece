#!/usr/bin/env bats

load helpers/common

MIRROR="${BATS_TEST_DIRNAME}/../bin/image-mirror"

setup() {
  WORK="$(mktemp -d)"
  export OPSKIT_MIRROR_FILE="${WORK}/mirror.yaml"
  printf 'source: ghcr.io/activepieces/activepieces\ntarget: ghcr.io/us/activepieces\ntags: [0.92.2, 0.92.3]\n' > "$OPSKIT_MIRROR_FILE"
  export REGISTRY="${WORK}/registry" DOCKER_LOG="${WORK}/docker.log"
  mkdir -p "$REGISTRY" "${WORK}/bin"
  printf 'sha256:aaa' > "${REGISTRY}/ghcr.io_activepieces_activepieces:0.92.2"
  printf 'sha256:bbb' > "${REGISTRY}/ghcr.io_activepieces_activepieces:0.92.3"
  cat > "${WORK}/bin/docker" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$DOCKER_LOG"
key() { printf '%s' "$1" | tr '/' '_'; }
case "$3" in
  inspect)
    f="${REGISTRY}/$(key "$4")"
    [ -f "$f" ] || exit 1
    printf '{"digest":"%s"}\n' "$(cat "$f")" ;;
  create)
    [ "${FAKE_PUSH_FAIL:-}" != "1" ] || exit 1
    src="$6"; digest="${src#*@}"
    [ "${FAKE_WRONG_DIGEST:-}" != "1" ] || digest="sha256:zzz"
    printf '%s' "$digest" > "${REGISTRY}/$(key "$5")" ;;
esac
SH
  chmod +x "${WORK}/bin/docker"
  export PATH="${WORK}/bin:${PATH}"
}

teardown() {
  rm -rf "$WORK"
}

@test "copies every listed tag by digest, then a second run copies nothing" {
  run "$MIRROR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"copied ghcr.io/activepieces/activepieces:0.92.2 → ghcr.io/us/activepieces:0.92.2 (sha256:aaa)"* ]]
  [[ "$output" == *"copied ghcr.io/activepieces/activepieces:0.92.3 → ghcr.io/us/activepieces:0.92.3 (sha256:bbb)"* ]]
  grep -q 'imagetools create --tag ghcr.io/us/activepieces:0.92.3 ghcr.io/activepieces/activepieces@sha256:bbb' "$DOCKER_LOG"
  : > "$DOCKER_LOG"
  run "$MIRROR"
  [ "$status" -eq 0 ]
  ! grep -q create "$DOCKER_LOG"
}

@test "--check reports a missing tag and writes nothing" {
  run "$MIRROR" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"[fail] ghcr.io/us/activepieces:0.92.2 missing, source is sha256:aaa"* ]]
  ! grep -q create "$DOCKER_LOG"
}

@test "a failed push, a digest mismatch and an unknown source tag fail the run" {
  FAKE_PUSH_FAIL=1 run "$MIRROR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not copy"* ]]
  FAKE_WRONG_DIGEST=1 run "$MIRROR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has digest sha256:zzz after the copy, expected sha256:aaa"* ]]
  printf 'source: ghcr.io/activepieces/activepieces\ntarget: ghcr.io/us/activepieces\ntags: [9.9.9]\n' > "$OPSKIT_MIRROR_FILE"
  run "$MIRROR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghcr.io/activepieces/activepieces:9.9.9 not found"* ]]
}

@test "the committed mirror list has the pinned release and a target the client schema allows" {
  local pinned target
  pinned="$(sed -n 's/^| Pinned release tag | \(.*\) |$/\1/p' "${OPSKIT_ROOT}/../docs/UPSTREAM_CHANGES.md" | head -n 1)"
  target="$(yq -r .target "${OPSKIT_ROOT}/image/mirror.yaml")"
  yq -e ".tags[] | select(. == \"${pinned}\")" "${OPSKIT_ROOT}/image/mirror.yaml" >/dev/null
  jq -e --arg t "$target" '.properties.image.properties.repo.enum | index($t)' "${OPSKIT_ROOT}/schema/client.schema.json" >/dev/null
}
