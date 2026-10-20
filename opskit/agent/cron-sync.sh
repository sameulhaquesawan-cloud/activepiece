#!/usr/bin/env bash
# opskit cron sync — standalone. Rebuilds this user's crontab: keeps every non-opskit line and
# adds the lines from <root>/clients/*/cron (each tagged "# opskit:<id>"). Idempotent.
set -euo pipefail
IFS=$'\n\t'

ROOT="/opt/opskit"
case "${1:-}" in
  --root) ROOT="$2" ;;
  -h|--help) printf 'Usage: cron-sync.sh [--root <opskit root>]\n'; exit 0 ;;
  "") ;;
  *) printf 'Usage: cron-sync.sh [--root <opskit root>]\n' >&2; exit 1 ;;
esac

current="$(crontab -l 2>/dev/null || true)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$current" | grep -v '# opskit:' | sed '/^$/d' > "$tmp" || true
count=0
for file in "${ROOT}"/clients/*/cron; do
  [ -f "$file" ] || continue
  grep '# opskit:' "$file" >> "$tmp" || true
  count=$((count + 1))
done
crontab "$tmp"
printf '[ok] crontab synced: %s client schedule(s)\n' "$count"
