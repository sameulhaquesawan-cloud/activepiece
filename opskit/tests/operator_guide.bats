#!/usr/bin/env bats

load helpers/common

guide_commands() {
  grep -ohE 'opskit/bin/opskit [a-z-]+( [a-z-]+)?' "${OPSKIT_ROOT}/../docs/OPERATOR_GUIDE.md" "${OPSKIT_ROOT}/../docs/ACTIVEPIECES_GUIDE.md" \
    | awk '{print $2}' | sort -u
}

@test "every opskit command named in the owner guides exists" {
  local cmd missing=""
  for cmd in $(guide_commands); do
    [ -f "${OPSKIT_ROOT}/lib/commands/${cmd}.sh" ] || missing="${missing} ${cmd}"
  done
  [ -z "$missing" ] || { echo "missing commands:${missing}"; return 1; }
}

@test "every --flag used with an opskit command in the owner guides is in that command's help" {
  local line cmd flag bad=""
  while IFS= read -r line; do
    cmd="$(awk '{print $2}' <<< "$line")"
    while IFS= read -r flag; do
      [ -z "$flag" ] || "$OPSKIT" "$cmd" --help 2>&1 | grep -qF -- "$flag" || bad="${bad} ${cmd}${flag}"
    done < <(grep -oE -- '--[a-z][a-z-]+' <<< "$line" || true)
  done < <(grep -ohE 'opskit/bin/opskit [a-z-]+[^`|]*' "${OPSKIT_ROOT}/../docs/OPERATOR_GUIDE.md" "${OPSKIT_ROOT}/../docs/ACTIVEPIECES_GUIDE.md" | sed 's/opskit\/bin\/opskit //' | sed 's/^/x /')
  [ -z "$bad" ] || { echo "unknown flags:${bad}"; return 1; }
}
