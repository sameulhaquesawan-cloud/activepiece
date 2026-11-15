#!/usr/bin/env bash
# Selftest upgrade rounds (task 6.10, SPEC 17 Phase 6 acceptance), each on its own throwaway client next to
# the selftest client: promote (previous release → pinned, everything must pass, history + data checked)
# and rollback (an older release with migrations → pinned with an injected production failure: back on the
# old tag with its schema and data, exactly one owner alert). Needs the selftest registry, owner key pair,
# off-server remote and roundtrip.sh / e2e.sh helpers. Flow checks in staging follow OPSKIT_REQUIRE_PIECES.

E2E_UPGRADE_PROMOTE_FROM="0.92.2"
E2E_UPGRADE_ROLLBACK_FROM="0.91.4"

# e2e_upgrade_client <id> <tag> <https port> <offsite dir>: deployed, seeded, backed up, restore-tested
e2e_upgrade_client() {
  local id="$1" tag="$2" port="$3" offsite="$4"
  "${OPSKIT_ROOT}/bin/opskit" client new "$id" --domain "${id}.localhost" --host selftest --contact selftest@example.com >/dev/null || return 1
  yq -i ".image.tag = \"${tag}\" | .ap_version = \"${tag}\" | .backup.remote = \"offsite:${offsite}\"" "$(client_file "$id")"
  "${OPSKIT_ROOT}/bin/opskit" deploy "$id" >/dev/null || { log_fail "upgrade e2e: deploy of ${id} on ${tag} failed"; return 1; }
  rt_seed selftest "$id" "${id}.localhost" "$port" >/dev/null || return 1
  "${OPSKIT_ROOT}/bin/opskit" backup "$id" >/dev/null || { log_fail "upgrade e2e: backup of ${id} failed"; return 1; }
  "${OPSKIT_ROOT}/bin/opskit" restore-test "$id" >/dev/null || { log_fail "upgrade e2e: restore test of ${id} failed"; return 1; }
  log_ok "upgrade e2e: ${id} deployed on ${tag}, seeded, backed up, restore-tested"
}

# e2e_upgrade_run <id> <to> [env assignments...]: the real command, client id typed at the prompt
e2e_upgrade_run() {
  local id="$1" to="$2"
  shift 2
  printf '%s\n' "$id" | env OPSKIT_REQUIRE_PIECES="${OPSKIT_REQUIRE_PIECES:-0}" "$@" \
    "${OPSKIT_ROOT}/bin/opskit" upgrade "$id" --to "$to" --yes --now > "${E2E_UPGRADE_LOG}" 2>&1
}

e2e_upgrade_image() {
  host_run selftest docker inspect -f '{{.Config.Image}}' "$(stack_service_container selftest "$1" app)" 2>/dev/null | sed 's/.*://'
}

e2e_upgrade_events() {
  yq -r '[.history[] | select(.event == "upgraded" or .event == "upgrade_failed" or .event == "rolled_back") | .event + " " + .tag] | join(", ")' "$(client_file "$1")"
}

e2e_upgrade_fail() {
  grep -E '^\[(fail|warn)\]' "$E2E_UPGRADE_LOG" | head -n 8 >&2 || true
  log_fail "upgrade e2e: $1"
  return 1
}

# e2e_upgrade_promote <selftest id> <https port> <pinned tag> <offsite dir>
e2e_upgrade_promote() {
  local id="${1}-up" port="$2" to="$3" offsite="$4" start
  start="$(date +%s)"
  e2e_upgrade_client "$id" "$E2E_UPGRADE_PROMOTE_FROM" "$port" "$offsite" || return 1
  e2e_upgrade_run "$id" "$to" || e2e_upgrade_fail "upgrade of ${id} ${E2E_UPGRADE_PROMOTE_FROM} → ${to} failed" || return 1
  grep -q "^\[ok\] staging of ${id} on ${to} passed" "$E2E_UPGRADE_LOG" || e2e_upgrade_fail "no staging pass for ${id}" || return 1
  grep -q '^Follow-ups:' "$E2E_UPGRADE_LOG" || e2e_upgrade_fail "no follow-up list for ${id}" || return 1
  [ "$(e2e_upgrade_image "$id")" = "$to" ] || e2e_upgrade_fail "${id} does not run ${to}" || return 1
  [ "$(yq -r .image.tag "$(client_file "$id")")" = "$to" ] || e2e_upgrade_fail "client.yaml of ${id} is not on ${to}" || return 1
  [ "$(e2e_upgrade_events "$id")" = "upgraded ${to}" ] || e2e_upgrade_fail "history of ${id}: $(e2e_upgrade_events "$id")" || return 1
  rt_verify selftest "$id" "${id}.localhost" "$port" >/dev/null || e2e_upgrade_fail "data of ${id} after the upgrade" || return 1
  log_ok "upgrade e2e: promote ${E2E_UPGRADE_PROMOTE_FROM} → ${to} passed staging and production checks, data intact, history 'upgraded' ($(( $(date +%s) - start ))s)"
}

# e2e_upgrade_rollback <selftest id> <https port> <pinned tag> <offsite dir> <owner dir>
e2e_upgrade_rollback() {
  local id="${1}-rb" port="$2" to="$3" offsite="$4" owner="$5" start rc=0 messages text
  start="$(date +%s)"
  e2e_upgrade_client "$id" "$E2E_UPGRADE_ROLLBACK_FROM" "$port" "$offsite" || return 1
  e2e_mock_start
  printf 'TELEGRAM_BOT_TOKEN=123:e2e\nTELEGRAM_CHAT_ID=111\n' > "${owner}/alerts.conf"
  e2e_upgrade_run "$id" "$to" OPSKIT_SMOKE_FAIL=production:counts \
    OPSKIT_TELEGRAM_API="http://127.0.0.1:$(cat "${E2E_MOCK_DIR}/port")" || rc=$?
  messages="$(jq -s '[.[] | select(.path | endswith("/sendMessage"))] | length' "${E2E_MOCK_DIR}/requests.jsonl")"
  text="$(jq -r '.body | fromjson | .text' "${E2E_MOCK_DIR}/requests.jsonl" 2>/dev/null | head -n 3)"
  e2e_mock_stop
  rm -f "${owner}/alerts.conf"
  [ "$rc" -eq 1 ] || e2e_upgrade_fail "the injected failure did not fail the upgrade of ${id} (exit ${rc})" || return 1
  grep -q "^\[ok\] ${id} is back on ${E2E_UPGRADE_ROLLBACK_FROM} (path: restore)" "$E2E_UPGRADE_LOG" \
    || e2e_upgrade_fail "${id} was not rolled back by restoring the pre-switch dump" || return 1
  grep -q "^\[ok\] schema of ${id}: matches the image" "$E2E_UPGRADE_LOG" || e2e_upgrade_fail "no schema check after the rollback" || return 1
  [ "$(e2e_upgrade_image "$id")" = "$E2E_UPGRADE_ROLLBACK_FROM" ] || e2e_upgrade_fail "${id} does not run ${E2E_UPGRADE_ROLLBACK_FROM}" || return 1
  [ "$(yq -r .image.tag "$(client_file "$id")")" = "$E2E_UPGRADE_ROLLBACK_FROM" ] || e2e_upgrade_fail "client.yaml of ${id} is not back on ${E2E_UPGRADE_ROLLBACK_FROM}" || return 1
  [ "$(e2e_upgrade_events "$id")" = "upgrade_failed ${to}, rolled_back ${E2E_UPGRADE_ROLLBACK_FROM}" ] \
    || e2e_upgrade_fail "history of ${id}: $(e2e_upgrade_events "$id")" || return 1
  rt_verify selftest "$id" "${id}.localhost" "$port" >/dev/null || e2e_upgrade_fail "data of ${id} after the rollback" || return 1
  [ "$messages" = "1" ] || e2e_upgrade_fail "expected exactly 1 owner alert, got ${messages}" || return 1
  [[ "$text" == *"rolled back to ${E2E_UPGRADE_ROLLBACK_FROM}"* ]] || e2e_upgrade_fail "owner alert lacks the rollback: ${text:0:200}" || return 1
  log_ok "upgrade e2e: injected production failure on ${E2E_UPGRADE_ROLLBACK_FROM} → ${to} rolled back to ${E2E_UPGRADE_ROLLBACK_FROM}, schema and data intact, 1 owner alert ($(( $(date +%s) - start ))s)"
}

# e2e_upgrade <selftest id> <https port> <selftest dir>: both rounds; the round clients are removed after
e2e_upgrade() {
  local base="$1" port="$2" dir="$3" to rc=0
  to="$(yq -r .image.tag "$(client_file "$base")")"
  E2E_UPGRADE_LOG="${dir}/upgrade-e2e.log"
  export OPSKIT_OWNER_AGE_KEY="${dir}/owner.key"
  e2e_upgrade_promote "$base" "$port" "$to" "${dir}/offsite" || rc=1
  [ "${SELFTEST_KEEP:-false}" = "true" ] || practice_teardown "$(host_root selftest)" "" "${base}-up"
  [ "$rc" -ne 0 ] || e2e_upgrade_rollback "$base" "$port" "$to" "${dir}/offsite" "${dir}/owner" || rc=1
  return "$rc"
}
