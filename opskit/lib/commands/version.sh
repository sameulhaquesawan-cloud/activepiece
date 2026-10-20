#!/usr/bin/env bash
# summary: show opskit version and the pinned Activepieces release

cmd_main() {
  case "${1:-}" in
    -h|--help)
      printf 'Usage: opskit version\n'
      return 0
      ;;
  esac
  local upstream_tag
  upstream_tag="$(sed -n 's/^| Pinned release tag | \(.*\) |$/\1/p' "${OPSKIT_ROOT}/../docs/UPSTREAM_CHANGES.md" | head -n 1)"
  printf 'opskit %s (Activepieces %s)\n' "$(cat "${OPSKIT_ROOT}/VERSION")" "${upstream_tag:-unknown}"
}
