#!/usr/bin/env bash
# opskit alert sender — standalone. Sends one alert to the owner's and the client's channels.
# Channels (KEY=VALUE files, mode 600, parsed not sourced):
#   <root>/agent/alerts.conf          owner: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
#   <root>/clients/<id>/alerts.conf   client: TELEGRAM_CHAT_ID, SLACK_WEBHOOK_URL, WEBHOOK_URL
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: alert.sh --client <id> --severity info|warn|critical --what <text> --action <text> [--root <dir>]

Message: [SEVERITY] <client> on <host>: <what> — First action: <action>
Texts are cut to 300 characters. Never pass secrets or personal data.
EOF
}

ROOT="/opt/opskit"
CLIENT=""
SEVERITY=""
WHAT=""
ACTION=""
TELEGRAM_API="${OPSKIT_TELEGRAM_API:-https://api.telegram.org}"

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) ROOT="$2"; shift 2 ;;
      --client) CLIENT="$2"; shift 2 ;;
      --severity) SEVERITY="$2"; shift 2 ;;
      --what) WHAT="$2"; shift 2 ;;
      --action) ACTION="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit 1 ;;
    esac
  done
  [[ "$CLIENT" =~ ^[a-z][a-z0-9-]{0,30}[a-z0-9]$ ]] || { echo "[fail] --client required" >&2; exit 1; }
  [[ "$SEVERITY" =~ ^(info|warn|critical)$ ]] || { echo "[fail] --severity info|warn|critical" >&2; exit 1; }
  if [ -z "$WHAT" ] || [ -z "$ACTION" ]; then
    echo "[fail] --what and --action are required" >&2
    exit 1
  fi
}

conf_value() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  sed -n "s/^${key}=//p" "$file" | tail -n 1
}

message_text() {
  local upper
  upper="$(printf '%s' "$SEVERITY" | tr '[:lower:]' '[:upper:]')"
  printf '[%s] %s on %s: %s — First action: %s' "$upper" "$CLIENT" "$(hostname)" "${WHAT:0:300}" "${ACTION:0:300}"
}

post_json() {
  local url="$1" body="$2"
  curl -fsS -m 15 -X POST -H 'content-type: application/json' --data "$body" "$url" > /dev/null
}

deliver() {
  local label="$1" url="$2" body="$3"
  if post_json "$url" "$body"; then
    echo "[ok] alert sent: ${label}"
  else
    echo "[warn] ${label} alert failed" >&2
    return 1
  fi
}

send_telegram() {
  local token="$1" chat="$2" text="$3"
  [ -n "$token" ] && [ -n "$chat" ] || return 0
  deliver "telegram ${chat}" "${TELEGRAM_API}/bot${token}/sendMessage" "$(jq -nc --arg chat "$chat" --arg text "$text" '{chat_id: $chat, text: $text}')"
}

send_slack() {
  local url="$1" text="$2"
  [ -n "$url" ] || return 0
  deliver slack "$url" "$(jq -nc --arg text "$text" '{text: $text}')"
}

send_webhook() {
  local url="$1"
  [ -n "$url" ] || return 0
  deliver webhook "$url" "$(jq -nc --arg client "$CLIENT" --arg severity "$SEVERITY" --arg what "${WHAT:0:300}" \
    --arg action "${ACTION:0:300}" --arg host "$(hostname)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{client: $client, severity: $severity, what: $what, first_action: $action, host: $host, at: $at}')"
}

main() {
  parse_args "$@"
  local owner="${ROOT}/agent/alerts.conf" client="${ROOT}/clients/${CLIENT}/alerts.conf" text sent=0 failed=0
  text="$(message_text)"
  local token
  token="$(conf_value "$owner" TELEGRAM_BOT_TOKEN)"
  send_telegram "$token" "$(conf_value "$owner" TELEGRAM_CHAT_ID)" "$text" || failed=1
  send_telegram "$token" "$(conf_value "$client" TELEGRAM_CHAT_ID)" "$text" || failed=1
  send_slack "$(conf_value "$client" SLACK_WEBHOOK_URL)" "$text" || failed=1
  send_webhook "$(conf_value "$owner" WEBHOOK_URL)" || failed=1
  send_webhook "$(conf_value "$client" WEBHOOK_URL)" || failed=1
  if [ -n "$token" ] || [ -n "$(conf_value "$owner" WEBHOOK_URL)" ]; then
    sent=1
  fi
  if [ "$sent" -eq 0 ]; then
    echo "[warn] no owner alert channel configured (${owner}); alert only logged: ${text}" >&2
    return 1
  fi
  return "$failed"
}

main "$@"
