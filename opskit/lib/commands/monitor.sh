#!/usr/bin/env bash
# summary: the owner's Uptime Kuma: deploy it on a host (monitors per client: opskit monitor sync)

for lib in validate schema registry render ssh host monitor; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

monitor_usage() {
  cat <<'USAGE'
Usage: opskit monitor deploy <host>

deploy <host>   run Uptime Kuma (pinned tag) on the host behind its Caddy edge at monitor.domain
                (hosts/<host>.yaml), create the admin account (stored in hosts/<host>.monitor/admin.env,
                git-ignored, mode 600) and check that the HTTPS page answers. Safe to re-run.
Needs: opskit host bootstrap <host> first. Data lives in the Docker volume opskit-monitor_data.
USAGE
}

cmd_main() {
  case "${1:-}" in
    -h|--help) monitor_usage; return 0 ;;
    deploy)
      [ -n "${2:-}" ] || { monitor_usage >&2; return 1; }
      monitor_deploy "$2"
      ;;
    *) monitor_usage >&2; return 1 ;;
  esac
}
