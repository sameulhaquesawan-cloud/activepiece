#!/usr/bin/env bash
# summary: deploy (or update) a client's stack on its host and verify it over HTTPS

# shellcheck source=../validate.sh
source "${OPSKIT_ROOT}/lib/validate.sh"
# shellcheck source=../schema.sh
source "${OPSKIT_ROOT}/lib/schema.sh"
# shellcheck source=../registry.sh
source "${OPSKIT_ROOT}/lib/registry.sh"
# shellcheck source=../render.sh
source "${OPSKIT_ROOT}/lib/render.sh"
# shellcheck source=../secrets.sh
source "${OPSKIT_ROOT}/lib/secrets.sh"
# shellcheck source=../stack.sh
source "${OPSKIT_ROOT}/lib/stack.sh"
# shellcheck source=../ssh.sh
source "${OPSKIT_ROOT}/lib/ssh.sh"
# shellcheck source=../host.sh
source "${OPSKIT_ROOT}/lib/host.sh"
# shellcheck source=../deploy.sh
source "${OPSKIT_ROOT}/lib/deploy.sh"

cmd_main() {
  case "${1:-}" in
    -h|--help|"")
      cat <<'USAGE'
Usage: opskit deploy <client id>

render → copy compose/.env to the host → docker compose -p <id> up -d → wait for the app
to be healthy → confirm the worker polls the app → publish the Caddy site → check
https://<domain>/api/v1/health → mark the client deployed. Safe to re-run.
USAGE
      [ -n "${1:-}" ] && return 0
      return 1
      ;;
  esac
  deploy_client "$1"
}
