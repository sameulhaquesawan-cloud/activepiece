#!/usr/bin/env bash
# Fork hygiene: compared with the pinned upstream tag, new files must live in our paths and
# changed/deleted upstream files must be listed in the docs/UPSTREAM_CHANGES.md patch ledger.

OPSKIT_NEW_FILE_PATTERNS=(
  'opskit/*' 'packages/pieces/custom/*' '.github/workflows/opskit-*' '.claude/CLAUDE.md'
  '.claude/hooks/*' '.agents/skills/opskit-*' '.devcontainer/opskit/*' 'README-START-HERE.md'
  'explore/*' 'docs/*'
)

fork_pinned_tag() {
  sed -n 's/^| Pinned release tag | \(.*\) |$/\1/p' "$1/docs/UPSTREAM_CHANGES.md" | head -n 1
}

fork_ledger_paths() {
  # shellcheck disable=SC2016
  sed -n '/^## Patch ledger/,$p' "$1/docs/UPSTREAM_CHANGES.md" \
    | awk -F'|' 'NR > 3 && NF > 4 { print $4 }' | grep -oE '`[^`]+`' | tr -d '`' | sort -u
}

fork_is_our_new_path() {
  local path="$1" pattern
  for pattern in "${OPSKIT_NEW_FILE_PATTERNS[@]}"; do
    # shellcheck disable=SC2053
    [[ "$path" == $pattern ]] && return 0
  done
  return 1
}

# fork_check <repo root>: prints [ok]/[fail] lines, returns 1 on violations
fork_check() {
  local root="$1" tag path violations=0 ledger
  tag="$(fork_pinned_tag "$root")"
  if [ -z "$tag" ] || ! git -C "$root" rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    log_warn "fork: pinned tag '${tag:-?}' not available locally; skipped (git fetch upstream --tags)"
    return 0
  fi
  ledger="$(fork_ledger_paths "$root")"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if git -C "$root" cat-file -e "${tag}:${path}" 2>/dev/null; then
      if ! grep -qxF "$path" <<< "$ledger"; then
        log_fail "fork: upstream file changed without a ledger row: ${path}"
        violations=$((violations + 1))
      fi
    elif ! fork_is_our_new_path "$path"; then
      log_fail "fork: new file outside our paths: ${path}"
      violations=$((violations + 1))
    fi
  done < <({ git -C "$root" diff --name-only "$tag"; git -C "$root" ls-files --others --exclude-standard; } | sort -u)
  if [ "$violations" -gt 0 ]; then
    return 1
  fi
  log_ok "fork: only our paths and ledgered upstream files differ from ${tag}"
}
