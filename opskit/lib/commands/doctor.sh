#!/usr/bin/env bash
# summary: check this machine has everything opskit needs (tools, Docker, network)

DOCTOR_TOOLS=(git curl openssl jq envsubst shellcheck bats age rclone ssh scp node npx)
DOCTOR_URLS=(
  "https://cloud.activepieces.com/api/v1/flags|Activepieces piece catalog"
  "https://registry.npmjs.org/|npm registry (piece code)"
  "https://ghcr.io/v2/|GitHub container registry"
)

doctor_usage() {
  cat <<'EOF'
Usage: opskit doctor [--offline]

Checks the operator machine: OS, Docker + Compose v2+, required tools
(incl. mikefarah yq v4) and outbound access. --offline skips network checks.
Fix missing tools with: opskit/bin/dev-env
EOF
}

doctor_os() {
  local kernel
  kernel="$(uname -s)"
  if [ "$kernel" != "Linux" ]; then
    log_fail "OS: ${kernel} (use Linux, WSL2 or a Codespace)"
    return 1
  fi
  if grep -qi microsoft /proc/version 2>/dev/null; then
    log_ok "OS: Linux (WSL)"
  else
    log_ok "OS: Linux"
  fi
}

doctor_docker() {
  local version major
  if ! command -v docker >/dev/null 2>&1; then
    log_fail "docker: not installed"
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    log_fail "docker: daemon not reachable (run opskit/bin/dev-env, or start Docker Desktop)"
    return 1
  fi
  version="$(docker compose version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
  major="${version#v}"
  major="${major%%.*}"
  if [ -z "$version" ] || [ "$major" -lt 2 ]; then
    log_fail "docker compose: v2 or newer required (found: ${version:-none})"
    return 1
  fi
  log_ok "docker: daemon running, compose ${version}"
}

doctor_tools() {
  local tool failed=0
  for tool in "${DOCTOR_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log_fail "tool missing: ${tool}"
      failed=1
    fi
  done
  if ! command -v yq >/dev/null 2>&1; then
    log_fail "tool missing: yq (mikefarah v4)"
    failed=1
  elif ! yq --version 2>/dev/null | grep -q 'mikefarah.*version v4'; then
    log_fail "yq: wrong flavor/version (need mikefarah yq v4; run opskit/bin/dev-env)"
    failed=1
  fi
  [ "$failed" -eq 0 ] && log_ok "tools: all present (${#DOCTOR_TOOLS[@]} + yq v4)"
  return "$failed"
}

doctor_network() {
  local entry url label code
  for entry in "${DOCTOR_URLS[@]}"; do
    url="${entry%%|*}"
    label="${entry#*|}"
    code="$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$url" || true)"
    if [ "$code" = "000" ] || [ -z "$code" ]; then
      log_warn "network: cannot reach ${label} (${url})"
    else
      log_ok "network: ${label} reachable"
    fi
  done
}

cmd_main() {
  local offline="false"
  case "${1:-}" in
    -h|--help) doctor_usage; return 0 ;;
    --offline) offline="true" ;;
    "") ;;
    *) doctor_usage >&2; return 1 ;;
  esac
  local failed=0
  doctor_os || failed=1
  doctor_docker || failed=1
  doctor_tools || failed=1
  [ "$offline" = "true" ] || doctor_network
  if [ "$failed" -ne 0 ]; then
    log_fail "doctor: problems found"
    return 1
  fi
  log_ok "doctor: ready"
}
