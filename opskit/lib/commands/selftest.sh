#!/usr/bin/env bash
# summary: end-to-end check on this machine: throwaway host + client → deploy → backup → restore → teardown

for lib in validate schema registry render secrets stack ssh host deploy verify roundtrip; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

selftest_usage() {
  cat <<'EOF'
Usage: opskit selftest [--keep]

Creates a throwaway practice host (local, Caddy internal TLS on the first free port
pair from 18080/18443 — override with OPSKIT_SELFTEST_HTTP_PORT / _HTTPS_PORT) and a
"selftest-<random>" client in a temp registry, then: bootstrap edge → client new →
deploy → re-deploy (must keep the same containers) → seed 3 flows + a stored connection →
backup (off-server copy to a local rclone remote) → restore into "<id>-rt" → the copy has the
flows and the connection decrypts → teardown of only what it created.
--keep leaves everything running for inspection (prints how to remove it).
Needs Docker and network access for image pulls. Touches no real client.
EOF
}

selftest_cleanup() {
  [ "${SELFTEST_KEEP:-false}" = "true" ] && return 0
  local id
  for id in ${SELFTEST_ID:+"$SELFTEST_ID" "${SELFTEST_ID}-rt"}; do
    [ -f "${SELFTEST_ROOT}/clients/${id}/compose.yml" ] || continue
    docker compose -p "$id" --project-directory "${SELFTEST_ROOT}/clients/${id}" \
      -f "${SELFTEST_ROOT}/clients/${id}/compose.yml" down -v --remove-orphans >/dev/null 2>&1 || true
  done
  [ -z "${SELFTEST_EDGE:-}" ] || docker rm -f "$SELFTEST_EDGE" >/dev/null 2>&1 || true
  [ -z "${SELFTEST_DIR:-}" ] || remove_tree "$SELFTEST_DIR"
}

remove_tree() {
  local dir="$1"
  if [ -d "${dir}/host-root/caddy" ]; then
    docker run --rm -v "${dir}/host-root/caddy:/caddy" --entrypoint sh caddy:2.10.0 \
      -c 'rm -rf /caddy/data /caddy/config' >/dev/null 2>&1 || true
  fi
  rm -rf "$dir" 2>/dev/null || log_warn "selftest: could not fully remove ${dir}"
}

port_free() {
  ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

free_port_pair() {
  local http
  for http in $(seq 18080 10 18980); do
    if port_free "$http" && port_free "$((http + 363))"; then
      printf '%s %s' "$http" "$((http + 363))"
      return 0
    fi
  done
  return 1
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
  local shim="false" start ports http_port https_port
  [ -e /proc/net/if_inet6 ] || shim="true"
  ports="$(free_port_pair)" || die "selftest: no free port pair in 18080-18980"
  http_port="${OPSKIT_SELFTEST_HTTP_PORT:-${ports% *}}"
  https_port="${OPSKIT_SELFTEST_HTTPS_PORT:-${ports#* }}"
  mkdir -p "${SELFTEST_DIR}/hosts"
  cat > "${SELFTEST_DIR}/hosts/selftest.yaml" <<EOF
host_id: selftest
ip: 127.0.0.1
ssh_user: ops
mode: dedicated
cpus: 2
ram_gb: 4
transport: local
opskit_root: ${SELFTEST_ROOT}
edge:
  http_port: ${http_port}
  https_port: ${https_port}
  tls: internal
  container: ${SELFTEST_EDGE}
practice_quirks:
  ipv4_listen_shim: ${shim}
EOF
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
  rt_seed selftest "$SELFTEST_ID" "${SELFTEST_ID}.localhost" "$https_port" || die "selftest: seeding test data failed"
  "${SELFTEST_ROOT}/agent/backup.sh" "$SELFTEST_ID" --root "$SELFTEST_ROOT" | grep -E '^\[(ok|warn)\] (copied|backup of)' \
    || die "selftest: backup failed"
  local latest
  latest="$(cat "${SELFTEST_ROOT}/backups/${SELFTEST_ID}/latest")"
  age -d -i "${SELFTEST_DIR}/owner.key" "${SELFTEST_DIR}/offsite/${SELFTEST_ID}/${latest}/env.age" | grep -q '^AP_ENCRYPTION_KEY=' \
    || die "selftest: off-server env.age does not decrypt with the owner key"
  log_ok "backup off-server and env escrow decrypts"
  OPSKIT_OWNER_AGE_KEY="${SELFTEST_DIR}/owner.key" "${OPSKIT_ROOT}/bin/opskit" restore "$SELFTEST_ID" --target "${SELFTEST_ID}-rt" \
    || die "selftest: restore into ${SELFTEST_ID}-rt failed"
  rt_verify selftest "${SELFTEST_ID}-rt" "${SELFTEST_ID}-rt.localhost" "$https_port" || die "selftest: restored copy is incomplete"
  if [ "$SELFTEST_KEEP" = "true" ]; then
    log_warn "kept: OPSKIT_REGISTRY=${SELFTEST_DIR}; remove with: docker compose -p ${SELFTEST_ID} down -v; docker compose -p ${SELFTEST_ID}-rt down -v; docker rm -f ${SELFTEST_EDGE}; rm -rf ${SELFTEST_DIR}"
  fi
  log_ok "selftest passed in $(( $(date +%s) - start ))s"
}
