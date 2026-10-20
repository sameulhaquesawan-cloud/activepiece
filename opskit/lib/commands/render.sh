#!/usr/bin/env bash
# summary: render a client's compose, .env, Caddy site and cron from client.yaml

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

cmd_main() {
  case "${1:-}" in
    -h|--help|"")
      printf 'Usage: opskit render <client id>\n\nWrites opskit/clients/<id>/rendered/{compose.yml,.env,<id>.caddy,cron}.\nSecrets are generated on the first render and never regenerated.\n'
      [ -n "${1:-}" ] && return 0
      return 1
      ;;
  esac
  stack_render "$1"
}
