#!/usr/bin/env bash
# Piece pack: the exact piece versions our stacks use, kept as files in this repo (opskit/pieces/files)
# and listed with their sha256 in opskit/pieces/pack.yaml. Stacks get them through CE's own
# POST /v1/pieces archive install, so a run never needs cloud.activepieces.com, its CDN or npm.

PIECES_NPM_URL="${OPSKIT_NPM_REGISTRY_URL:-https://registry.npmjs.org}"

pieces_dir() {
  printf '%s' "${OPSKIT_PIECES_DIR:-${OPSKIT_ROOT}/pieces}"
}

pieces_pack_file() {
  printf '%s/pack.yaml' "$(pieces_dir)"
}

# pieces_file <name> <version>: path of the archive in the pack
pieces_file() {
  printf '%s/files/%s-%s.tgz' "$(pieces_dir)" "$(sed -E 's#^@##; s#/#-#' <<< "$1")" "$2"
}

pieces_valid_ref() {
  [[ "$1" =~ ^@[a-z0-9-]+/piece-[a-z0-9-]+$ ]] && [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# pieces_entries: "<name>\t<version>\t<sha256>" per pack entry
pieces_entries() {
  local pack
  pack="$(pieces_pack_file)"
  [ -f "$pack" ] || return 0
  yq -r '.pieces[]? | [.name, .version, .sha256] | @tsv' "$pack"
}

pieces_in_pack() {
  pieces_entries | awk -F'\t' -v n="$1" -v v="$2" '$1 == n && $2 == v { found = 1 } END { exit !found }'
}

# pieces_sha256 <file>
pieces_sha256() {
  sha256sum "$1" | awk '{ print $1 }'
}

# pieces_add <name> <version>: download once from npm, verify npm's sha512, refuse pieces that would
# still need npm at run time (dependencies), record the sha256 in pack.yaml. Idempotent.
pieces_add() {
  local name="$1" version="$2" file tmp meta tarball integrity got pkg
  pieces_valid_ref "$name" "$version" || { log_fail "not a piece reference: ${name} ${version} (expected @scope/piece-name x.y.z)"; return 1; }
  file="$(pieces_file "$name" "$version")"
  if pieces_in_pack "$name" "$version" && [ -f "$file" ]; then
    log_ok "${name} ${version} is already in the pack"
    return 0
  fi
  tmp="$(mktemp -d)"
  meta="${tmp}/meta.json"
  if ! curl -sSf -m 30 -o "$meta" "${PIECES_NPM_URL}/${name}/${version}" 2>/dev/null; then
    rm -rf "$tmp"
    log_fail "${name} ${version}: not found on npm (or npm not reachable from this machine)"
    return 1
  fi
  tarball="$(jq -r '.dist.tarball // empty' "$meta")"
  integrity="$(jq -r '.dist.integrity // empty' "$meta")"
  if [[ "$tarball" != "${PIECES_NPM_URL}/"* ]] || [[ "$integrity" != sha512-* ]]; then
    rm -rf "$tmp"
    log_fail "${name} ${version}: npm answer has no usable tarball/integrity"
    return 1
  fi
  if ! curl -sSf -m 120 -o "${tmp}/piece.tgz" "$tarball" 2>/dev/null; then
    rm -rf "$tmp"
    log_fail "${name} ${version}: download failed"
    return 1
  fi
  got="sha512-$(openssl dgst -sha512 -binary "${tmp}/piece.tgz" | base64 -w 0)"
  if [ "$got" != "$integrity" ]; then
    rm -rf "$tmp"
    log_fail "${name} ${version}: checksum does not match npm's (download damaged or tampered)"
    return 1
  fi
  if ! pkg="$(tar -xzOf "${tmp}/piece.tgz" package/package.json 2>/dev/null)" \
    || [ "$(jq -r '.name + " " + .version' <<< "$pkg")" != "${name} ${version}" ]; then
    rm -rf "$tmp"
    log_fail "${name} ${version}: the archive is not that piece"
    return 1
  fi
  if [ "$(jq '(.dependencies // {}) | length' <<< "$pkg")" != "0" ]; then
    rm -rf "$tmp"
    log_fail "${name} ${version}: has npm dependencies, so a stack would still download them at run time; not added"
    return 1
  fi
  mkdir -p "$(dirname "$file")"
  mv "${tmp}/piece.tgz" "$file"
  rm -rf "$tmp"
  pieces_record "$name" "$version" "$(pieces_sha256 "$file")"
  log_ok "${name} ${version} added to the pack ($(stat -c %s "$file") bytes)"
}

# pieces_record <name> <version> <sha256>: upsert the entry, keep the list sorted
pieces_record() {
  local pack
  pack="$(pieces_pack_file)"
  [ -f "$pack" ] || printf 'pieces: []\n' > "$pack"
  NAME="$1" VERSION="$2" SHA="$3" yq -i '
    .pieces = ([.pieces[]? | select(.name != strenv(NAME) or .version != strenv(VERSION))]
      + [{"name": strenv(NAME), "version": strenv(VERSION), "sha256": strenv(SHA)}])
    | .pieces |= sort_by(.name, .version)' "$pack"
}

# pieces_template_pins: "<name>\t<version>" of every official piece pinned by a template
pieces_template_pins() {
  local dir
  for dir in "${OPSKIT_FLOWS_DIR:-${OPSKIT_ROOT}/flows}"/*/; do
    [ -f "${dir}template.yaml" ] || continue
    yq -r '.pieces[]? | select(.custom == null) | [.name, .version] | @tsv' "${dir}template.yaml"
  done | sort -u
}

# pieces_check: files present and unchanged, every template pin in the pack
pieces_check() {
  local name version sha file failed=0 count=0
  while IFS=$'\t' read -r name version sha; do
    [ -n "$name" ] || continue
    count=$((count + 1))
    file="$(pieces_file "$name" "$version")"
    if [ ! -f "$file" ]; then
      log_fail "${name} ${version}: file missing (${file}); opskit pieces add ${name} ${version}"
      failed=1
    elif [ "$(pieces_sha256 "$file")" != "$sha" ]; then
      log_fail "${name} ${version}: file changed since it was added (sha256 differs)"
      failed=1
    fi
  done < <(pieces_entries)
  while IFS=$'\t' read -r name version; do
    [ -n "$name" ] || continue
    if ! pieces_in_pack "$name" "$version"; then
      log_fail "template pin ${name} ${version} is not in the pack: opskit pieces add ${name} ${version}"
      failed=1
    fi
  done < <(pieces_template_pins)
  [ "$failed" -eq 0 ] && log_ok "piece pack: ${count} pieces, files intact, every template pin included"
  return "$failed"
}
