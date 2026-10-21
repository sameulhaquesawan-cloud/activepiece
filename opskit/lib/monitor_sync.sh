#!/usr/bin/env bash
# Per-client monitors in the owner's Uptime Kuma: uptime of /api/v1/health (60 s) and a backup push
# monitor (26 h) that alerts the owner's Telegram (or owner webhook). Needs lib/monitor.sh.

# monitor_host_for: the host whose yaml has a monitor section (OPSKIT_MONITOR_HOST if several)
monitor_host_for() {
  local file found=()
  if [ -n "${OPSKIT_MONITOR_HOST:-}" ]; then
    printf '%s' "$OPSKIT_MONITOR_HOST"
    return 0
  fi
  for file in "$(registry_root)"/hosts/*.yaml; do
    [ -f "$file" ] || continue
    [ -z "$(yaml_get "$file" .monitor.domain)" ] || found+=("$(yaml_get "$file" .host_id)")
  done
  case "${#found[@]}" in
    1) printf '%s' "${found[0]}" ;;
    0) log_fail "no monitoring host: add monitor: {domain: ...} to one host and run opskit monitor deploy <host>"; return 1 ;;
    *) log_fail "several monitoring hosts (${found[*]}): set OPSKIT_MONITOR_HOST"; return 1 ;;
  esac
}

monitor_base_url() {
  local hfile
  hfile="$(host_file "$1")"
  stack_frontend_url "$(yaml_get "$hfile" .monitor.domain)" "$(yaml_get "$hfile" .edge.https_port 443)"
}

# practice hosts (internal TLS) are checked over the edge network; real clients over public HTTPS
monitor_client_url() {
  local id="$1" cfile hfile
  cfile="$(client_file "$id")"
  hfile="$(host_file "$(yaml_get "$cfile" .host.name)")"
  if [ "$(yaml_get "$hfile" .edge.tls acme)" = "internal" ]; then
    printf 'http://%s-app/api/v1/health' "$id"
  else
    printf '%s/api/v1/health' "$(stack_frontend_url "$(yaml_get "$cfile" .domain)" "$(yaml_get "$hfile" .edge.https_port 443)")"
  fi
}

owner_conf_value() {
  local file
  file="$(registry_root)/owner/alerts.conf"
  [ -f "$file" ] || return 0
  sed -n "s/^${1}=//p" "$file" | tail -n 1
}

monitor_owner_notification() {
  local token chat hook
  token="$(owner_conf_value TELEGRAM_BOT_TOKEN)"
  chat="$(owner_conf_value TELEGRAM_CHAT_ID)"
  hook="$(owner_conf_value WEBHOOK_URL)"
  if [ -n "$token" ] && [ -n "$chat" ]; then
    jq -nc --arg t "$token" --arg c "$chat" --arg u "${OPSKIT_TELEGRAM_API:-https://api.telegram.org}" \
      '{name: "opskit owner", type: "telegram", telegramBotToken: $t, telegramChatID: $c, telegramServerUrl: $u, telegramSendSilently: false}'
  elif [ -n "$hook" ]; then
    jq -nc --arg u "$hook" '{name: "opskit owner", type: "webhook", webhookURL: $u, webhookContentType: "json"}'
  else
    log_fail "no owner alert channel in $(registry_root)/owner/alerts.conf (TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID)"
    return 1
  fi
}

monitor_sync_input() {
  local id="$1" mhost="$2" notification
  notification="$(monitor_owner_notification)" || return 1
  jq -nc --argjson admin "$(monitor_admin_json "$mhost")" --argjson notification "$notification" \
    --arg id "$id" --arg url "$(monitor_client_url "$id")" \
    --argjson interval "${OPSKIT_MONITOR_INTERVAL:-60}" --argjson push "${OPSKIT_MONITOR_PUSH_INTERVAL:-93600}" '
    {admin: $admin, notification: $notification, monitors: [
      {type: "http", name: "\($id) uptime", url: $url, method: "GET", interval: $interval, retryInterval: $interval,
       maxretries: 1, timeout: 48, maxredirects: 10, ignoreTls: false, expiryNotification: false},
      {type: "push", name: "\($id) backup", interval: $push, retryInterval: $push, maxretries: 0}
    ]}'
}

# monitor_sync <id>: create/update both monitors; store the push URL as backup.heartbeat_url
monitor_sync() {
  local id="$1" mhost result token url chost
  require_client "$id" || return 1
  mhost="$(monitor_host_for)" || return 1
  monitor_require "$mhost" || return 1
  result="$(monitor_node_retry "$mhost" "${OPSKIT_ROOT}/templates/monitor/sync.js" "$(monitor_sync_input "$id" "$mhost")")" \
    || { log_fail "monitor sync for ${id} failed: ${result:0:200}"; return 1; }
  token="$(jq -r '.monitors.push.pushToken // empty' <<< "$result")"
  [[ "$token" =~ ^[A-Za-z0-9_-]{16,64}$ ]] || { log_fail "Uptime Kuma returned no push token for ${id}"; return 1; }
  log_ok "monitors for ${id} in Uptime Kuma on ${mhost}: uptime every $(jq -r .monitors.http.interval <<< "$result") s ($(monitor_client_url "$id")), backup watchdog window $(jq -r '.monitors.push.interval / 3600 * 100 | round / 100' <<< "$result") h"
  url="$(monitor_base_url "$mhost")/api/push/${token}"
  yaml_set "$(client_file "$id")" ".backup.heartbeat_url = \"${url}\""
  stack_render "$id" >/dev/null || return 1
  chost="$(yaml_get "$(client_file "$id")" .host.name)"
  if host_run "$chost" test -f "$(host_root "$chost")/clients/${id}/backup.conf" 2>/dev/null; then
    host_put "$chost" "$(rendered_dir "$id")/backup.conf" "$(host_root "$chost")/clients/${id}/backup.conf" 600 || return 1
    log_ok "backup heartbeat for ${id} now goes to Uptime Kuma"
  else
    log_warn "backup heartbeat URL saved in client.yaml; it reaches ${chost} with the next opskit deploy ${id}"
  fi
}

# monitor_remove <id>: delete the client's monitors (offboarding)
monitor_remove() {
  local id="$1" mhost input result
  mhost="$(monitor_host_for)" || return 1
  monitor_require "$mhost" || return 1
  input="$(jq -nc --argjson admin "$(monitor_admin_json "$mhost")" --arg id "$id" \
    '{admin: $admin, action: "remove", remove: ["\($id) uptime", "\($id) backup"]}')"
  result="$(monitor_node_retry "$mhost" "${OPSKIT_ROOT}/templates/monitor/sync.js" "$input")" \
    || { log_fail "could not remove monitors of ${id}: ${result:0:200}"; return 1; }
  log_ok "monitors removed for ${id}: $(jq -r '.removed | join(", ") | if . == "" then "none" else . end' <<< "$result")"
}

# monitor_set_active <id> <pause|resume>: the client's uptime monitor (planned downtime, e.g. an upgrade)
monitor_set_active() {
  local id="$1" action="$2" mhost input result
  mhost="$(monitor_host_for)" || return 1
  monitor_require "$mhost" || return 1
  input="$(jq -nc --argjson admin "$(monitor_admin_json "$mhost")" --arg action "$action" --arg id "$id" \
    '{admin: $admin, action: $action, names: ["\($id) uptime"]}')"
  result="$(monitor_node_retry "$mhost" "${OPSKIT_ROOT}/templates/monitor/sync.js" "$input")" \
    || { log_fail "could not ${action} the uptime monitor of ${id}: ${result:0:200}"; return 1; }
  if [ "$(jq -r '.changed | length' <<< "$result")" = "0" ]; then
    log_warn "no uptime monitor for ${id} in Uptime Kuma (opskit monitor sync ${id})"
    return 0
  fi
  log_ok "uptime monitor of ${id} $([ "$action" = pause ] && echo paused || echo resumed) in Uptime Kuma"
}
