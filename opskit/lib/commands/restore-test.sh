#!/usr/bin/env bash
# summary: monthly restore test: latest backup → throwaway stack on this machine → checks → record → teardown

for lib in validate schema registry render secrets stack ssh host deploy verify practice; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

restore_test_usage() {
  cat <<'EOF'
Usage: opskit restore-test <client id> [--from <backup name>|latest]
       opskit restore-test --all

Restores the client's backup into a temporary stack on THIS machine (Docker, Caddy internal TLS
on free ports 18080+/18443+), never on the client's server. Passes when the stack is healthy, the
worker registers, HTTPS answers and every stored connection decrypts. Prints flow/connection/run
counts, removes the temporary stack and appends the result to clients/<id>/restore-tests.jsonl
(read by the care report). --all tests every deployed client. Needs the owner's age private key
($OPSKIT_OWNER_AGE_KEY or ~/.config/opskit/owner.key). The client and its server are not changed.
EOF
}

restore_test_record() {
  local id="$1" reason="${4:-}" file
  file="$(client_dir "$id")/restore-tests.jsonl"
  jq -nc --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg backup "${RT_BACKUP:-}" --arg result "$2" \
    --arg flows "${RT_COUNTS[0]:-}" --arg connections "${RT_COUNTS[1]:-}" --arg runs "${RT_COUNTS[2]:-}" \
    --argjson seconds "$3" --arg reason "${reason:0:300}" \
    '{at: $at, backup: $backup, result: $result, seconds: $seconds}
     + (if $flows != "" then {flows: ($flows | tonumber), connections: ($connections | tonumber), runs: ($runs | tonumber)} else {} end)
     + (if $reason != "" then {reason: $reason} else {} end)' >> "$file"
}

restore_test_one() {
  local id="$1" from="$2" host start rc=0
  require_client "$id" || return 1
  host="$(yaml_get "$(client_file "$id")" .host.name)"
  require_host "$host" || return 1
  start="$(date +%s)"
  RT_BACKUP=""
  RT_COUNTS=()
  log_info "restore test of ${id}: temporary stack on this machine"
  temp_stack_restore "$id" "$from" restore-test || rc=1
  grep -E '^\[(ok|fail)\] ' "$TEMP_LOG" 2>/dev/null | grep -vE '^\[ok\] (rendered|files copied|edge|deployed|HTTPS site)' || true
  RT_BACKUP="$(sed -n "s|^\[ok\] restore of ${id}/\([0-9TZ]*\) into .*|\1|p" "$TEMP_LOG" 2>/dev/null | head -n 1)"
  read -r -a RT_COUNTS <<< "$(sed -n 's/^\[ok\] restored data: \([0-9]*\) flows, \([0-9]*\) connections, \([0-9]*\) runs$/\1 \2 \3/p' "$TEMP_LOG" 2>/dev/null | head -n 1)"
  local reason="$TEMP_REASON"
  temp_stack_remove
  if [ "$rc" -eq 0 ]; then
    restore_test_record "$id" pass "$(( $(date +%s) - start ))"
    log_ok "restore test of ${id} passed (${RT_BACKUP}, $(( $(date +%s) - start ))s); temporary stack removed"
  else
    restore_test_record "$id" fail "$(( $(date +%s) - start ))" "${reason:-see output above}"
    log_fail "restore test of ${id} FAILED: ${reason:-see output above}; temporary stack removed"
  fi
  return "$rc"
}

cmd_main() {
  local from="latest" id="" failed=0 file
  case "${1:-}" in
    -h|--help) restore_test_usage; return 0 ;;
    --all) [ "$#" -eq 1 ] || { restore_test_usage >&2; return 1; } ;;
    ""|-*) restore_test_usage >&2; return 1 ;;
  esac
  if [ "$1" = "--all" ]; then
    for file in "$(registry_root)"/clients/*/client.yaml; do
      [ -f "$file" ] || continue
      [ "$(yaml_get "$file" .status)" = "deployed" ] || continue
      restore_test_one "$(yaml_get "$file" .client_id)" latest || failed=1
    done
    return "$failed"
  fi
  id="$1"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --from) from="${2:-}"; shift 2 ;;
      *) restore_test_usage >&2; return 1 ;;
    esac
  done
  restore_test_one "$id" "$from"
}
