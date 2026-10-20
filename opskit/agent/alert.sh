#!/usr/bin/env bash
# opskit alert sender — standalone. Sends one alert to the owner's and the client's channels.
# Channels (KEY=VALUE files, mode 600, parsed not sourced):
#   <root>/agent/alerts.conf          owner: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, WEBHOOK_URL,
#                                     SMTP_URL, SMTP_USER, SMTP_PASSWORD, SMTP_FROM, SMTP_TLS, OWNER_EMAIL
#   <root>/clients/<id>/alerts.conf   client: TELEGRAM_CHAT_ID, SLACK_WEBHOOK_URL, EMAIL_TO, WEBHOOK_URL
# Payload templates: <root>/agent/alerts/*.jq (repo: opskit/templates/alerts/).
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: alert.sh --client <id> --severity info|warn|critical --what <text> --action <text>
                [--link <url>] [--root <dir>]

Message: [SEVERITY] <client> on <host>: <what> — First action: <action> (+ link)
Texts are cut to 300 characters. Never pass secrets or personal data.
Exit: 0 delivered everywhere, 1 nothing reached the owner or a channel failed.
EOF
}

ROOT="/opt/opskit"
CLIENT=""
SEVERITY=""
WHAT=""
ACTION=""
LINK=""
TELEGRAM_API="${OPSKIT_TELEGRAM_API:-https://api.telegram.org}"

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) ROOT="$2"; shift 2 ;;
      --client) CLIENT="$2"; shift 2 ;;
      --severity) SEVERITY="$2"; shift 2 ;;
      --what) WHAT="$2"; shift 2 ;;
      --action) ACTION="$2"; shift 2 ;;
      --link) LINK="$2"; shift 2 ;;
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
  [[ -z "$LINK" || "$LINK" =~ ^https?://[^[:space:]]+$ ]] || { echo "[fail] --link must be an http(s) URL" >&2; exit 1; }
}

conf_value() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  sed -n "s/^${key}=//p" "$file" | tail -n 1
}

template_dir() {
  local dir
  for dir in "${OPSKIT_ALERT_TEMPLATES:-}" "$(dirname "$0")/alerts" "$(dirname "$0")/../templates/alerts"; do
    if [ -n "$dir" ] && [ -f "${dir}/text.jq" ]; then
      printf '%s' "$dir"
      return 0
    fi
  done
  echo "[fail] alert templates not found next to $0 (alerts/*.jq)" >&2
  return 1
}

alert_json() {
  jq -nc --arg client "$CLIENT" --arg severity "$SEVERITY" --arg what "${WHAT:0:300}" --arg action "${ACTION:0:300}" \
    --arg host "$(hostname)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg date "$(date -u -R)" --arg link "$LINK" \
    '{client: $client, severity: $severity, what: $what, action: $action, host: $host, at: $at, date: $date, link: $link}'
}

# render <channel> [jq args...]: payload for one channel from the alert object
render() {
  local channel="$1"
  shift
  jq -r "$@" "def text: $(cat "${TEMPLATES}/text.jq"); $(cat "${TEMPLATES}/${channel}.jq")" <<< "$ALERT"
}

post_json() {
  local url="$1" body="$2"
  curl -fsS -m 15 -X POST -H 'content-type: application/json' --data "$body" "$url" > /dev/null
}

deliver() {
  local label="$1"
  shift
  if "$@"; then
    echo "[ok] alert sent: ${label}"
  else
    echo "[warn] ${label} alert failed" >&2
    return 1
  fi
}

send_telegram() {
  local token="$1" chat="$2"
  [ -n "$token" ] && [ -n "$chat" ] || return 0
  deliver "telegram ${chat}" post_json "${TELEGRAM_API}/bot${token}/sendMessage" "$(render telegram --arg chat "$chat")"
}

send_slack() {
  local url="$1"
  [ -n "$url" ] || return 0
  deliver slack post_json "$url" "$(render slack)"
}

send_webhook() {
  local url="$1"
  [ -n "$url" ] || return 0
  deliver webhook post_json "$url" "$(render webhook)"
}

curl_quote() {
  local value="${1//\\/\\\\}"
  printf '"%s"' "${value//\"/\\\"}"
}

smtp_send() {
  local to="$1" owner="$2" url from tls user password message rcpt args=()
  url="$(conf_value "$owner" SMTP_URL)"
  from="$(conf_value "$owner" SMTP_FROM)"
  tls="$(conf_value "$owner" SMTP_TLS)"
  user="$(conf_value "$owner" SMTP_USER)"
  password="$(conf_value "$owner" SMTP_PASSWORD)"
  message="$(mktemp)"
  render email --arg from "$from" --arg to "$to" > "$message"
  args=(-fsS -m 30 --url "$url" --mail-from "$from" --upload-file "$message")
  [ "${tls:-starttls}" = "none" ] || args+=(--ssl-reqd)
  for rcpt in ${to//,/$'\n'}; do
    args+=(--mail-rcpt "$rcpt")
  done
  if [ -n "$user" ]; then
    curl "${args[@]}" -K - <<< "user = $(curl_quote "${user}:${password}")" > /dev/null || { rm -f "$message"; return 1; }
  else
    curl "${args[@]}" > /dev/null || { rm -f "$message"; return 1; }
  fi
  rm -f "$message"
}

send_email() {
  local to="$1" owner="$2"
  [ -n "$to" ] || return 0
  if [ -z "$(conf_value "$owner" SMTP_URL)" ] || [ -z "$(conf_value "$owner" SMTP_FROM)" ]; then
    echo "[warn] email alert for ${to} skipped: no SMTP_URL/SMTP_FROM in ${owner}" >&2
    return 1
  fi
  deliver "email ${to}" smtp_send "$to" "$owner"
}

main() {
  parse_args "$@"
  local owner="${ROOT}/agent/alerts.conf" client="${ROOT}/clients/${CLIENT}/alerts.conf" token failed=0
  TEMPLATES="$(template_dir)"
  ALERT="$(alert_json)"
  token="$(conf_value "$owner" TELEGRAM_BOT_TOKEN)"
  send_telegram "$token" "$(conf_value "$owner" TELEGRAM_CHAT_ID)" || failed=1
  send_telegram "$token" "$(conf_value "$client" TELEGRAM_CHAT_ID)" || failed=1
  send_slack "$(conf_value "$client" SLACK_WEBHOOK_URL)" || failed=1
  send_email "$(conf_value "$owner" OWNER_EMAIL)" "$owner" || failed=1
  send_email "$(conf_value "$client" EMAIL_TO)" "$owner" || failed=1
  send_webhook "$(conf_value "$owner" WEBHOOK_URL)" || failed=1
  send_webhook "$(conf_value "$client" WEBHOOK_URL)" || failed=1
  if [ -z "$token" ] && [ -z "$(conf_value "$owner" WEBHOOK_URL)" ]; then
    echo "[warn] no owner alert channel configured (${owner}); alert only logged: $(render text)" >&2
    return 1
  fi
  return "$failed"
}

main "$@"
