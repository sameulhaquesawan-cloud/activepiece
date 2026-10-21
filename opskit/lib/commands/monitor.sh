#!/usr/bin/env bash
# summary: the owner's Uptime Kuma: deploy it on a host, sync or remove a client's monitors

for lib in validate schema registry render secrets stack ssh host deploy monitor monitor_sync; do
  # shellcheck source=/dev/null
  source "${OPSKIT_ROOT}/lib/${lib}.sh"
done

monitor_usage() {
  cat <<'USAGE'
Usage: opskit monitor deploy <host>
       opskit monitor sync <client id>
       opskit monitor remove <client id>

deploy <host>   run Uptime Kuma (pinned tag) on the host behind its Caddy edge at monitor.domain
                (hosts/<host>.yaml), create the admin account (stored in hosts/<host>.monitor/admin.env,
                git-ignored, mode 600) and check that the HTTPS page answers. Safe to re-run.
sync <id>       create/update the client's monitors: uptime of /api/v1/health every 60 s and a backup
                push monitor that alerts when no backup arrived for 26 h; both notify the owner's
                Telegram (owner/alerts.conf). Saves the push URL as backup.heartbeat_url and updates
                the client's backup config on its host. Safe to re-run.
remove <id>     delete the client's monitors (offboarding).
Needs: opskit host bootstrap <host> first. Data lives in the Docker volume opskit-monitor_data.
The monitoring host is the one host with a monitor section (or OPSKIT_MONITOR_HOST).
USAGE
}

cmd_main() {
  case "${1:-}" in
    -h|--help) monitor_usage; return 0 ;;
    deploy)
      [ -n "${2:-}" ] || { monitor_usage >&2; return 1; }
      monitor_deploy "$2"
      ;;
    sync|remove)
      [ -n "${2:-}" ] || { monitor_usage >&2; return 1; }
      "monitor_$1" "$2"
      ;;
    *) monitor_usage >&2; return 1 ;;
  esac
}
