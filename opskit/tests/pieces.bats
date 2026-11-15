#!/usr/bin/env bats

load helpers/common

setup() {
  WORK="$(mktemp -d)"
  export OPSKIT_PIECES_DIR="${WORK}/pieces"
  export OPSKIT_FLOWS_DIR="${WORK}/flows"
  export OPSKIT_NPM_REGISTRY_URL="https://npm.test"
  NPM="${WORK}/npm"
  mkdir -p "$OPSKIT_PIECES_DIR" "$OPSKIT_FLOWS_DIR/demo" "${WORK}/bin" "$NPM"
  printf 'activepieces: 0.92.3\npieces:\n  - name: "@activepieces/piece-webhook"\n    version: 0.1.42\n  - name: "@opskit/piece-x"\n    version: 0.1.0\n    custom: packages/pieces/custom/x\n' \
    > "${OPSKIT_FLOWS_DIR}/demo/template.yaml"
  cat > "${WORK}/bin/curl" <<SH
#!/usr/bin/env bash
out=""; url=""
while [ "\$#" -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2 ;; -m) shift 2 ;; -*) shift ;; *) url="\$1"; shift ;; esac; done
file="${NPM}/\$(printf '%s' "\${url#https://npm.test/}" | tr '/' '_')"
[ -f "\$file" ] || exit 22
cp "\$file" "\$out"
SH
  chmod +x "${WORK}/bin/curl"
  export PATH="${WORK}/bin:${PATH}"
}

teardown() {
  rm -rf "$WORK"
}

# publish <name> <version> [package.json jq edit] [integrity override]: a fake npm entry
publish() {
  local name="$1" version="$2" short pkg tgz integrity
  short="${name#*/}"
  pkg="${WORK}/pkg-${short}-${version}"
  mkdir -p "${pkg}/package"
  jq -n --arg n "$name" --arg v "$version" '{name: $n, version: $v, dependencies: {}}' | jq "${3:-.}" > "${pkg}/package/package.json"
  printf 'code\n' > "${pkg}/package/index.js"
  tgz="${NPM}/$(printf '%s/-/%s-%s.tgz' "$name" "$short" "$version" | tr '/' '_')"
  tar -czf "$tgz" -C "$pkg" package
  integrity="${4:-sha512-$(openssl dgst -sha512 -binary "$tgz" | base64 -w 0)}"
  jq -n --arg t "https://npm.test/${name}/-/${short}-${version}.tgz" --arg i "$integrity" '{dist: {tarball: $t, integrity: $i}}' \
    > "${NPM}/$(printf '%s/%s' "$name" "$version" | tr '/' '_')"
}

@test "add stores the archive, records its sha256 and is idempotent; check then passes" {
  publish "@activepieces/piece-webhook" 0.1.42
  run "$OPSKIT" pieces add "@activepieces/piece-webhook" 0.1.42
  [ "$status" -eq 0 ]
  local file="${OPSKIT_PIECES_DIR}/files/activepieces-piece-webhook-0.1.42.tgz"
  [ -s "$file" ]
  [ "$(yq -r '.pieces[0].sha256' "${OPSKIT_PIECES_DIR}/pack.yaml")" = "$(sha256sum "$file" | cut -d' ' -f1)" ]
  run "$OPSKIT" pieces add "@activepieces/piece-webhook" 0.1.42
  [ "$status" -eq 0 ]
  [[ "$output" == *"already in the pack"* ]]
  [ "$(yq '.pieces | length' "${OPSKIT_PIECES_DIR}/pack.yaml")" = "1" ]
  run "$OPSKIT" pieces check
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ok] piece pack: 1 pieces, files intact, every template pin included"* ]]
}

@test "add refuses a damaged download, a piece with npm dependencies and a wrong package" {
  publish "@activepieces/piece-webhook" 0.1.42 '.' "sha512-AAAA"
  run "$OPSKIT" pieces add "@activepieces/piece-webhook" 0.1.42
  [ "$status" -eq 1 ]
  [[ "$output" == *"checksum does not match npm's"* ]]
  publish "@activepieces/piece-webhook" 0.1.42 '.dependencies = {"axios": "1.0.0"}'
  run "$OPSKIT" pieces add "@activepieces/piece-webhook" 0.1.42
  [ "$status" -eq 1 ]
  [[ "$output" == *"has npm dependencies"* ]]
  publish "@activepieces/piece-webhook" 0.1.42 '.version = "9.9.9"'
  run "$OPSKIT" pieces add "@activepieces/piece-webhook" 0.1.42
  [ "$status" -eq 1 ]
  [[ "$output" == *"the archive is not that piece"* ]]
  [ ! -e "${OPSKIT_PIECES_DIR}/files/activepieces-piece-webhook-0.1.42.tgz" ]
}

@test "add refuses bad references and unknown versions" {
  run "$OPSKIT" pieces add "webhook; rm -rf /" 1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a piece reference"* ]]
  run "$OPSKIT" pieces add "@activepieces/piece-webhook" 0.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found on npm"* ]]
}

@test "check fails on a changed file and on a template pin missing from the pack; custom pieces are not required" {
  run "$OPSKIT" pieces check
  [ "$status" -eq 1 ]
  [[ "$output" == *"template pin @activepieces/piece-webhook 0.1.42 is not in the pack"* ]]
  [[ "$output" != *"piece-x"* ]]
  publish "@activepieces/piece-webhook" 0.1.42
  "$OPSKIT" pieces add "@activepieces/piece-webhook" 0.1.42 >/dev/null
  printf 'x' >> "${OPSKIT_PIECES_DIR}/files/activepieces-piece-webhook-0.1.42.tgz"
  run "$OPSKIT" pieces check
  [ "$status" -eq 1 ]
  [[ "$output" == *"file changed since it was added"* ]]
}

@test "the committed pack is intact and covers every template in the repo" {
  OPSKIT_PIECES_DIR="${OPSKIT_ROOT}/pieces" OPSKIT_FLOWS_DIR="${OPSKIT_ROOT}/flows" run "$OPSKIT" pieces check
  [ "$status" -eq 0 ]
}
