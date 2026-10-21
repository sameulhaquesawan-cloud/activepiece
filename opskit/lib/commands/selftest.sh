#!/usr/bin/env bash
# summary: end-to-end check on this machine: throwaway host + client → deploy → backup → restore → teardown

for lib in validate schema registry render secrets stack ssh host deploy verify roundtrip e2e flows e2e_flows smoke smoke_flows e2e_smoke e2e_upgrade practice; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

selftest_usage() {
  cat <<'EOF'
Usage: opskit selftest [--keep]

Creates a throwaway practice host (local, Caddy internal TLS on the first free port
pair from 18080/18443 — override with OPSKIT_PRACTICE_HTTP_PORT / _HTTPS_PORT) and a
"selftest-<random>" client in a temp registry, then: bootstrap edge → client new →
deploy → re-deploy (must keep the same containers) → seed 3 flows + a stored connection →
backup (off-server copy to a local rclone remote) → restore into "<id>-rt" → the copy has the
flows and the connection decrypts → a deliberately failing flow produces exactly one Telegram
alert (mock API) via the failed-run detector (skipped when pieces are offline unless
OPSKIT_REQUIRE_PIECES=1) → the upgrade smoke checks pass, and fail when the stack is broken on
purpose (lowered baseline, stopped worker, connection with another key, newer schema), plus a
webhook and a schedule flow run (pieces) → upgrade rounds on two more throwaway clients: 0.92.2 →
pinned (plan, staging, switch, checks) and 0.91.4 → pinned with an injected production failure that
must roll back with data intact and one owner alert → teardown of only what it created.
--keep leaves everything running for inspection (prints how to remove it).
Needs Docker and network access for image pulls. Touches no real client.
EOF
}

selftest_cleanup() {
  [ "${SELFTEST_KEEP:-false}" = "true" ] && return 0
  [ -n "${SELFTEST_DIR:-}" ] || return 0
  practice_teardown "$SELFTEST_ROOT" "${SELFTEST_EDGE:-}" ${SELFTEST_ID:+"$SELFTEST_ID" "${SELFTEST_ID}-rt" "${SELFTEST_ID}-up" "${SELFTEST_ID}-rb"}
  practice_remove_tree "$SELFTEST_DIR"
}

selftest_containers() {
  docker compose -p "$SELFTEST_ID" ps -q | sort | tr '\n' ' '
}

cmd_main() {
  case "${1:-}" in
    -h|--help) selftest_usage; return 0 ;;
    --keep) SELFTEST_KEEP="true" ;;
    "") SELFTEST_KEEP="false" ;;
    *) selftest_usage >&2; return 1 ;;
  esac
  if ! "${OPSKIT_ROOT}/bin/opskit" doctor --offline >/dev/null 2>&1; then
    "${OPSKIT_ROOT}/bin/opskit" doctor --offline | grep -F '[fail]'
    die "selftest: fix the problems above first (most can be fixed with: opskit/bin/dev-env)"
  fi
  SELFTEST_DIR="$(mktemp -d)"
  SELFTEST_ROOT="${SELFTEST_DIR}/host-root"
  SELFTEST_ID="selftest-$(openssl rand -hex 3)"
  SELFTEST_EDGE="opskit-caddy-${SELFTEST_ID}"
  trap selftest_cleanup EXIT
  local start https_port
  https_port="$(practice_host_write "$SELFTEST_DIR" selftest "$SELFTEST_ROOT" "$SELFTEST_EDGE")" || die "selftest: no practice host"
  export OPSKIT_REGISTRY="$SELFTEST_DIR"
  mkdir -p "${SELFTEST_DIR}/owner" "${SELFTEST_DIR}/offsite"
  age-keygen -o "${SELFTEST_DIR}/owner.key" 2>/dev/null
  age-keygen -y "${SELFTEST_DIR}/owner.key" > "${SELFTEST_DIR}/owner.age.pub"
  export OPSKIT_OWNER_AGE_PUB="${SELFTEST_DIR}/owner.age.pub"
  printf '[offsite]\ntype = local\n' > "${SELFTEST_DIR}/owner/rclone.conf"
  start="$(date +%s)"
  log_info "selftest: ${SELFTEST_ID} in ${SELFTEST_DIR}"
  "${OPSKIT_ROOT}/bin/opskit" host bootstrap selftest | grep -E '^\[(ok|warn|fail)\] edge' || die "selftest: edge bootstrap failed"
  "${OPSKIT_ROOT}/bin/opskit" client new "$SELFTEST_ID" --domain "${SELFTEST_ID}.localhost" --host selftest --contact selftest@example.com >/dev/null \
    || die "selftest: client new failed"
  yq -i ".backup.remote = \"offsite:${SELFTEST_DIR}/offsite\"" "${SELFTEST_DIR}/clients/${SELFTEST_ID}/client.yaml"
  "${OPSKIT_ROOT}/bin/opskit" deploy "$SELFTEST_ID" || die "selftest: deploy failed"
  local before after
  before="$(selftest_containers)"
  "${OPSKIT_ROOT}/bin/opskit" deploy "$SELFTEST_ID" >/dev/null || die "selftest: re-deploy failed"
  after="$(selftest_containers)"
  if [ -z "$before" ] || [ "$before" != "$after" ]; then
    die "selftest: re-deploy recreated containers (not idempotent)"
  fi
  log_ok "re-deploy idempotent (same containers)"
  stack_readonly_check selftest "$SELFTEST_ID" || die "selftest: read-only database role is not safe"
  rt_seed selftest "$SELFTEST_ID" "${SELFTEST_ID}.localhost" "$https_port" || die "selftest: seeding test data failed"
  "${SELFTEST_ROOT}/agent/backup.sh" "$SELFTEST_ID" --root "$SELFTEST_ROOT" | grep -E '^\[(ok|warn)\] (copied|backup of)' \
    || die "selftest: backup failed"
  local latest
  latest="$(cat "${SELFTEST_ROOT}/backups/${SELFTEST_ID}/latest")"
  age -d -i "${SELFTEST_DIR}/owner.key" "${SELFTEST_DIR}/offsite/${SELFTEST_ID}/${latest}/env.age" | grep -q '^AP_ENCRYPTION_KEY=' \
    || die "selftest: off-server env.age does not decrypt with the owner key"
  local offsite="${SELFTEST_DIR}/offsite/${SELFTEST_ID}/${latest}"
  [ ! -e "${offsite}/db.dump" ] || die "selftest: a plain database dump left the server"
  if ! age -d -i "${SELFTEST_DIR}/owner.key" -o "${SELFTEST_DIR}/check.dump" "${offsite}/db.dump.age" \
    || [ "$(head -c 5 "${SELFTEST_DIR}/check.dump")" != "PGDMP" ]; then
    die "selftest: off-server db.dump.age does not decrypt to a database dump"
  fi
  rm -f "${SELFTEST_DIR}/check.dump"
  log_ok "backup off-server; database dump and env escrow are encrypted and decrypt with the owner key"
  OPSKIT_OWNER_AGE_KEY="${SELFTEST_DIR}/owner.key" "${OPSKIT_ROOT}/bin/opskit" restore "$SELFTEST_ID" --target "${SELFTEST_ID}-rt" \
    || die "selftest: restore into ${SELFTEST_ID}-rt failed"
  rt_verify selftest "${SELFTEST_ID}-rt" "${SELFTEST_ID}-rt.localhost" "$https_port" || die "selftest: restored copy is incomplete"
  e2e_monitoring selftest "$SELFTEST_ID" "${SELFTEST_ID}.localhost" "$https_port" || die "selftest: monitoring end-to-end check failed"
  e2e_flow_templates "$SELFTEST_ID" "${SELFTEST_ID}.localhost" "$https_port" || die "selftest: flow template import check failed"
  e2e_smoke selftest "$SELFTEST_ID" "${SELFTEST_ID}.localhost" "$https_port" || die "selftest: upgrade smoke checks failed"
  [ "$SELFTEST_KEEP" = "true" ] || practice_teardown "$SELFTEST_ROOT" "" "${SELFTEST_ID}-rt"
  e2e_upgrade "$SELFTEST_ID" "$https_port" "$SELFTEST_DIR" || die "selftest: upgrade rounds failed"
  if [ "$SELFTEST_KEEP" = "true" ]; then
    log_warn "kept: OPSKIT_REGISTRY=${SELFTEST_DIR}; remove with: for p in ${SELFTEST_ID} ${SELFTEST_ID}-rt ${SELFTEST_ID}-up ${SELFTEST_ID}-rb; do docker compose -p \$p down -v; done; docker rm -f ${SELFTEST_EDGE}; rm -rf ${SELFTEST_DIR}"
  fi
  log_ok "selftest passed in $(( $(date +%s) - start ))s"
}
